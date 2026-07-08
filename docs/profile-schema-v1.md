# user_domain_profiles 画像 Schema v1(六域)

> 架构定位:画像是**投影**,不是数据源。真相永远在 `transactions` / `data_records` / `income_records`,
> 画像可随时用 `rebuild_<domain>_profile()` 从源表全量重算。
>
> 铁律:**每个 key 必须有 ≥1 条消费它的信号规则,否则不进 schema。** 结构为信号服务,信号为文案服务。

## 0. 表结构与公共约定

```sql
create table user_domain_profiles (
  user_id         uuid  not null,
  domain_key      text  not null,   -- expense/sleep/sport/food/reading/wallet
  profile_version int   not null,   -- 回填任务据此找"落后版本"的行
  profile         jsonb not null,   -- 内含 "v" 镜像版本号,方便 trace 归因
  source_count    int   not null,   -- 参与计算的源记录数(信号规则判断基线是否可信)
  computed_at     timestamptz,
  primary key (user_id, domain_key)
)
```

公共约定:

| 约定 | 内容 | 理由 |
|---|---|---|
| 时区 | 一切日期口径 `Asia/Shanghai` | 与用户"这周/今天"语感一致 |
| "这周" | **周一起算的自然周**(`date_trunc('week')`) | 文案说"这周第3次"必须与用户日历认知一致,不用滚动7天 |
| "近30天" | 滚动窗口 `today - 29 .. today` | 频率/基线类统计用滚动,避免月初清零 |
| 更新 | 归档成功后 fire-and-forget 调 `refresh_domain_profile()`;**夜间 cron 对 60 天内活跃用户全量 rebuild** | 增量保新鲜,夜间重算滚动窗口老化 + 纠漂移 |
| 一致性 | 增量与回填**共用同一个 rebuild 函数**(增量=单用户单域重算,数据量小到毫秒级,不做真·增量计数) | 消灭"增量与回填两套逻辑漂移"这个经典坑 |
| 读取 | EF 单行 `select profile`,零计算 | 速度 |
| 校验 | EF 侧每域一个 zod schema,parse 失败按"无画像"降级 | 烂数据进不了信号层 |

> 决策说明:放弃"真·增量计数器(+1)"方案。单用户单域 90 天数据 <500 行,整段重算 <10ms,
> 换来增量/回填永远同一套逻辑。这是速度和正确性的免费午餐。

---

## 1. expense(消费)

```jsonc
{
  "v": 1,
  // 商户维度:准入 = 近30天≥2次 或 近14天有消费;按 last_visit 排序取前 40
  "merchant_stats": {
    "QLHazyCoder 数字中心": {
      "week_count": 2,          // 本自然周(不含当前正在识别的这笔,信号层 +1)
      "month_count": 17,        // 滚动30天
      "count_90d": 21,
      "last_visit": "2026-07-06",
      "avg_amount": 10.4
    }
  },
  // 分类维度:category 归一化('餐饮'→'food',线上已发现脏值)
  "category_stats": {
    "food": { "week_count": 9, "month_count": 41, "week_total": 152.3,
              "median_amount": 14.7, "p90_amount": 32.9 }
  },
  // 周节奏:本周 vs 上周同期(截至同星期几),支撑"这周明显收着花/放开花"
  "week_velocity": {
    "cur_count": 12, "cur_total": 534.3,
    "prev_count_same_span": 15, "prev_total_same_span": 402.1
  },
  // 当天快照(夜间 cron 归零重算)
  "today": { "count": 3, "total": 717.0, "late_night_count": 0 }
}
```

**消费信号**:`merchant_repeat`(week_count+1≥3 才说)· `unusual_amount`(> 该分类 p90)· `week_velocity`(±40% 才说)· `late_night_spend`(today.late_night_count≥2)

**结构性消灭的病**:"这周第十次"——week_count 是自然周真数,模型只收信号里算好的 n。

---

## 2. sleep(睡眠)

```jsonc
{
  "v": 1,
  // 个人基线:近30天,按"夜"去重(线上发现 6/25、6/26 各有重复行,取同夜最新一条)
  "baseline": {
    "n": 15,                    // n≥7 基线才可信,信号层强制检查
    "median_hours": 6.6, "p25": 6.3, "p75": 7.9,
    "mean_score": 81, "window_days": 30
  },
  // 作息型:入睡时刻跨午夜,平均前先 +12h 平移再取模还原
  "chronotype": {
    "typical_sleep_start": "00:40", "typical_wake": "07:30",
    "type": "night_owl",        // night_owl(中位入睡≥00:00) / early_bird(≤22:30) / regular
    "n": 12
  },
  "recent_nights": [            // 近3夜,支撑"连着两晚都短了"
    { "night": "2026-07-07", "hours": 6.45, "score": 79 },
    { "night": "2026-07-06", "hours": 6.28, "score": 78 },
    { "night": "2026-07-04", "hours": 8.13, "score": 86 }
  ],
  "coverage": { "nights_last7": 5 }
}
```

**消费信号**:`vs_baseline`(n≥7:|Δmedian|<0.75h→normal,<p25→below,>p75→above;n<7 退回 7h 世界标准)· `consecutive_short`(近2夜均 <p25)· `score_trend`

**结构性消灭的病**:"醒来应该挺重的"人机感——6.45h 对 median 6.6h 的用户判定为 **normal**,文案说"和你平时差不多",这就是"AI 记得我"的体感来源。

---

## 3. sport(运动)

```jsonc
{
  "v": 1,
  "weekly_rhythm": { "sessions_per_week_4w": 2.5, "minutes_per_week_4w": 130 },
  "type_stats": {
    "户外骑行": { "count_90d": 8, "last_date": "2026-07-01",
                  "median_duration_min": 45, "median_distance_km": 12.3,
                  "best_pace": "4'50\"", "median_pace": "5'20\"" }
  },
  "current_week": { "sessions": 1, "minutes": 40 },
  "gap_days": 3                 // 距上次运动天数,支撑"歇了X天又动起来了"
}
```

**消费信号**:`pace_vs_self`(同类型 vs 自己中位配速,替代"比上次快一点"的模糊话)· `rhythm_return`(gap_days≥7 后再运动)· `weekly_progress`(current_week vs rhythm)

---

## 4. food(饮食)

```jsonc
{
  "v": 1,
  "meal_baseline": {            // 分餐次热量基线,滚动30天
    "lunch":  { "n": 14, "median_kcal": 620 },
    "dinner": { "n": 11, "median_kcal": 750 },
    "snack":  { "n": 6,  "median_kcal": 280 }
  },
  "daily_kcal_7d": { "avg": 1850, "days_recorded": 5 },
  "late_snack_14d": 3,          // 21点后加餐次数
  "recurring_dishes": ["麻辣烫", "鸡腿饭"]   // 近30天出现≥3次的菜品,top5
}
```

**消费信号**:`meal_vs_baseline`(本餐 vs 同餐次自己的中位)· `late_snack_streak` · `dish_ritual`(recurring 命中当前菜品)

---

## 5. reading(阅读)

```jsonc
{
  "v": 1,
  "current_book": {
    "name": "xxx", "last_progress_percent": 14,
    "last_read_date": "2026-07-05", "sessions_30d": 6,
    "progress_delta_7d": 9      // 一周推进了多少个百分点
  },
  "minutes_baseline": { "median_daily_30d": 42, "days_read_30d": 12 },
  "streak": { "current_days": 3, "best_30d": 6 }
}
```

**消费信号**:`progress_momentum`(delta 明显快/慢于自己节奏)· `streak` · `book_switch`(书名 ≠ current_book)

---

## 6. wallet(钱包/负债)

```jsonc
{
  "v": 1,
  "liabilities": {
    "花呗": { "latest_amount": 812.33, "prev_amount": 640.10, "delta": 172.23,
              "payment_due_day": 10, "last_snapshot": "2026-07-05" }
  },
  "cash": {
    "微信余额": { "latest": 320.50, "prev": 410.00, "last_snapshot": "2026-07-03" }
  },
  "due_soon": [ { "account": "花呗", "due_date": "2026-07-10", "amount": 812.33 } ]
}
```

**消费信号**:`liability_delta`(环比涨/降,只说方向和幅度)· `due_reminder`(due_soon ≤3天,timing 类信号)· `cash_runway`(现金 vs 本周消费速度,v2 再说)

---

## 7. 演进钩子(三件套)

1. **版本号双写**:列 `profile_version` 为权威,jsonb 内 `v` 镜像进 trace_snapshot,点评数据可按版本归因文案质量;
2. **rebuild 函数即真相**:每域 `rebuild_<domain>_profile(p_user_id) returns jsonb`,增量/夜间/回填三条路径共用;改结构 = 改函数 + bump 版本 + 夜间任务自动把落后行冲掉;
3. **zod 前置校验**(EF 侧,阶段②实现):

```ts
const ExpenseProfileV1 = z.object({
  v: z.literal(1),
  merchant_stats: z.record(z.object({
    week_count: z.number().int(), month_count: z.number().int(),
    count_90d: z.number().int(), last_visit: z.string(), avg_amount: z.number(),
  })),
  category_stats: z.record(z.object({
    week_count: z.number().int(), month_count: z.number().int(),
    week_total: z.number(), median_amount: z.number(), p90_amount: z.number(),
  })),
  week_velocity: z.object({ cur_count: z.number(), cur_total: z.number(),
    prev_count_same_span: z.number(), prev_total_same_span: z.number() }),
  today: z.object({ count: z.number(), total: z.number(), late_night_count: z.number() }),
}).strict();
// parse 失败 → 视为无画像 → 信号层沉默 → 文案只围绕当前记录
```

## 8. 一期范围

- migration 066:建表 + `rebuild_expense_profile` + `rebuild_sleep_profile` + `refresh_domain_profile` 分发器(见 `supabase/migrations/066_user_domain_profiles.sql`)
- sport/food/reading/wallet 的 rebuild 函数结构同理,阶段①验证 expense/sleep 后按同模板补(067)
- 夜间 cron:pg_cron 每日 03:30 Asia/Shanghai 对 60 天活跃用户逐域 refresh
