-- ════════════════════════════════════════════════════════════════════
-- 016_daily_domain_summary.sql
-- 跨域日聚合视图：PageInsights 的统一数据源
-- ────────────────────────────────────────────────────────────────────
-- 设计说明：
-- 1. 用普通 VIEW 而非 MATERIALIZED VIEW —— 当前数据量小（< 200 行/月），
--    每次查询聚合开销可忽略；不存在"何时刷新"工程问题。
--    等单日记录上千、查询变慢时，再 ALTER 为 MATERIALIZED VIEW + REFRESH。
-- 2. 时区按 'Asia/Shanghai' 切分日期，与前端口径一致。
-- 3. 字段命名与「多域联动分析.html」原型的 DAILY 数组一致，前端可直接消费。
-- 4. 时长字段统一为分钟（已在 015 完成 sleep 单位迁移；保留 sleep_hours 双兼容）。
-- 5. food_calories 取 total_calorie_kcal；如未来 food schema 调整，只改这一处。
-- ════════════════════════════════════════════════════════════════════

DROP VIEW IF EXISTS public.daily_domain_summary CASCADE;

CREATE VIEW public.daily_domain_summary AS
WITH expense_agg AS (
  SELECT
    transaction_date AS d,
    user_id,
    SUM(amount)::numeric AS expense_total,
    COUNT(*) AS expense_count
  FROM public.transactions
  WHERE status = 'done' AND type = 'expense'
  GROUP BY transaction_date, user_id
),
income_agg AS (
  SELECT
    income_date AS d,
    user_id,
    SUM(amount)::numeric AS income_total,
    COUNT(*) AS income_count
  FROM public.income_records
  GROUP BY income_date, user_id
),
domain_agg AS (
  SELECT
    (occurred_at AT TIME ZONE 'Asia/Shanghai')::date AS d,
    user_id,
    -- sleep：分钟为主，兼容历史 sleep_hours
    SUM(CASE WHEN domain_key = 'sleep' THEN
      COALESCE(
        NULLIF(payload_jsonb->>'sleep_minutes', '')::numeric,
        NULLIF(payload_jsonb->>'sleep_hours', '')::numeric * 60,
        0
      )
    END) AS sleep_minutes,
    AVG(CASE WHEN domain_key = 'sleep' AND payload_jsonb->>'quality_score' IS NOT NULL
      THEN NULLIF(payload_jsonb->>'quality_score', '')::numeric
    END) AS sleep_score_avg,
    COUNT(*) FILTER (WHERE domain_key = 'sleep') AS sleep_count,
    -- sport
    SUM(CASE WHEN domain_key = 'sport' THEN
      COALESCE(NULLIF(payload_jsonb->>'duration_minutes', '')::numeric, 0)
    END) AS sport_minutes,
    COUNT(*) FILTER (WHERE domain_key = 'sport') AS sport_count,
    -- reading
    SUM(CASE WHEN domain_key = 'reading' THEN
      COALESCE(NULLIF(payload_jsonb->>'reading_minutes', '')::numeric, 0)
    END) AS reading_minutes,
    COUNT(*) FILTER (WHERE domain_key = 'reading') AS reading_count,
    -- food
    SUM(CASE WHEN domain_key = 'food' THEN
      COALESCE(NULLIF(payload_jsonb->>'total_calorie_kcal', '')::numeric, 0)
    END) AS food_calories,
    COUNT(*) FILTER (WHERE domain_key = 'food') AS food_meals
  FROM public.data_records
  WHERE occurred_at IS NOT NULL
  GROUP BY 1, 2
),
-- 三路 union 出所有"至少有一类记录的日期+用户"组合
all_keys AS (
  SELECT d, user_id FROM expense_agg
  UNION
  SELECT d, user_id FROM income_agg
  UNION
  SELECT d, user_id FROM domain_agg
)
SELECT
  k.d AS date,
  k.user_id,
  -- 财务
  COALESCE(e.expense_total, 0) AS expense_total,
  COALESCE(e.expense_count, 0) AS expense_count,
  COALESCE(i.income_total, 0) AS income_total,
  COALESCE(i.income_count, 0) AS income_count,
  -- 睡眠
  COALESCE(da.sleep_minutes, 0)::numeric AS sleep_minutes,
  da.sleep_score_avg,
  COALESCE(da.sleep_count, 0) AS sleep_count,
  -- 运动
  COALESCE(da.sport_minutes, 0)::numeric AS sport_minutes,
  COALESCE(da.sport_count, 0) AS sport_count,
  -- 阅读
  COALESCE(da.reading_minutes, 0)::numeric AS reading_minutes,
  COALESCE(da.reading_count, 0) AS reading_count,
  -- 饮食
  COALESCE(da.food_calories, 0)::numeric AS food_calories,
  COALESCE(da.food_meals, 0) AS food_meals,
  -- 当日是否至少有一个域有数据（前端展示空状态用）
  CASE WHEN
    COALESCE(e.expense_count, 0) +
    COALESCE(i.income_count, 0) +
    COALESCE(da.sleep_count, 0) +
    COALESCE(da.sport_count, 0) +
    COALESCE(da.reading_count, 0) +
    COALESCE(da.food_meals, 0) > 0
  THEN true ELSE false END AS has_any_data
FROM all_keys k
LEFT JOIN expense_agg e ON e.d = k.d AND e.user_id IS NOT DISTINCT FROM k.user_id
LEFT JOIN income_agg i ON i.d = k.d AND i.user_id IS NOT DISTINCT FROM k.user_id
LEFT JOIN domain_agg da ON da.d = k.d AND da.user_id IS NOT DISTINCT FROM k.user_id
ORDER BY k.d DESC;

COMMENT ON VIEW public.daily_domain_summary IS
  '跨域日聚合视图。每行=某用户某一天的多域指标。供 PageInsights/AI 分析消费。当前单用户阶段 user_id 可能为 NULL。';

-- 给 anon/authenticated 授权（沿用 data_records 风格）
GRANT SELECT ON public.daily_domain_summary TO anon, authenticated;
