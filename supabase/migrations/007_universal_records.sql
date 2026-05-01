-- ════════════════════════════════════════════════════════════════════
-- 阶段 1B：通用记录与路由反馈
-- 目的：为运动、睡眠、阅读等非记账域提供正式承载层
-- ════════════════════════════════════════════════════════════════════

create extension if not exists "uuid-ossp";

create table if not exists public.data_records (
  id                  uuid primary key default uuid_generate_v4(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  domain_id           uuid not null references public.data_domains(id) on delete cascade,
  domain_key          text not null,
  domain_version      text not null default '1.0',
  occurred_at         timestamptz,
  title               text,
  summary             text,
  payload_jsonb       jsonb not null default '{}'::jsonb,
  source              text not null default 'staging'
                      check (source in ('staging','manual','import','ai_scan')),
  source_image_path   text,
  source_image_hash   text,
  staging_record_id   uuid references public.staging_records(id) on delete set null,
  user_id             uuid
);

create index if not exists idx_data_records_domain on public.data_records (domain_id);
create index if not exists idx_data_records_domain_key on public.data_records (domain_key);
create index if not exists idx_data_records_occurred on public.data_records (occurred_at desc);
create index if not exists idx_data_records_payload_gin on public.data_records using gin (payload_jsonb);

create table if not exists public.user_routing_feedback (
  id                    uuid primary key default uuid_generate_v4(),
  created_at            timestamptz not null default now(),
  staging_record_id     uuid references public.staging_records(id) on delete set null,
  image_hash            text,
  original_domain_key   text,
  corrected_domain_key  text not null,
  action                text not null default 'archive'
                        check (action in ('archive','correct','discard','retry')),
  confidence            numeric(4,3),
  payload_jsonb         jsonb not null default '{}'::jsonb,
  user_id               uuid
);

create index if not exists idx_routing_feedback_corrected on public.user_routing_feedback (corrected_domain_key);
create index if not exists idx_routing_feedback_staging on public.user_routing_feedback (staging_record_id);

alter table public.data_records enable row level security;
alter table public.user_routing_feedback enable row level security;

drop policy if exists "allow_all_data_records" on public.data_records;
drop policy if exists "allow_all_routing_feedback" on public.user_routing_feedback;

-- 单用户阶段先全开；上线多用户前改为 user_id = auth.uid()
create policy "allow_all_data_records" on public.data_records
for all using (true) with check (true);

create policy "allow_all_routing_feedback" on public.user_routing_feedback
for all using (true) with check (true);

alter table public.ai_recognition_logs
  drop constraint if exists ai_recognition_logs_data_record_id_fkey;

alter table public.ai_recognition_logs
  add constraint ai_recognition_logs_data_record_id_fkey
  foreign key (data_record_id) references public.data_records(id) on delete set null;

insert into public.data_domains (
  key, name, description, icon, status, is_system,
  schema_json, display_json, routing_json, extraction_json, version, privacy_level
) values
(
  'sport',
  '运动记录',
  '承接运动截图、步数、距离、消耗和训练记录。',
  '🏃',
  'active',
  true,
  '{
    "time_field": "occurred_at",
    "facts": [
      {"key": "duration_minutes", "label": "运动时长", "type": "number", "unit": "分钟"},
      {"key": "distance_km", "label": "距离", "type": "number", "unit": "公里"},
      {"key": "calories", "label": "消耗", "type": "number", "unit": "千卡"}
    ],
    "dimensions": [
      {"key": "sport_type", "label": "运动类型"},
      {"key": "source_app", "label": "来源"}
    ]
  }'::jsonb,
  '{
    "primary_fact": "duration_minutes",
    "primary_dimension": "sport_type",
    "title_field": "sport_type",
    "summary_fields": ["duration_minutes", "distance_km", "calories"]
  }'::jsonb,
  '{"keywords": ["运动", "步数", "跑步", "Keep", "华为健康"], "confidence_threshold": 0.75}'::jsonb,
  '{}'::jsonb,
  '1.0',
  'private'
),
(
  'sleep',
  '睡眠记录',
  '承接睡眠追踪截图、睡眠时长、入睡时间和睡眠质量。',
  '🌙',
  'active',
  true,
  '{
    "time_field": "occurred_at",
    "facts": [
      {"key": "sleep_hours", "label": "睡眠时长", "type": "number", "unit": "小时"},
      {"key": "quality_score", "label": "睡眠评分", "type": "number", "unit": "分"}
    ],
    "dimensions": [
      {"key": "quality_level", "label": "质量等级"},
      {"key": "source_app", "label": "来源"}
    ]
  }'::jsonb,
  '{
    "primary_fact": "sleep_hours",
    "primary_dimension": "quality_level",
    "title_field": "quality_level",
    "summary_fields": ["sleep_hours", "quality_score"]
  }'::jsonb,
  '{"keywords": ["睡眠", "入睡", "醒来", "睡眠评分"], "confidence_threshold": 0.75}'::jsonb,
  '{}'::jsonb,
  '1.0',
  'private'
),
(
  'reading',
  '阅读记录',
  '承接阅读时长、书籍进度、页数和阅读平台截图。',
  '📚',
  'active',
  true,
  '{
    "time_field": "occurred_at",
    "facts": [
      {"key": "reading_minutes", "label": "阅读时长", "type": "number", "unit": "分钟"},
      {"key": "pages", "label": "页数", "type": "number", "unit": "页"}
    ],
    "dimensions": [
      {"key": "book_name", "label": "书名"},
      {"key": "source_app", "label": "来源"}
    ]
  }'::jsonb,
  '{
    "primary_fact": "reading_minutes",
    "primary_dimension": "book_name",
    "title_field": "book_name",
    "summary_fields": ["reading_minutes", "pages"]
  }'::jsonb,
  '{"keywords": ["阅读", "读书", "微信读书", "书籍", "页"], "confidence_threshold": 0.75}'::jsonb,
  '{}'::jsonb,
  '1.0',
  'private'
)
on conflict (key, user_id) do update set
  name = excluded.name,
  description = excluded.description,
  icon = excluded.icon,
  status = excluded.status,
  is_system = excluded.is_system,
  schema_json = excluded.schema_json,
  display_json = excluded.display_json,
  routing_json = excluded.routing_json,
  extraction_json = excluded.extraction_json,
  version = excluded.version,
  privacy_level = excluded.privacy_level;
