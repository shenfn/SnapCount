create table if not exists public.user_finance_vocabulary (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('platform', 'category', 'payment')),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  normalized_name text not null check (char_length(btrim(normalized_name)) between 1 and 80),
  primary_category text check (
    primary_category is null
    or primary_category in ('餐饮', '购物', '出行', '娱乐', '生活', '健康', '教育', '其他')
  ),
  linked_account_id uuid references public.accounts(id) on delete set null,
  source text not null default 'user_confirmed'
    check (source in ('system', 'user_confirmed', 'ai_confirmed', 'import')),
  status text not null default 'active'
    check (status in ('active', 'hidden', 'merged')),
  usage_count integer not null default 1 check (usage_count >= 0),
  last_used_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, kind, normalized_name)
);

create index if not exists idx_user_finance_vocabulary_rank
  on public.user_finance_vocabulary (user_id, kind, status, usage_count desc, last_used_at desc);

alter table public.user_finance_vocabulary enable row level security;

drop policy if exists user_finance_vocabulary_select_own on public.user_finance_vocabulary;
create policy user_finance_vocabulary_select_own
  on public.user_finance_vocabulary
  for select
  to authenticated
  using (user_id = auth.uid());

revoke all on table public.user_finance_vocabulary from public, anon, authenticated, service_role;
grant select on table public.user_finance_vocabulary to authenticated, service_role;

create or replace function public.record_user_finance_vocabulary(
  p_kind text,
  p_display_name text,
  p_primary_category text default null,
  p_linked_account_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_display_name text := btrim(coalesce(p_display_name, ''));
  v_normalized_name text;
  v_primary_category text := nullif(btrim(coalesce(p_primary_category, '')), '');
  v_row public.user_finance_vocabulary%rowtype;
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;

  if p_kind is null or p_kind not in ('platform', 'category', 'payment') then
    raise exception 'unsupported finance vocabulary kind';
  end if;

  if char_length(v_display_name) < 1 or char_length(v_display_name) > 80 then
    raise exception 'finance vocabulary display name must contain 1 to 80 characters';
  end if;

  if v_primary_category is not null
    and v_primary_category not in ('餐饮', '购物', '出行', '娱乐', '生活', '健康', '教育', '其他') then
    raise exception 'unsupported primary category';
  end if;

  if p_kind = 'category' then
    if v_display_name not in ('餐饮', '购物', '出行', '娱乐', '生活', '健康', '教育', '其他') then
      raise exception 'expense categories must use the stable primary taxonomy';
    end if;
    v_primary_category := v_display_name;
  elsif v_primary_category is not null then
    raise exception 'primary category is only valid for category vocabulary';
  end if;

  if p_kind <> 'payment' and p_linked_account_id is not null then
    raise exception 'linked account is only valid for payment vocabulary';
  end if;

  if p_linked_account_id is not null and not exists (
    select 1
    from public.accounts
    where id = p_linked_account_id
      and user_id = v_user_id
  ) then
    raise exception 'linked account not found or permission denied';
  end if;

  v_normalized_name := lower(regexp_replace(v_display_name, '\s+', ' ', 'g'));

  insert into public.user_finance_vocabulary (
    user_id,
    kind,
    display_name,
    normalized_name,
    primary_category,
    linked_account_id,
    source,
    status,
    usage_count,
    last_used_at,
    updated_at
  ) values (
    v_user_id,
    p_kind,
    v_display_name,
    v_normalized_name,
    v_primary_category,
    p_linked_account_id,
    'user_confirmed',
    'active',
    1,
    now(),
    now()
  )
  on conflict (user_id, kind, normalized_name)
  do update set
    display_name = excluded.display_name,
    primary_category = coalesce(excluded.primary_category, public.user_finance_vocabulary.primary_category),
    linked_account_id = coalesce(excluded.linked_account_id, public.user_finance_vocabulary.linked_account_id),
    source = case
      when public.user_finance_vocabulary.source = 'system' then 'system'
      else 'user_confirmed'
    end,
    status = 'active',
    usage_count = public.user_finance_vocabulary.usage_count + 1,
    last_used_at = now(),
    updated_at = now()
  returning * into v_row;

  return to_jsonb(v_row);
end;
$$;

revoke all on function public.record_user_finance_vocabulary(text, text, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.record_user_finance_vocabulary(text, text, text, uuid)
  to authenticated;
