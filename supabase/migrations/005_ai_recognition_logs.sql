-- ════════════════════════════════════════════════════════════════════
-- AI 识别日志
-- 目的：记录每次截图识别的模型返回、入库结果和错误信息，方便排查
-- ════════════════════════════════════════════════════════════════════

create extension if not exists "uuid-ossp";

create table if not exists public.ai_recognition_logs (
  id              uuid primary key default uuid_generate_v4(),
  created_at      timestamptz not null default now(),
  image_hash      text,
  perceptual_hash text,
  perceptual_distance integer,
  image_url       text,
  image_type      text,
  record_type     text,
  occurred_at     timestamptz,
  order_finished_at timestamptz,
  duplicate_kind  text,
  duplicate_ref_table text,
  duplicate_ref_id uuid,
  target_table    text,
  target_id       uuid,
  status          text not null default 'started'
                  check (status in ('started','success','pending','duplicate','ai_error','db_error','error')),
  confidence      numeric(4,3),
  duration_ms     integer,
  ai_response     jsonb,
  raw_response    text,
  error_message   text,
  user_id         uuid
);

create index if not exists idx_ai_logs_created on public.ai_recognition_logs (created_at desc);
create index if not exists idx_ai_logs_hash on public.ai_recognition_logs (image_hash);
create index if not exists idx_ai_logs_phash on public.ai_recognition_logs (perceptual_hash);
create index if not exists idx_ai_logs_occurred on public.ai_recognition_logs (occurred_at desc);
create index if not exists idx_ai_logs_status on public.ai_recognition_logs (status);
create index if not exists idx_ai_logs_record_type on public.ai_recognition_logs (record_type);

alter table public.ai_recognition_logs enable row level security;

drop policy if exists "allow_all_ai_logs" on public.ai_recognition_logs;

-- 单用户阶段先全开；上线多用户前改为 user_id = auth.uid()
create policy "allow_all_ai_logs" on public.ai_recognition_logs
for all using (true) with check (true);
