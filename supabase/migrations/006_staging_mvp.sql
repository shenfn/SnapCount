-- ════════════════════════════════════════════════════════════════════
-- 阶段 1A：中转站 MVP 补强
-- 目的：让非记账/识别失败截图进入 staging_records，并让日志可关联中转站
-- ════════════════════════════════════════════════════════════════════

alter table public.data_domains
  add column if not exists routing_json jsonb not null default '{}'::jsonb,
  add column if not exists extraction_json jsonb not null default '{}'::jsonb,
  add column if not exists version text not null default '1.0',
  add column if not exists privacy_level text not null default 'private';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'data_domains_privacy_level_check'
      and conrelid = 'public.data_domains'::regclass
  ) then
    alter table public.data_domains
      add constraint data_domains_privacy_level_check
      check (privacy_level in ('private','shared','public_template'));
  end if;
end $$;

alter table public.staging_records
  add column if not exists perceptual_hash text,
  add column if not exists image_type text,
  add column if not exists record_type text,
  add column if not exists occurred_at timestamptz,
  add column if not exists order_finished_at timestamptz,
  add column if not exists routing_candidates jsonb not null default '[]'::jsonb,
  add column if not exists quality_report jsonb not null default '{}'::jsonb,
  add column if not exists retry_count integer not null default 0,
  add column if not exists last_error_type text,
  add column if not exists last_error_message text,
  add column if not exists resolved_at timestamptz,
  add column if not exists resolved_action text,
  add column if not exists discard_reason text;

alter table public.staging_records
  drop constraint if exists staging_records_status_check;

alter table public.staging_records
  add constraint staging_records_status_check
  check (status in (
    'unassigned',
    'assigned',
    'discarded',
    'failed',
    'unrouted',
    'routed',
    'routing_failed',
    'extracted',
    'pending_review',
    'confirmed',
    'archived',
    'extraction_failed',
    'schema_failed',
    'ai_error'
  ));

alter table public.ai_recognition_logs
  add column if not exists domain_id uuid references public.data_domains(id) on delete set null,
  add column if not exists staging_record_id uuid references public.staging_records(id) on delete set null,
  add column if not exists data_record_id uuid,
  add column if not exists model_provider text,
  add column if not exists model_name text,
  add column if not exists prompt_version text,
  add column if not exists token_usage jsonb,
  add column if not exists cost_estimate numeric(10,6);

create index if not exists idx_staging_retry on public.staging_records (retry_count);
create index if not exists idx_staging_record_type on public.staging_records (record_type);
create index if not exists idx_staging_phash on public.staging_records (perceptual_hash);
create index if not exists idx_ai_logs_staging on public.ai_recognition_logs (staging_record_id);
create index if not exists idx_ai_logs_domain on public.ai_recognition_logs (domain_id);

insert into public.data_domains (
  key, name, description, icon, status, is_system, schema_json, display_json, routing_json, extraction_json, version, privacy_level
) values (
  'income',
  '收入记录',
  '识别收款、转账到账、退款和报销截图，写入 income_records 表。',
  '💰',
  'active',
  true,
  '{
    "target_table": "income_records",
    "required_fields": ["amount", "source_name", "income_date"],
    "fields": {
      "amount": "number",
      "source_name": "string",
      "income_category": "string",
      "income_date": "date"
    }
  }'::jsonb,
  '{
    "primary_field": "amount",
    "secondary_field": "source_name",
    "list_view": "income_list"
  }'::jsonb,
  '{
    "default_record_type": "income",
    "confidence_threshold": 0.7
  }'::jsonb,
  '{}'::jsonb,
  '1.0',
  'private'
) on conflict (key, user_id) do nothing;
