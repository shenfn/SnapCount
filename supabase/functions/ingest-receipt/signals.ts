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
  numberFacts?: DomainSignalNumberFact[]; // 数字与语义、单位、统计口径的候选级绑定
}

export interface DomainSignalNumberFact {
  value: number;
  meaning: string | null;
  role: "count" | "measure";
  unit?: string;
  scope?: string;
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

function normalizeEntityKey(value: string): string {
  return value
    .normalize("NFKC")
    .toLocaleLowerCase("zh-CN")
    .replace(/[\s\u00a0\u3000·•・_\-\/\\()[\]（）【】]/g, "");
}

function mergedMerchantStats(
  merchantStats: Record<string, unknown>,
  merchant: string,
): { weekCount: number | null; averageAmount: number | null } | null {
  const normalizedMerchant = normalizeEntityKey(merchant);
  const matches = Object.entries(merchantStats)
    .filter(([name, value]) => normalizeEntityKey(name) === normalizedMerchant && isObj(value))
    .map(([, value]) => value as Record<string, unknown>);
  if (matches.length === 0) return null;

  const weekCounts = matches.map((item) => num(item.week_count)).filter((value): value is number => value !== null);
  const weekCount = weekCounts.length > 0 ? weekCounts.reduce((sum, value) => sum + value, 0) : null;
  let weightedTotal = 0;
  let totalWeight = 0;
  const fallbackAverages: number[] = [];
  for (const item of matches) {
    const average = num(item.avg_amount);
    if (average === null) continue;
    fallbackAverages.push(average);
    const weight = num(item.count_90d) ?? num(item.month_count);
    if (weight === null || weight <= 0) continue;
    weightedTotal += average * weight;
    totalWeight += weight;
  }
  const averageAmount = totalWeight > 0
    ? Math.round((weightedTotal / totalWeight) * 100) / 100
    : fallbackAverages.length > 0
      ? Math.round((fallbackAverages.reduce((sum, value) => sum + value, 0) / fallbackAverages.length) * 100) / 100
      : null;

  return { weekCount, averageAmount };
}

// ============================================================
// 各域信号规则(与 docs/profile-schema-v1.md 一一对应)
// ============================================================

function expenseSignals(profile: Record<string, unknown>, cur: CurrentFacts): DomainSignal[] {
  const out: DomainSignal[] = [];
  const merchantStats = isObj(profile.merchant_stats) ? profile.merchant_stats : {};
  const categoryStats = isObj(profile.category_stats) ? profile.category_stats : {};

  // merchant_repeat:week_count 是本周已入库真数,+1 含当前这笔;≥3 才说
  if (cur.merchant) {
    const merchantSummary = mergedMerchantStats(merchantStats, cur.merchant);
    const weekCount = merchantSummary?.weekCount ?? null;
    if (weekCount !== null && weekCount + 1 >= 3) {
      const n = weekCount + 1;
      const nums: number[] = [n];
      pushNums(nums, merchantSummary?.averageAmount, cur.amount);
      out.push({
        kind: "merchant_repeat", priority: 1,
        fact: `本自然周(周一起算)在「${cur.merchant}」已是第 ${n} 次消费(含本笔);该店近90天平均单笔 ${merchantSummary?.averageAmount ?? "?"} 元`,
        numbers: nums,
        countNumbers: [n],
        numberFacts: [
          {
            value: n,
            meaning: "current_week_merchant_occurrence_count",
            role: "count",
            unit: "occurrence",
            scope: "week:current",
          },
          ...(merchantSummary?.averageAmount !== null && merchantSummary?.averageAmount !== undefined
            ? [{
              value: merchantSummary.averageAmount,
              meaning: "rolling_90d_merchant_average_amount",
              role: "measure" as const,
              unit: "currency",
              scope: "rolling:90d",
            }]
            : []),
          ...(cur.amount !== null && cur.amount !== undefined
            ? [{
              value: cur.amount,
              meaning: "current_record_amount",
              role: "measure" as const,
              unit: "currency",
              scope: "record:current",
            }]
            : []),
        ],
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

function incomeSignals(cur: CurrentFacts): DomainSignal[] {
  const parts: string[] = [];
  const numbers: number[] = [];
  if (cur.amount !== null && cur.amount !== undefined) {
    parts.push(`本笔收入 ${cur.amount} 元`);
    numbers.push(cur.amount);
  }
  if (cur.merchant) parts.push(`来源「${cur.merchant}」`);
  if (cur.category) parts.push(`类型 ${cur.category}`);
  if (parts.length === 0) return [];
  return [{
    kind: "record_acknowledge",
    priority: 99,
    fact: parts.join("，"),
    numbers,
  }];
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
  const profile = row && isObj(row.profile) ? row.profile : {};
  let signals: DomainSignal[] = [];
  switch (domainKey) {
    case "expense": signals = expenseSignals(profile, cur); break;
    case "income":  signals = incomeSignals(cur); break;
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

export function hasUnsupportedFinanceCompanionClaim(text: string): boolean {
  // 统计次数不在这里拦截：是否有来源、数字和时间口径由 validateModelTone
  // 按 Context Packet/Signals 校验。这里仅保留与事实来源无关的空泛或判决式套话。
  return /(第几笔|凑个单|小确幸|给生活充个值|看来是|应该不错|确实地道)/.test(text);
}

// 画像统计的次数、周期、趋势和比较必须由代码提供来源。模型可以忠实转述，
// 但 validateModelTone 会拒绝没有候选支撑或改写了时间窗口的表述。
export function hasModelOwnedStatisticalClaim(text: string): boolean {
  const compact = text.replace(/\s+/g, "");
  return /(?:本|这|上)(?:自然)?周|(?:本|这|上)个月|本月|上月|近(?:两|三|四|[一二两三四五六七八九十\d]+)(?:天|周|月|晚)|过去(?:两|三|四|[一二两三四五六七八九十\d]+)(?:天|周|月)/.test(compact)
    || /(?:第|连续|连着|已有|累计)[一二两三四五六七八九十百\d]+(?:次|笔|顿|天|晚|家|周|月)/.test(compact)
    || /[一二两三四五六七八九十百\d]+(?:次|笔|顿|天|晚|家|周|月|回)/.test(compact)
    || /(?:比|较)(?:昨天|之前|过去|上次|上周|上月|平时|常态|平均|中位|历史)/.test(compact)
    || /(?:平均|中位数?|四分位|百分位|历史最好|历史最高|历史最低|连续偏|反复出现|高频|常点|周节奏|月节奏)/.test(compact)
    || /(?:今天|今晚|今早).{0,10}(?:已有|累计|第[一二两三四五六七八九十百\d]+|连续)/.test(compact)
    || /(?:最近|近来).{0,12}(?:总是|一直|经常|频繁|反复|又)/.test(compact);
}

type StatisticalScope = string;

type StatisticalUnit = "occurrence" | "day" | "week" | "month" | "currency";

interface BoundStatisticalClaim {
  value: number;
  meaning: string;
  unit: StatisticalUnit | string;
  scope: StatisticalScope;
}

interface ScopeMarker {
  start: number;
  end: number;
  scope: StatisticalScope;
  numberStart?: number;
  numberEnd?: number;
}

function parseChineseCardinal(s: string): number | null {
  if (/^\d+$/.test(s)) return Number(s);
  const digits: Record<string, number> = {
    "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
    "六": 6, "七": 7, "八": 8, "九": 9, "零": 0,
  };
  const units: Record<string, number> = { "十": 10, "百": 100, "千": 1000 };
  if (!s || [...s].some((char) => !(char in digits) && !(char in units))) return null;
  let total = 0;
  let section = 0;
  for (const char of s) {
    if (char in digits) {
      section += digits[char];
      continue;
    }
    const unit = units[char];
    total += (section || 1) * unit;
    section = 0;
  }
  const result = total + section;
  return result > 0 ? result : null;
}

function rollingWindowKey(value: string, unit: string): string | null {
  const parsed = parseChineseCardinal(value);
  if (parsed === null) return null;
  if (unit === "天" || unit === "晚") return `rolling:${parsed}d`;
  if (unit === "周") return `rolling:${parsed * 7}d`;
  if (unit === "月") return `rolling:${parsed}m`;
  return null;
}

function scopeMarkers(text: string): ScopeMarker[] {
  const markers: ScopeMarker[] = [];
  const pushStatic = (pattern: RegExp, scope: StatisticalScope) => {
    for (const match of text.matchAll(pattern)) {
      const start = match.index ?? 0;
      markers.push({ start, end: start + match[0].length, scope });
    }
  };
  pushStatic(/(?:本|这)(?:自然)?周/g, "week:current");
  pushStatic(/上(?:自然)?周/g, "week:previous");
  pushStatic(/(?:本|这)个?月|本月/g, "month:current");
  pushStatic(/上个?月|上月/g, "month:previous");
  pushStatic(/(?:今天|今晚|今早)/g, "day:today");
  pushStatic(/(?:本|这)(?:笔|次|晚|顿|条)|当前记录/g, "record:current");
  pushStatic(/历史/g, "history");
  for (const match of text.matchAll(/(?:近|过去)([一二两三四五六七八九十百\d]+)(天|周|月|晚)/g)) {
    const scope = rollingWindowKey(match[1], match[2]);
    if (!scope) continue;
    const start = match.index ?? 0;
    const relativeNumberStart = match[0].indexOf(match[1]);
    markers.push({
      start,
      end: start + match[0].length,
      scope,
      numberStart: start + relativeNumberStart,
      numberEnd: start + relativeNumberStart + match[1].length,
    });
  }
  return markers.sort((left, right) => left.start - right.start || left.end - right.end);
}

function segmentBounds(text: string, index: number): { start: number; end: number } {
  const separators = /[;；。！？!?\n]/;
  let start = 0;
  for (let cursor = index - 1; cursor >= 0; cursor -= 1) {
    if (separators.test(text[cursor])) {
      start = cursor + 1;
      break;
    }
  }
  let end = text.length;
  for (let cursor = index; cursor < text.length; cursor += 1) {
    if (separators.test(text[cursor])) {
      end = cursor;
      break;
    }
  }
  return { start, end };
}

function scopeNearNumber(text: string, numberStart: number, markers: ScopeMarker[]): StatisticalScope {
  const bounds = segmentBounds(text, numberStart);
  const before = markers.filter((marker) =>
    marker.start >= bounds.start && marker.end <= numberStart
  );
  if (before.length > 0) return before[before.length - 1].scope;
  const after = markers.find((marker) => marker.start >= numberStart && marker.end <= bounds.end);
  return after?.scope ?? "unspecified";
}

function isWindowNumber(start: number, end: number, markers: ScopeMarker[]): boolean {
  return markers.some((marker) =>
    marker.numberStart !== undefined && marker.numberEnd !== undefined &&
    start >= marker.numberStart && end <= marker.numberEnd
  );
}

function numberValue(value: string): number | null {
  const normalized = value.replace(/,/g, "");
  const numeric = Number(normalized);
  return Number.isFinite(numeric) ? numeric : parseChineseCardinal(normalized);
}

function countMeaning(
  text: string,
  numberStart: number,
  unit: string,
  value: number,
): string {
  const bounds = segmentBounds(text, numberStart);
  const before = text.slice(Math.max(bounds.start, numberStart - 20), numberStart);
  if (/样本[^一二两三四五六七八九十百千\d]*$/.test(before)) return "sample_count";
  if (/平均每(?:天|周|月)[^一二两三四五六七八九十百千\d]*$|平均[^一二两三四五六七八九十百千\d]*$/.test(before)) {
    return "average_occurrence_count";
  }
  if (/(?:连续|连着)[^一二两三四五六七八九十百千\d]*$/.test(before)) return "consecutive_count";
  if (/至少[^一二两三四五六七八九十百千\d]*$/.test(before)) return "minimum_occurrence_count";
  if (value === 1 && /第[^一二两三四五六七八九十百千\d]*$/.test(before)) return "first_occurrence_count";
  if (unit === "天" || unit === "晚") return "day_count";
  if (unit === "周") return "week_count";
  if (unit === "月") return "month_count";
  return "occurrence_count";
}

function amountMeaning(text: string, numberStart: number): string {
  const bounds = segmentBounds(text, numberStart);
  const before = text.slice(Math.max(bounds.start, numberStart - 24), numberStart);
  if (/(?:平均单笔|平均每笔|均价|平均)[^\d]*$/.test(before)) return "average_amount";
  if (/(?:中位数?|中位)[^\d]*$/.test(before)) return "median_amount";
  if (/(?:p\s*90|百分位)[^\d]*$/i.test(before)) return "percentile_amount";
  if (/(?:相差|差额|增加|减少|多了|少了|涨了|降了)[^\d]*$/.test(before)) return "delta_amount";
  if (/(?:累计|总额|合计|共|已消费|已支出|已收入)[^\d]*$/.test(before)) return "total_amount";
  if (/(?:本笔|本次|这笔|这次|当前)[^\d]*$/.test(before)) return "current_amount";
  return "amount";
}

function claimIsStatistical(claim: BoundStatisticalClaim): boolean {
  if (claim.unit !== "currency") return true;
  return claim.scope !== "record:current" && claim.scope !== "unspecified";
}

function boundStatisticalClaims(text: string): BoundStatisticalClaim[] {
  const compact = text.replace(/\s+/g, "");
  const markers = scopeMarkers(compact);
  const claims: BoundStatisticalClaim[] = [];
  const countPattern = /(第|连续|连着|已有|已经|已是|累计|至少|超过|共|样本)?([一二两三四五六七八九十百千\d]{1,8})(次|笔|顿|天|晚|家|周|月|回)/g;
  for (const match of compact.matchAll(countPattern)) {
    const rawValue = match[2];
    const relativeStart = match[0].indexOf(rawValue);
    const start = (match.index ?? 0) + relativeStart;
    const end = start + rawValue.length;
    if (isWindowNumber(start, end, markers)) continue;
    const value = numberValue(rawValue);
    if (value === null) continue;
    const rawUnit = match[3];
    const unit: StatisticalUnit = rawUnit === "天" || rawUnit === "晚"
      ? "day"
      : rawUnit === "周"
        ? "week"
        : rawUnit === "月"
          ? "month"
          : "occurrence";
    const meaning = countMeaning(compact, start, rawUnit, value);
    let scope = scopeNearNumber(compact, start, markers);
    if (scope === "unspecified" && meaning === "first_occurrence_count") scope = "lifetime";
    // “本笔 11 元，先把这一顿记下”里的“一顿”是指代当前对象，不是历史计数。
    if (scope === "record:current" && !match[1] && meaning === "occurrence_count") continue;
    claims.push({ value, meaning, unit, scope });
  }
  const amountPattern = /([+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?)(?:元|块钱|块)/g;
  for (const match of compact.matchAll(amountPattern)) {
    const start = match.index ?? 0;
    const value = numberValue(match[1]);
    if (value === null) continue;
    const claim = {
      value,
      meaning: amountMeaning(compact, start),
      unit: "currency" as const,
      scope: scopeNearNumber(compact, start, markers),
    };
    if (claimIsStatistical(claim)) claims.push(claim);
  }
  return claims;
}

function meaningFromNumberFact(fact: DomainSignalNumberFact): string {
  const meaning = fact.meaning?.toLocaleLowerCase() ?? "";
  if (/first.*occurrence/.test(meaning)) return "first_occurrence_count";
  if (/(?:sample).*count/.test(meaning)) return "sample_count";
  if (/(?:average|avg).*(?:occurrence|count|session)/.test(meaning)) return "average_occurrence_count";
  if (/(?:consecutive|streak).*(?:count|day)/.test(meaning)) return "consecutive_count";
  if (/(?:occurrence|transaction|session|meal).*count|(?:^|_)count$/.test(meaning)) return "occurrence_count";
  if (/(?:average|avg|mean).*amount/.test(meaning)) return "average_amount";
  if (/median.*amount/.test(meaning)) return "median_amount";
  if (/(?:p\d+|percentile).*amount/.test(meaning)) return "percentile_amount";
  if (/(?:delta|difference|change).*amount/.test(meaning)) return "delta_amount";
  if (/(?:total|sum|cumulative).*amount/.test(meaning)) return "total_amount";
  if (/current.*amount/.test(meaning)) return "current_amount";
  return fact.role === "count" ? "occurrence_count" : meaning;
}

function scopeFromNumberFact(fact: DomainSignalNumberFact): StatisticalScope | null {
  if (fact.scope) return fact.scope;
  const meaning = fact.meaning?.toLocaleLowerCase() ?? "";
  if (/previous_week|last_week/.test(meaning)) return "week:previous";
  if (/current_week|week_to_date/.test(meaning)) return "week:current";
  if (/previous_month|last_month/.test(meaning)) return "month:previous";
  if (/current_month|month_to_date/.test(meaning)) return "month:current";
  const rolling = meaning.match(/(?:rolling_?)?(\d+)d/);
  if (rolling) return `rolling:${Number(rolling[1])}d`;
  if (/current_record|current_expense|current_income/.test(meaning)) return "record:current";
  if (/first_occurrence/.test(meaning)) return "lifetime";
  if (/historical|history|prior_/.test(meaning)) return "history";
  return null;
}

function unitFromNumberFact(fact: DomainSignalNumberFact): StatisticalUnit | string {
  if (fact.unit) return fact.unit;
  const meaning = fact.meaning?.toLocaleLowerCase() ?? "";
  if (/amount|price|cost|balance/.test(meaning)) return "currency";
  if (/day/.test(meaning)) return "day";
  if (/week/.test(meaning) && fact.role === "count") return "week";
  if (/month/.test(meaning) && fact.role === "count") return "month";
  return fact.role === "count" ? "occurrence" : "unknown";
}

function sameNumber(left: number, right: number): boolean {
  return Math.abs(left - right) <= Number.EPSILON * Math.max(1, Math.abs(left), Math.abs(right));
}

function signalBoundClaims(signal: DomainSignal): BoundStatisticalClaim[] {
  const parsed = boundStatisticalClaims(signal.fact);
  const explicit = (signal.numberFacts ?? []).flatMap((fact): BoundStatisticalClaim[] => {
    if (!Number.isFinite(fact.value)) return [];
    const parsedMatch = parsed.find((claim) => sameNumber(claim.value, fact.value));
    const claim: BoundStatisticalClaim = {
      value: fact.value,
      meaning: meaningFromNumberFact(fact),
      unit: fact.unit ?? parsedMatch?.unit ?? unitFromNumberFact(fact),
      scope: fact.scope ?? scopeFromNumberFact(fact) ?? parsedMatch?.scope ?? "unspecified",
    };
    return claimIsStatistical(claim) ? [claim] : [];
  });
  const combined = [...explicit, ...parsed];
  return combined.filter((claim, index) => combined.findIndex((other) =>
    sameNumber(claim.value, other.value) && claim.meaning === other.meaning &&
    claim.unit === other.unit && claim.scope === other.scope
  ) === index);
}

function signalSupportsBoundClaims(text: string, signals: DomainSignal[]): boolean {
  const requested = boundStatisticalClaims(text);
  if (requested.length === 0) return true;
  return signals.some((signal) => {
    const available = signalBoundClaims(signal);
    return requested.every((claim) => available.some((candidateClaim) =>
      sameNumber(claim.value, candidateClaim.value) &&
      claim.meaning === candidateClaim.meaning &&
      claim.unit === candidateClaim.unit &&
      claim.scope === candidateClaim.scope
    ));
  });
}

function statisticalScopes(text: string): Set<StatisticalScope> {
  const compact = text.replace(/\s+/g, "");
  const scopes = new Set<StatisticalScope>();
  if (/(?:本|这)(?:自然)?周/.test(compact)) scopes.add("week:current");
  if (/上(?:自然)?周/.test(compact)) scopes.add("week:previous");
  if (/(?:本|这)个?月|本月/.test(compact)) scopes.add("month:current");
  if (/(?:上)个?月|上月/.test(compact)) scopes.add("month:previous");
  for (const match of compact.matchAll(/(?:近|过去)([一二两三四五六七八九十百\d]+)(天|周|月|晚)/g)) {
    const key = rollingWindowKey(match[1], match[2]);
    if (key) scopes.add(key);
  }
  if (/(?:第|连续|连着|已有|累计)[一二两三四五六七八九十百\d]+(?:次|笔|顿|天|晚|家|周|月)|[一二两三四五六七八九十百\d]+(?:次|笔|顿|天|晚|家|周|月|回)/.test(compact)) scopes.add("count");
  if (/(?:平均|均值)/.test(compact)) scopes.add("baseline:average");
  if (/(?:中位数?|中位)/.test(compact)) scopes.add("baseline:median");
  if (/(?:四分位|百分位|p\d{1,3})/i.test(compact)) scopes.add("baseline:percentile");
  if (/(?:历史最好|历史最高|历史最低|最好|最高|最低)/.test(compact)) scopes.add("baseline:extreme");
  if (/(?:比|较)(?:昨天|之前|过去|上次|上周|上月|平时|常态|平均|中位|历史)/.test(compact)) scopes.add("comparison:reference");
  if (/(?:高于|低于|涨了|降了|增加|减少|相差|多了|少了)/.test(compact)) scopes.add("comparison:direction");
  if (/(?:今天|今晚|今早).{0,12}(?:已有|累计|第[一二两三四五六七八九十百\d]+|连续)/.test(compact)) scopes.add("day:today");
  if (/(?:最近|近来).{0,12}(?:总是|一直|经常|频繁|反复|又)|(?:反复出现|高频|常点)/.test(compact)) scopes.add("frequency");
  return scopes;
}

function signalSupportsStatisticalClaim(text: string, signals: DomainSignal[]): boolean {
  const requested = statisticalScopes(text);
  if (requested.size === 0) return true;
  // 必须由同一个候选提供完整口径，避免把一个候选的周次数和另一个候选的
  // 月度比较拼成模型从未得到过的组合。显式数字还必须与这个候选里的
  // meaning + unit + scope 同时一致，不能再用全局数字集与全局 scope 集自由组合。
  return signals.some((signal) => {
    if (!signalSupportsBoundClaims(text, [signal])) return false;
    const available = statisticalScopes(signal.fact);
    return [...requested].every((scope) => {
      if (available.has(scope)) return true;
      // A qualitative comparison such as “比平时短些” is a valid rendering
      // of a verified baseline signal. It does not invent a new window or
      // number; the exact baseline remains in the selected candidate.
      if (scope === "comparison:reference") {
        return available.has("baseline:average")
          || available.has("baseline:median")
          || available.has("baseline:percentile");
      }
      return false;
    });
  });
}

// allowedSources:信号 fact 文本 + 本条记录字段 JSON。数字必须与代码事实一致；
// 不再把金额/均值自动取整，避免模型把 9.54 元改写成 10 元后仍被放行。
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
      if (!allowed.has(String(n))) {
        violations.push(`数字 ${n} 不在信号/记录允许集内: "${text.slice(0, 40)}"`);
        bad = true;
      }
    }
    // 2) "第X次/笔/顿/天/晚" 计数表达:数值必须来自计数信号显式声明
    for (const m of text.matchAll(/(?:第|连续|连着)\s*([一二两三四五六七八九十百千\d]{1,4})\s*(?:次|笔|顿|天|晚|家)/g)) {
      const n = parseChineseCardinal(m[1]);
      if (countAllowed.size === 0) {
        violations.push(`计数表达 "${m[0]}" 无计数信号支撑`);
        bad = true;
      } else if (n === null || !countAllowed.has(String(n))) {
        violations.push(`计数 "${m[0]}" 数值不可追溯到计数信号`);
        bad = true;
      }
    }
    // 3) 统计数字必须与同一候选中的 value + meaning + unit + scope 整体匹配。
    // 单纯出现在全局 allowed/countAllowed 中，不代表可以换一个周期或统计含义使用。
    if (!signalSupportsBoundClaims(text, signals)) {
      violations.push(`统计数字未绑定到同一候选的语义/单位/口径: "${text.slice(0, 40)}"`);
      bad = true;
    }
    if (bad) badIndexes.push(idx);
  });
  return { ok: violations.length === 0, violations, badIndexes };
}

export function validateModelTone(
  generatedTexts: Array<string | null | undefined>,
  recordFactsJson: string,
  signals: DomainSignal[] = [],
): NumberValidationResult {
  // 旧链路不传 signals 时仍保持严格模式；信号 Voice 层传入已核实信号后，允许忠实转述其数字和口径。
  const numericCheck = validateVoiceNumbers(generatedTexts, signals, recordFactsJson);
  const violations = [...numericCheck.violations];
  const badIndexes = new Set(numericCheck.badIndexes);

  generatedTexts.forEach((text, index) => {
    if (!text || !hasModelOwnedStatisticalClaim(text)) return;
    if (badIndexes.has(index)) return;
    if (signals.length > 0 && signalSupportsStatisticalClaim(text, signals)) return;
    violations.push(`模型试图改写代码统计口径: "${text.slice(0, 40)}"`);
    badIndexes.add(index);
  });

  return {
    ok: violations.length === 0,
    violations,
    badIndexes: [...badIndexes].sort((left, right) => left - right),
  };
}
