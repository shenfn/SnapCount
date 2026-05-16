-- ════════════════════════════════════════════════════════════════════
-- 015 sleep 时长字段单位统一为「分钟」
-- ────────────────────────────────────────────────────────────────────
-- 背景：sleep_hours 浮点小时存储不直观，与 sport/reading 的分钟单位不一致。
-- 改造后所有时长字段统一为分钟整数：
--   - 录入时双输入框（小时+分钟），存储自动合并
--   - 展示时 formatDuration 转回 "6 小时 30 分钟" 自然格式
--   - 大小比较和聚合都更精确（避免 6.67 浮点尾差）
--
-- 范围：
--   1. data_records 表里 domain_key='sleep' 的所有 payload_jsonb
--      sleep_hours (numeric) → sleep_minutes (integer)
--      值 = round(sleep_hours * 60)
--   2. data_domains 表里 sleep 域的 schema_json/display_json
--      facts: sleep_hours → sleep_minutes
--      display.primary_fact: sleep_hours → sleep_minutes
--      display.summary_fields: sleep_hours → sleep_minutes
--
-- 安全性：
--   - 单事务原子提交，失败回滚
--   - 已通过 SELECT 预演确认所有 sleep_hours 取值合理（修复 5/13 后最大 8.12h）
--   - 旧字段 sleep_hours 完全移除（不保留双写，因为 schema 是单一事实源）
-- ════════════════════════════════════════════════════════════════════

begin;

-- ──────────────────────────────────────────────────────────────────
-- 1. data_records: sleep_hours → sleep_minutes
-- ──────────────────────────────────────────────────────────────────
update public.data_records
set payload_jsonb = (payload_jsonb - 'sleep_hours')
                    || jsonb_build_object(
                         'sleep_minutes',
                         round(((payload_jsonb->>'sleep_hours')::numeric) * 60)::int
                       )
where domain_key = 'sleep'
  and payload_jsonb ? 'sleep_hours';

-- ──────────────────────────────────────────────────────────────────
-- 2. data_domains: sleep 的 schema_json 和 display_json
-- ──────────────────────────────────────────────────────────────────
update public.data_domains
set
  schema_json = jsonb_set(
    schema_json,
    '{facts}',
    '[
      {"key": "sleep_minutes", "label": "睡眠时长", "type": "number", "unit": "分钟", "input": "duration"},
      {"key": "quality_score", "label": "睡眠评分", "type": "number", "unit": "分"}
    ]'::jsonb
  ),
  display_json = jsonb_set(
    jsonb_set(
      display_json,
      '{primary_fact}',
      '"sleep_minutes"'::jsonb
    ),
    '{summary_fields}',
    '["sleep_minutes", "quality_score"]'::jsonb
  ),
  updated_at = now()
where key = 'sleep';

-- ──────────────────────────────────────────────────────────────────
-- 3. 验证：迁移后没有遗留 sleep_hours
-- ──────────────────────────────────────────────────────────────────
do $$
declare
  remaining_records int;
  remaining_schema  int;
begin
  select count(*) into remaining_records
  from public.data_records
  where domain_key = 'sleep' and payload_jsonb ? 'sleep_hours';

  select count(*) into remaining_schema
  from public.data_domains
  where key = 'sleep' and schema_json::text like '%sleep_hours%';

  if remaining_records > 0 or remaining_schema > 0 then
    raise exception '015 migration 不完整: records=%, schema=%', remaining_records, remaining_schema;
  end if;
end $$;

commit;

-- ════════════════════════════════════════════════════════════════════
-- 迁移效果对照
-- ────────────────────────────────────────────────────────────────────
-- 5/13 午睡  sleep_hours=0.33   → sleep_minutes=20
-- 5/10 夜睡  sleep_hours=7.65   → sleep_minutes=459
-- 5/14 夜睡  sleep_hours=6.67   → sleep_minutes=400
-- 等等...
-- ════════════════════════════════════════════════════════════════════
