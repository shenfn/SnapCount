// 信号层:事实 → 信号 → 语言 三层架构的中间层
// 数字由数据库算(user_domain_profiles),判断由这里的代码做,语言由模型说。
// 铁律:模型只能引用信号里已算好的数字;闭环校验在 validateVoiceNumbers。
// 口径与结构见 docs/profile-schema-v1.md

// ============================================================
// 画像加载 + 结构校验(v1 手写守卫,等价于 zod parse 失败即降级)
// ============================================================

export interface DomainProfileRow {
  profile: Record<string, unknown>;
  source_count: number;
}

export type DomainProfilesMap = Record<string, DomainProfileRow>;

// deno-lint-ignore no-explicit-any
type SupabaseLike = any;

export async function loadDomainProfiles(
  supabase: SupabaseLike,
  userId: string | null,
): Promise<DomainProfilesMap> {
  if (!userId) return {};
  const { data, error } = await supabase
    .from("user_domain_profiles")
    .select("domain_key,profile,source_count,profile_version")
    .eq("user_id", userId);
  if (error || !data) return {};
  const map: DomainProfilesMap = {};
  for (const row of data) {
    if (!row?.domain_key || !isObj(row.profile)) continue;
    // 版本校验:v 镜像必须匹配,否则视为落后画像,不进信号层
    if ((row.profile as Record<string, unknown>).v !== 1) continue;
    map[row.domain_key] = {
      profile: row.profile as Record<string, unknown>,
      source_count: typeof row.source_count === "number" ? row.source_count : 0,
    };
  }
  return map;
}

function isObj(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

function num(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

function str(v: unknown): string | null {
  return typeof v === "string" && v.trim() !== "" ? v.trim() : null;
}

// "7'34\"/公里" / "4'51\"" / "6.62" → 分钟小数;解析不了返回 null(与 SQL 同口径)
export function parsePaceMinutes(v: unknown): number | null {
  const direct = num(v);
  if (direct !== null) return direct;
  const s = str(v);
  if (!s) return null;
  const m = s.match(/^(\d+)'(\d{1,2})/);
  if (m) return Number(m[1]) + Math.round((Number(m[2]) / 60) * 10000) / 10000;
  return null;
}

// ============================================================
// 信号定义
// ============================================================

export interface DomainSignal {
  kind: string;
  priority: number; // 越小越优先
  fact: string;     // 已算好数字的中文事实句,模型只能转述
  numbers: number[]; // 本信号允许出现在文案里的数字
  countNumbers?: number[]; // 允许出现在"第X次/连续X天"计数表达里的数(严格白名单)
}

export interface CurrentFacts {
  // expense
  amount?: number | null;
  merchant?: string | null;
  category?: string | null;
  platform?: string | null;
  isLateNight?: boolean;
  // sleep
  hours?: number | null;
  score?: number | null;
  // sport
  sportType?: string | null;
  durationMin?: number | null;
  distanceKm?: number | null;
  paceMin?: number | null;
  // food
  mealType?: string | null;
  kcal?: number | null;
  dishNames?: string[];
  // reading
  bookName?: string | null;
  readingMinutes?: number | null;
  progressPercent?: number | null;
  // wallet
  recordKind?: string | null;
  accountName?: string | null;
  walletAmount?: number | null;
}

const MEAL_LABELS: Record<string, string> = {
  breakfast: "早餐", lunch: "午餐", dinner: "晚餐", snack: "加餐",
};

function pushNums(arr: number[], ...vals: Array<number | null | undefined>) {
  for (const v of vals) if (typeof v === "number" && Number.isFinite(v)) arr.push(v);
}

// ============================================================
// 各域信号规则(与 docs/profile-schema-v1.md 一一对应)
// ============================================================

function expenseSignals(profile: Record<string, unknown>, cur: CurrentFacts): DomainSignal[] {
  const out: DomainSignal[] = [];
  const merchantStats = isObj(profile.merchant_stats) ? profile.merchant_stats : {};
  const categoryStats = isObj(profile.category_stats) ? profile.category_stats : {};

  // merchant_repeat:week_count 是本周已入库真数,+1 含当前这笔;≥3 才说
  if (cur.merchant && isObj(merchantStats[cur.merchant])) {
    const ms = merchantStats[cur.merchant] as Record<string, unknown>;
    const weekCount = num(ms.week_count);
    if (weekCount !== null && weekCount + 1 >= 3) {
      const n = weekCount + 1;
      const nums: number[] = [n];
      pushNums(nums, num(ms.avg_amount), cur.amount);
      out.push({
        kind: "merchant_repeat", priority: 1,
        fact: `本自然周(周一起算)在「${cur.merchant}」已是第 ${n} 次消费(含本笔);该店近90天平均单笔 ${num(ms.avg_amount) ?? "?"} 元`,
        numbers: nums,
        countNumbers: [n],
      });
    }
  }

  // unusual_amount:高于该分类近30天 p90 才说,样本≥5 才可信
  if (cur.category && cur.amount !== null && cur.amount !== undefined && isObj(categoryStats[cur.category])) {
    const cs = categoryStats[cur.category] as Record<string, unknown>;
    const p90 = num(cs.p90_amount);
    const monthCount = num(cs.month_count);
    if (p90 !== null && monthCount !== null && monthCount >= 5 && cur.amount > p90) {
      const nums: number[] = [];
      pushNums(nums, cur.amount, p90, num(cs.median_amount));
      out.push({
        kind: "unusual_amount", priority: 2,
        fact: `本笔 ${cur.amount} 元高于你近30天该类 90% 的单笔(p90=${p90},中位 ${num(cs.median_amount) ?? "?"})`,
        numbers: nums,
      });
    }
  }

  // week_velocity:本周 vs 上周同期,±40% 才说
  if (isObj(profile.week_velocity)) {
    const wv = profile.week_velocity as Record<string, unknown>;
    const curTotal = num(wv.cur_total);
    const prevTotal = num(wv.prev_total_same_span);
    if (curTotal !== null && prevTotal !== null && prevTotal >= 50) {
      const ratio = (curTotal - prevTotal) / prevTotal;
      if (Math.abs(ratio) >= 0.4) {
        // 衍生数全部预先算好喂给模型;否则模型自己加减,算出的数必被闭环校验拦下
        const diff = Math.round(Math.abs(curTotal - prevTotal) * 100) / 100;
        const inclTotal = cur.amount !== null && cur.amount !== undefined
          ? Math.round((curTotal + cur.amount) * 100) / 100
          : null;
        const nums: number[] = [];
        pushNums(nums, curTotal, prevTotal, diff, inclTotal);
        out.push({
          kind: "week_velocity", priority: 3,
          fact: `本周已消费 ${curTotal} 元(不含本笔)${inclTotal !== null ? `,加上本笔共 ${inclTotal} 元` : ""};上周同期 ${prevTotal} 元,相差 ${diff} 元(${ratio > 0 ? "明显放开" : "明显收着"})`,
          numbers: nums,
        });
      }
    }
  }

  // late_night_spend:今天 21 点后 ≥2 笔(含本笔)才说
  if (isObj(profile.today)) {
    const today = profile.today as Record<string, unknown>;
    const lateCount = (num(today.late_night_count) ?? 0) + (cur.isLateNight ? 1 : 0);
    if (lateCount >= 2) {
      out.push({
        kind: "late_night_spend", priority: 4,
        fact: `今天已有 ${lateCount} 笔 21 点后的消费(含本笔)`,
        numbers: [lateCount, 21],
        countNumbers: [lateCount],
      });
    }
  }
  // 默认信号：所有条件信号未命中时，基于本条记录产出
  if (out.length === 0) {
    const parts: string[] = [];
    const nums: number[] = [];
    if (cur.amount !== null && cur.amount !== undefined) {
      parts.push(`本笔支出 ${cur.amount} 元`);
      nums.push(cur.amount);
    }
    if (cur.merchant) parts.push(`商户「${cur.merchant}」`);
    if (cur.category) parts.push(`分类 ${cur.category}`);
    if (cur.platform) parts.push(`支付方式 ${cur.platform}`);
    if (parts.length > 0) {
      out.push({
        kind: "record_acknowledge", priority: 99,
        fact: parts.join("，"),
        numbers: nums,
      });
    }
  }
  return out;
}

function sleepSignals(profile: Record<string, unknown>, cur: CurrentFacts): DomainSignal[] {
  const out: DomainSignal[] = [];
  const baseline = isObj(profile.baseline) ? profile.baseline : null;
  const n = baseline ? num(baseline.n) : null;
  const median = baseline ? num(baseline.median_hours) : null;
  const p25 = baseline ? num(baseline.p25) : null;
  const p75 = baseline ? num(baseline.p75) : null;

  // vs_baseline:n≥7 基线才可信;n<7 不出信号(语言层只围绕本条,不引用世界标准)
  if (cur.hours !== null && cur.hours !== undefined && n !== null && n >= 7 && median !== null) {
    const h = Math.round(cur.hours * 100) / 100;
    const nums: number[] = [];
    pushNums(nums, h, median, n, p25, p75);
    if (Math.abs(h - median) < 0.75) {
      out.push({
        kind: "vs_baseline_normal", priority: 1,
        fact: `这晚 ${h} 小时,和你近30天自己的中位数 ${median} 小时差不多(样本 ${n} 晚),属于你的正常水平`,
        numbers: nums,
      });
    } else if (p25 !== null && h < p25) {
      out.push({
        kind: "vs_baseline_below", priority: 1,
        fact: `这晚 ${h} 小时,低于你自己近30天的常态区间(中位 ${median},下四分位 ${p25},样本 ${n} 晚)`,
        numbers: nums,
      });
    } else if (p75 !== null && h > p75) {
      out.push({
        kind: "vs_baseline_above", priority: 1,
        fact: `这晚 ${h} 小时,比你自己近30天的常态更充足(中位 ${median},上四分位 ${p75},样本 ${n} 晚)`,
        numbers: nums,
      });
    }
  }

  // consecutive_short:近几夜 + 本夜均低于 p25 才说
  if (
    cur.hours !== null && cur.hours !== undefined && p25 !== null && cur.hours < p25 &&
    Array.isArray(profile.recent_nights)
  ) {
    let run = 0;
    for (const nightRaw of profile.recent_nights as unknown[]) {
      if (!isObj(nightRaw)) break;
      const nh = num(nightRaw.hours);
      if (nh !== null && nh < p25) run += 1;
      else break;
    }
    if (run >= 1) {
      out.push({
        kind: "consecutive_short", priority: 2,
        fact: `加上这晚,已连续 ${run + 1} 晚低于你平时的睡眠水平`,
        numbers: [run + 1],
        countNumbers: [run + 1],
      });
    }
  }
  // 默认信号
  if (out.length === 0 && cur.hours !== null && cur.hours !== undefined) {
    const h = Math.round(cur.hours * 100) / 100;
    const parts: string[] = [`本晚睡眠 ${h} 小时`];
    const nums: number[] = [h];
    if (cur.score !== null && cur.score !== undefined) {
      parts.push(`评分 ${cur.score}`);
      nums.push(cur.score);
    }
    out.push({
      kind: "record_acknowledge", priority: 99,
      fact: parts.join("，"),
      numbers: nums,
    });
  }
  return out;
}

function sportSignals(profile: Record<string, unknown>, cur: CurrentFacts): DomainSignal[] {
  const out: DomainSignal[] = [];
  const typeStats = isObj(profile.type_stats) ? profile.type_stats : {};

  // pace_vs_self:同类型 vs 自己中位配速,样本≥3 才可信
  if (cur.sportType && cur.paceMin !== null && cur.paceMin !== undefined && isObj(typeStats[cur.sportType])) {
    const ts = typeStats[cur.sportType] as Record<string, unknown>;
    const medPace = num(ts.median_pace);
    const bestPace = num(ts.best_pace);
    const cnt = num(ts.count_90d);
    if (medPace !== null && cnt !== null && cnt >= 3) {
      const curPace = Math.round(cur.paceMin * 100) / 100;
      const nums: number[] = [];
      pushNums(nums, curPace, medPace, bestPace);
      out.push({
        kind: "pace_vs_self", priority: 1,
        fact: `本次「${cur.sportType}」配速约 ${curPace} 分钟/公里,你近90天同类中位约 ${medPace}${bestPace !== null ? `,历史最好 ${bestPace}` : ""}(与自己比,不与别人比)`,
        numbers: nums,
      });
    }
  }

  // rhythm_return:歇了 ≥7 天后再运动
  const gapDays = num(profile.gap_days);
  if (gapDays !== null && gapDays >= 7) {
    out.push({
      kind: "rhythm_return", priority: 2,
      fact: `距你上次运动已 ${gapDays} 天,今天重新动起来了`,
      numbers: [gapDays],
    });
  }

  // weekly_progress:本周次数(含本次) vs 近4周平均节奏
  if (isObj(profile.current_week) && isObj(profile.weekly_rhythm)) {
    const cw = profile.current_week as Record<string, unknown>;
    const wr = profile.weekly_rhythm as Record<string, unknown>;
    const sessions = num(cw.sessions);
    const spw = num(wr.sessions_per_week_4w);
    if (sessions !== null && spw !== null && spw >= 1) {
      out.push({
        kind: "weekly_progress", priority: 3,
        fact: `算上本次,这是本自然周第 ${sessions + 1} 次运动;你近4周平均每周 ${spw} 次`,
        numbers: [sessions + 1, spw, 4],
        countNumbers: [sessions + 1],
      });
    }
  }
  // 默认信号
  if (out.length === 0) {
    const parts: string[] = [];
    const nums: number[] = [];
    if (cur.sportType) parts.push(`本次${cur.sportType}运动`);
    if (cur.durationMin !== null && cur.durationMin !== undefined) {
      parts.push(`${cur.durationMin} 分钟`);
      nums.push(cur.durationMin);
    }
    if (cur.distanceKm !== null && cur.distanceKm !== undefined) {
      parts.push(`距离 ${cur.distanceKm} 公里`);
      nums.push(cur.distanceKm);
    }
    if (cur.paceMin !== null && cur.paceMin !== undefined) {
      parts.push(`配速 ${cur.paceMin} 分钟/公里`);
      nums.push(cur.paceMin);
    }
    if (parts.length > 0) {
      out.push({
        kind: "record_acknowledge", priority: 99,
        fact: parts.join("，"),
        numbers: nums,
      });
    }
  }
  return out;
}

function foodSignals(profile: Record<string, unknown>, cur: CurrentFacts): DomainSignal[] {
  const out: DomainSignal[] = [];
  const mealBaseline = isObj(profile.meal_baseline) ? profile.meal_baseline : {};

  // meal_vs_baseline:本餐 vs 同餐次自己的中位,样本≥5 才可信
  if (cur.mealType && cur.kcal !== null && cur.kcal !== undefined && isObj(mealBaseline[cur.mealType])) {
    const mb = mealBaseline[cur.mealType] as Record<string, unknown>;
    const med = num(mb.median_kcal);
    const mbN = num(mb.n);
    if (med !== null && mbN !== null && mbN >= 5 && med > 0) {
      const label = MEAL_LABELS[cur.mealType] ?? cur.mealType;
      const kcal = Math.round(cur.kcal);
      const nums: number[] = [kcal, med, mbN];
      const ratio = kcal / med;
      const verdict = ratio >= 1.4 ? "偏重" : ratio <= 0.6 ? "偏轻" : "和平时差不多";
      out.push({
        kind: "meal_vs_baseline", priority: 1,
        fact: `这顿约 ${kcal} 千卡,你近30天${label}中位约 ${med} 千卡(样本 ${mbN} 次),${verdict}`,
        numbers: nums,
      });
    }
  }

  // dish_ritual:当前菜品命中近30天出现≥3次的常点
  if (Array.isArray(profile.recurring_dishes) && cur.dishNames?.length) {
    const recurring = (profile.recurring_dishes as unknown[]).filter((d): d is string => typeof d === "string");
    const hit = cur.dishNames.find((d) => recurring.some((r) => r === d || d.includes(r) || r.includes(d)));
    if (hit) {
      out.push({
        kind: "dish_ritual", priority: 2,
        fact: `「${hit}」是你近30天反复出现的菜(至少 3 次),算是你的常点`,
        numbers: [3, 30],
      });
    }
  }

  // late_snack_streak:本次是 21 点后加餐,且近两周已有 ≥2 次
  const lateSnack = num(profile.late_snack_14d);
  if (cur.mealType === "snack" && cur.isLateNight && lateSnack !== null && lateSnack >= 2) {
    out.push({
      kind: "late_snack_streak", priority: 3,
      fact: `近两周你已有 ${lateSnack} 次 21 点后的加餐(不含本次)`,
      numbers: [lateSnack, lateSnack + 1, 21],
      countNumbers: [lateSnack, lateSnack + 1],
    });
  }
  // 默认信号
  if (out.length === 0) {
    const parts: string[] = [];
    const nums: number[] = [];
    const label = cur.mealType ? (MEAL_LABELS[cur.mealType] ?? cur.mealType) : null;
    if (label) parts.push(`本次${label}`);
    if (cur.kcal !== null && cur.kcal !== undefined) {
      parts.push(`约 ${cur.kcal} 千卡`);
      nums.push(cur.kcal);
    }
    if (cur.dishNames?.length) {
      parts.push(`菜品：${cur.dishNames.join("、")}`);
    }
    if (parts.length > 0) {
      out.push({
        kind: "record_acknowledge", priority: 99,
        fact: parts.join("，"),
        numbers: nums,
      });
    }
  }
  return out;
}

function readingSignals(profile: Record<string, unknown>, cur: CurrentFacts): DomainSignal[] {
  const out: DomainSignal[] = [];
  const currentBook = isObj(profile.current_book) ? profile.current_book : null;

  // book_switch:换书了
  if (currentBook && cur.bookName && str(currentBook.name) && cur.bookName !== currentBook.name) {
    const oldName = str(currentBook.name)!;
    const oldProgress = num(currentBook.last_progress_percent);
    const nums: number[] = [];
    pushNums(nums, oldProgress);
    out.push({
      kind: "book_switch", priority: 1,
      fact: `你换了书:之前在读《${oldName}》${oldProgress !== null ? `(进度 ${oldProgress}%)` : ""},这次是《${cur.bookName}》`,
      numbers: nums,
    });
  }

  // progress_momentum:同一本书,进度往前推了
  if (
    currentBook && cur.bookName && cur.bookName === currentBook.name &&
    cur.progressPercent !== null && cur.progressPercent !== undefined
  ) {
    const last = num(currentBook.last_progress_percent);
    if (last !== null && cur.progressPercent > last) {
      out.push({
        kind: "progress_momentum", priority: 2,
        fact: `《${cur.bookName}》从上次的 ${last}% 推进到 ${cur.progressPercent}%`,
        numbers: [last, cur.progressPercent],
      });
    }
  }

  // streak:连续阅读天数(current_days 截至昨天,今天这条 +1)
  if (isObj(profile.streak)) {
    const st = profile.streak as Record<string, unknown>;
    const days = num(st.current_days);
    const best = num(st.best_30d);
    if (days !== null && days >= 2) {
      const nums: number[] = [days + 1];
      pushNums(nums, best);
      out.push({
        kind: "streak", priority: 3,
        fact: `算上今天,你已连续 ${days + 1} 天阅读${best !== null ? `(近30天最长 ${best} 天)` : ""}`,
        numbers: nums,
        countNumbers: best !== null ? [days + 1, best] : [days + 1],
      });
    }
  }
  // 默认信号
  if (out.length === 0) {
    const parts: string[] = [];
    const nums: number[] = [];
    if (cur.bookName) parts.push(`本次阅读《${cur.bookName}》`);
    if (cur.readingMinutes !== null && cur.readingMinutes !== undefined) {
      parts.push(`${cur.readingMinutes} 分钟`);
      nums.push(cur.readingMinutes);
    }
    if (cur.progressPercent !== null && cur.progressPercent !== undefined) {
      parts.push(`进度 ${cur.progressPercent}%`);
      nums.push(cur.progressPercent);
    }
    if (parts.length > 0) {
      out.push({
        kind: "record_acknowledge", priority: 99,
        fact: parts.join("，"),
        numbers: nums,
      });
    }
  }
  return out;
}

function walletSignals(profile: Record<string, unknown>, cur: CurrentFacts): DomainSignal[] {
  const out: DomainSignal[] = [];

  // liability_delta:本次快照 vs 画像里的最近一次,只说方向和幅度
  if (
    cur.recordKind === "liability_snapshot" && cur.accountName &&
    cur.walletAmount !== null && cur.walletAmount !== undefined &&
    isObj(profile.liabilities) && isObj((profile.liabilities as Record<string, unknown>)[cur.accountName])
  ) {
    const li = (profile.liabilities as Record<string, unknown>)[cur.accountName] as Record<string, unknown>;
    const latest = num(li.latest_amount);
    if (latest !== null && Math.abs(cur.walletAmount - latest) >= 1) {
      const delta = Math.round((cur.walletAmount - latest) * 100) / 100;
      out.push({
        kind: "liability_delta", priority: 1,
        fact: `「${cur.accountName}」待还从上次记录的 ${latest} 元变为本次 ${cur.walletAmount} 元(${delta > 0 ? "涨" : "降"}了 ${Math.abs(delta)} 元)`,
        numbers: [latest, cur.walletAmount, Math.abs(delta)],
      });
    }
  }

  // due_reminder:due_soon 里 3 天内到期的账单
  if (Array.isArray(profile.due_soon)) {
    for (const itemRaw of profile.due_soon as unknown[]) {
      if (!isObj(itemRaw)) continue;
      const account = str(itemRaw.account);
      const dueDate = str(itemRaw.due_date);
      const amt = num(itemRaw.amount);
      if (!account || !dueDate) continue;
      const dueMs = Date.parse(`${dueDate}T00:00:00+08:00`);
      if (Number.isNaN(dueMs)) continue;
      const daysLeft = Math.ceil((dueMs - Date.now()) / 86400000);
      if (daysLeft >= 0 && daysLeft <= 3) {
        const nums: number[] = [daysLeft];
        pushNums(nums, amt);
        out.push({
          kind: "due_reminder", priority: 2,
          fact: `「${account}」${dueDate} 到期${amt !== null ? `,待还 ${amt} 元` : ""}(还有 ${daysLeft} 天)`,
          numbers: nums,
        });
        break; // 只提最近的一笔
      }
    }
  }
  // 默认信号
  if (out.length === 0) {
    const parts: string[] = [];
    const nums: number[] = [];
    if (cur.accountName) parts.push(`本次记录「${cur.accountName}」`);
    if (cur.recordKind) parts.push(cur.recordKind);
    if (cur.walletAmount !== null && cur.walletAmount !== undefined) {
      parts.push(`金额 ${cur.walletAmount} 元`);
      nums.push(cur.walletAmount);
    }
    if (parts.length > 0) {
      out.push({
        kind: "record_acknowledge", priority: 99,
        fact: parts.join("，"),
        numbers: nums,
      });
    }
  }
  return out;
}

// ============================================================
// 信号选择入口:每域最多 2 条,按 priority 排序,同 kind 去重
// ============================================================

export function selectSignals(
  domainKey: string,
  profiles: DomainProfilesMap,
  cur: CurrentFacts,
): DomainSignal[] {
  const row = profiles[domainKey];
  if (!row || !isObj(row.profile)) return [];
  const profile = row.profile;
  let signals: DomainSignal[] = [];
  switch (domainKey) {
    case "expense": signals = expenseSignals(profile, cur); break;
    case "sleep":   signals = sleepSignals(profile, cur); break;
    case "sport":   signals = sportSignals(profile, cur); break;
    case "food":    signals = foodSignals(profile, cur); break;
    case "reading": signals = readingSignals(profile, cur); break;
    case "wallet":  signals = walletSignals(profile, cur); break;
    default: return [];
  }
  const seen = new Set<string>();
  return signals
    .sort((a, b) => a.priority - b.priority)
    .filter((s) => (seen.has(s.kind) ? false : (seen.add(s.kind), true)))
    .slice(0, 2);
}

// ============================================================
// 数字闭环校验:文案里的数字必须是"信号数字 ∪ 本条记录数字"的子集
// 违规 → 调用方丢弃 AI 文案,退回规则渲染
// ============================================================

const CN_NUM: Record<string, number> = {
  "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
  "六": 6, "七": 7, "八": 8, "九": 9, "十": 10,
};

function cnToNumber(s: string): number | null {
  if (/^\d+$/.test(s)) return Number(s);
  if (s in CN_NUM) return CN_NUM[s];
  if (s.length === 2 && s[0] === "十" && s[1] in CN_NUM) return 10 + CN_NUM[s[1]]; // 十一..十九
  if (s.length === 2 && s[0] in CN_NUM && s[1] === "十") return CN_NUM[s[0]] * 10;  // 二十/三十...
  return null;
}

export function extractDigitNumbers(text: string): number[] {
  const out: number[] = [];
  for (const m of text.matchAll(/\d+(?:\.\d+)?/g)) {
    const n = Number(m[0]);
    if (Number.isFinite(n)) out.push(n);
  }
  return out;
}

export interface NumberValidationResult {
  ok: boolean;
  violations: string[];
  /** 与入参 generatedTexts 对齐:该下标文本存在违规 */
  badIndexes: number[];
}

// allowedSources:信号 fact 文本 + 本条记录字段 JSON。数字宽松匹配(整数/一位小数视为同数)。
// 计数表达("第X次/连续X天")单独用严格白名单 countNumbers:
// 只有计数类信号显式声明的数才能进计数表达,防止金额/时长取整后泄漏放行幻觉计数。
// 逐句校验:只标记违规的那条文本,调用方可保留其余合规字段(不整体丢弃)。
export function validateVoiceNumbers(
  generatedTexts: Array<string | null | undefined>,
  signals: DomainSignal[],
  recordFactsJson: string,
): NumberValidationResult {
  const allowed = new Set<string>();
  const countAllowed = new Set<string>();
  const addNum = (n: number) => {
    allowed.add(String(n));
    allowed.add(String(Math.round(n)));
    allowed.add(String(Math.floor(n)));
    allowed.add(String(Math.ceil(n)));
    allowed.add(String(Math.round(n * 10) / 10));
  };
  for (const s of signals) {
    for (const n of s.numbers) addNum(n);
    for (const n of s.countNumbers ?? []) countAllowed.add(String(n));
    for (const n of extractDigitNumbers(s.fact)) addNum(n);
  }
  for (const n of extractDigitNumbers(recordFactsJson)) addNum(n);

  const violations: string[] = [];
  const badIndexes: number[] = [];

  generatedTexts.forEach((text, idx) => {
    if (!text) return;
    let bad = false;
    // 1) 裸数字必须在允许集内
    for (const n of extractDigitNumbers(text)) {
      const keys = [String(n), String(Math.round(n)), String(Math.round(n * 10) / 10)];
      if (!keys.some((k) => allowed.has(k))) {
        violations.push(`数字 ${n} 不在信号/记录允许集内: "${text.slice(0, 40)}"`);
        bad = true;
      }
    }
    // 2) "第X次/笔/顿/天/晚" 计数表达:数值必须来自计数信号显式声明
    for (const m of text.matchAll(/(?:第|连续|连着)\s*([一二两三四五六七八九十\d]{1,3})\s*(?:次|笔|顿|天|晚|家)/g)) {
      const n = cnToNumber(m[1]);
      if (countAllowed.size === 0) {
        violations.push(`计数表达 "${m[0]}" 无计数信号支撑`);
        bad = true;
      } else if (n !== null && !countAllowed.has(String(n))) {
        violations.push(`计数 "${m[0]}" 数值不可追溯到计数信号`);
        bad = true;
      }
    }
    if (bad) badIndexes.push(idx);
  });
  return { ok: violations.length === 0, violations, badIndexes };
}
