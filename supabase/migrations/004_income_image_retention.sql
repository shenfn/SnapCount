-- ════════════════════════════════════════════════════════════════════
-- 收入截图留存字段
-- 目的：让收入记录也能像支出一样保留 Storage path / hash / 来源
-- ════════════════════════════════════════════════════════════════════

alter table public.income_records
  add column if not exists image_url text,
  add column if not exists image_hash text,
  add column if not exists source text not null default 'manual'
    check (source in ('ai_scan','manual','import'));

create unique index if not exists idx_inc_image_hash_unique
  on public.income_records (image_hash)
  where image_hash is not null;

create index if not exists idx_inc_source on public.income_records (source);
