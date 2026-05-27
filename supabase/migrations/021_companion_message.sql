-- 给截图识别相关 3 张表加 companion_message 列，统一存放 AI 生成的陪伴文案
-- data_records 已通过 payload_jsonb.companion_message 落地，本迁移不动它

alter table if exists public.transactions
  add column if not exists companion_message text;

alter table if exists public.income_records
  add column if not exists companion_message text;

alter table if exists public.staging_records
  add column if not exists companion_message text;

comment on column public.transactions.companion_message is 'AI 截图识别后生成的陪伴文案（不超过 30 汉字）';
comment on column public.income_records.companion_message is 'AI 截图识别后生成的陪伴文案（不超过 30 汉字）';
comment on column public.staging_records.companion_message is 'AI 截图识别后生成的陪伴文案（不超过 30 汉字）';
