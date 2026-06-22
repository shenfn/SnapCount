-- 062_ai_feedback_column.sql
-- 给 transactions / income_records 增加 ai_feedback (jsonb) 列，
-- 用于持久化 AI 即时反馈（badge / band / emotion_line / utility_line / detail_reason / timing_signal 等）。
-- data_records 的 ai_feedback 仍写到 payload_jsonb 内（已通过 ingest-receipt 完成），本次不动。

alter table if exists public.transactions
  add column if not exists ai_feedback jsonb;

alter table if exists public.income_records
  add column if not exists ai_feedback jsonb;

comment on column public.transactions.ai_feedback is
  'AI 即时反馈结构化对象：badge / band / emotion_line / utility_line / detail_reason / timing_signal 等。可空。';
comment on column public.income_records.ai_feedback is
  'AI 即时反馈结构化对象，结构同 transactions.ai_feedback。可空。';
