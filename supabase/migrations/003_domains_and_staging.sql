-- ════════════════════════════════════════════════════════════════════
-- 多数据域与中转站草案
-- 目的：为"非记账截图进入中转站，后续归档到新数据域"预留地基
-- 当前不会影响随手账 V1.0 入账链路
-- ════════════════════════════════════════════════════════════════════

create extension if not exists "uuid-ossp";

-- 数据域：一个可接收截图/图片抽取结果的业务域，如 expense、fitness、sleep
create table if not exists public.data_domains (
  id                    uuid primary key default uuid_generate_v4(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  key                   text not null,
  name                  text not null,
  description           text,
  icon                  text,
  status                text not null default 'active'
                        check (status in ('active','draft','archived')),
  routing_prompt        text,
  extraction_prompt     text,
  schema_json           jsonb not null default '{}'::jsonb,
  display_json          jsonb not null default '{}'::jsonb,
  is_system             boolean not null default false,
  user_id               uuid,
  unique (key, user_id)
);

create index if not exists idx_domains_status on public.data_domains (status);
create index if not exists idx_domains_user   on public.data_domains (user_id);

-- 中转站：AI 识别到"不是当前记账域"或"无法路由"时，先保留原图与文本化结果
create table if not exists public.staging_records (
  id                    uuid primary key default uuid_generate_v4(),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  status                text not null default 'unassigned'
                        check (status in ('unassigned','assigned','discarded','failed')),
  image_path            text,
  image_hash            text unique,
  source                text not null default 'ai_scan'
                        check (source in ('ai_scan','manual','import')),
  detected_domain_key   text,
  detected_domain_name  text,
  confidence            numeric(4,3),
  raw_text              text,
  ai_summary            text,
  extracted_json        jsonb not null default '{}'::jsonb,
  target_domain_id      uuid references public.data_domains(id) on delete set null,
  target_record_id      uuid,
  failure_reason        text,
  user_id               uuid
);

create index if not exists idx_staging_status  on public.staging_records (status);
create index if not exists idx_staging_domain  on public.staging_records (target_domain_id);
create index if not exists idx_staging_created on public.staging_records (created_at desc);

alter table public.data_domains    enable row level security;
alter table public.staging_records enable row level security;

drop policy if exists "allow_all_domains" on public.data_domains;
drop policy if exists "allow_all_staging" on public.staging_records;

-- 单用户阶段先全开；上线多用户前改为 user_id = auth.uid()
create policy "allow_all_domains" on public.data_domains
for all using (true) with check (true);

create policy "allow_all_staging" on public.staging_records
for all using (true) with check (true);

insert into public.data_domains (
  key, name, description, icon, status, is_system, schema_json, display_json
) values (
  'expense',
  '消费记账',
  '识别移动支付、账单详情和消费截图，写入 transactions 表。',
  '💰',
  'active',
  true,
  '{
    "target_table": "transactions",
    "required_fields": ["amount", "platform", "category", "payment_method"],
    "fields": {
      "amount": "number",
      "merchant_name": "string",
      "platform": "string",
      "category": "string",
      "payment_method": "string",
      "transaction_date": "date"
    }
  }'::jsonb,
  '{
    "primary_field": "amount",
    "secondary_field": "merchant_name",
    "list_view": "transaction_list"
  }'::jsonb
) on conflict (key, user_id) do nothing;
