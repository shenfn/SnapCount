begin;

lock table public.accounts in share row exclusive mode;

-- Normalize legacy rows before installing constraints.
update public.accounts
set is_default_expense = false,
    is_default_income = false,
    updated_at = now()
where is_archived
  and (is_default_expense or is_default_income);

with ranked as (
  select id,
         row_number() over (
           partition by user_id
           order by sort_order asc, created_at asc, id asc
         ) as position
  from public.accounts
  where not is_archived
    and is_default_expense
)
update public.accounts account
set is_default_expense = false,
    updated_at = now()
from ranked
where account.id = ranked.id
  and ranked.position > 1;

with ranked as (
  select id,
         row_number() over (
           partition by user_id
           order by sort_order asc, created_at asc, id asc
         ) as position
  from public.accounts
  where not is_archived
    and is_default_income
)
update public.accounts account
set is_default_income = false,
    updated_at = now()
from ranked
where account.id = ranked.id
  and ranked.position > 1;

create unique index if not exists uq_accounts_active_default_expense
  on public.accounts (user_id)
  where not is_archived and is_default_expense;

create unique index if not exists uq_accounts_active_default_income
  on public.accounts (user_id)
  where not is_archived and is_default_income;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.accounts'::regclass
      and conname = 'accounts_archived_not_default'
  ) then
    alter table public.accounts
      add constraint accounts_archived_not_default
      check (not is_archived or (not is_default_expense and not is_default_income));
  end if;
end;
$$;

create or replace function public.normalize_account_management_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 66066));

  if new.is_archived then
    new.is_default_expense := false;
    new.is_default_income := false;
  else
    if new.is_default_expense then
      update public.accounts
      set is_default_expense = false,
          updated_at = now()
      where user_id = new.user_id
        and id <> new.id
        and is_default_expense;
    end if;

    if new.is_default_income then
      update public.accounts
      set is_default_income = false,
          updated_at = now()
      where user_id = new.user_id
        and id <> new.id
        and is_default_income;
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists tr_normalize_account_management_write on public.accounts;
create trigger tr_normalize_account_management_write
  before insert or update on public.accounts
  for each row execute function public.normalize_account_management_write();

create or replace function public.save_account(
  p_name text,
  p_type public.account_type,
  p_account_id uuid default null,
  p_institution text default null,
  p_last4 text default null,
  p_initial_balance numeric default 0,
  p_bill_day integer default null,
  p_payment_due_day integer default null,
  p_auto_debit_account_id uuid default null,
  p_auto_confirm_repayment boolean default false,
  p_is_default_expense boolean default false,
  p_is_default_income boolean default false
)
returns public.accounts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_account public.accounts%rowtype;
  v_name text := btrim(coalesce(p_name, ''));
  v_institution text := nullif(btrim(coalesce(p_institution, '')), '');
  v_last4 text := nullif(btrim(coalesce(p_last4, '')), '');
  v_old_is_liability boolean;
  v_new_is_liability boolean := p_type in ('credit_card', 'credit_line');
  v_has_history_or_reference boolean := false;
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;

  if v_name = '' or length(v_name) > 30 then
    raise exception 'invalid_account_data: account name must contain 1 to 30 characters';
  end if;
  if p_type is null then
    raise exception 'invalid_account_data: account type is required';
  end if;
  if v_institution is not null and length(v_institution) > 30 then
    raise exception 'invalid_account_data: institution must contain at most 30 characters';
  end if;
  if v_last4 is not null and v_last4 !~ '^[0-9]{4}$' then
    raise exception 'invalid_account_data: last4 must contain exactly four digits';
  end if;
  if p_initial_balance is null or p_initial_balance < 0 then
    raise exception 'invalid_account_data: initial balance must be nonnegative';
  end if;
  if p_bill_day is not null and p_bill_day not between 1 and 31 then
    raise exception 'invalid_account_data: bill day must be between 1 and 31';
  end if;
  if p_payment_due_day is not null and p_payment_due_day not between 1 and 31 then
    raise exception 'invalid_account_data: payment due day must be between 1 and 31';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 66066));

  if p_account_id is not null then
    select *
    into v_account
    from public.accounts
    where id = p_account_id
      and user_id = v_user_id
    for update;

    if not found then
      raise exception 'account_not_found: account not found or permission denied';
    end if;

    v_old_is_liability := v_account.type in ('credit_card', 'credit_line');

    if v_old_is_liability <> v_new_is_liability then
      select exists (
        select 1
        from public.account_entries entry
        where entry.account_id = v_account.id
      )
      or exists (
        select 1
        from public.account_repayment_cycles cycle
        where cycle.account_id = v_account.id
           or cycle.auto_debit_account_id = v_account.id
      )
      or exists (
        select 1
        from public.liability_payments payment
        where payment.account_id = v_account.id
           or payment.debit_account_id = v_account.id
      )
      or exists (
        select 1
        from public.accounts dependent
        where dependent.user_id = v_user_id
          and dependent.id <> v_account.id
          and dependent.auto_debit_account_id = v_account.id
      )
      into v_has_history_or_reference;

      if v_has_history_or_reference then
        raise exception 'account_type_transition_blocked';
      end if;
    end if;
  end if;

  if v_new_is_liability and p_auto_debit_account_id is not null then
    if not exists (
      select 1
      from public.accounts debit
      where debit.id = p_auto_debit_account_id
        and debit.user_id = v_user_id
        and not debit.is_archived
        and debit.type not in ('credit_card', 'credit_line')
    ) then
      raise exception 'invalid_auto_debit_account';
    end if;
  end if;

  if p_account_id is null then
    insert into public.accounts (
      user_id,
      name,
      type,
      institution,
      last4,
      initial_balance,
      current_balance,
      bill_day,
      payment_due_day,
      auto_debit_account_id,
      auto_confirm_repayment,
      is_default_expense,
      is_default_income
    ) values (
      v_user_id,
      v_name,
      p_type,
      v_institution,
      v_last4,
      p_initial_balance,
      p_initial_balance,
      case when v_new_is_liability then p_bill_day else null end,
      case when v_new_is_liability then p_payment_due_day else null end,
      case when v_new_is_liability then p_auto_debit_account_id else null end,
      case when v_new_is_liability then coalesce(p_auto_confirm_repayment, false) else false end,
      coalesce(p_is_default_expense, false),
      coalesce(p_is_default_income, false)
    )
    returning * into v_account;
  else
    update public.accounts
    set name = v_name,
        type = p_type,
        institution = v_institution,
        last4 = v_last4,
        bill_day = case when v_new_is_liability then p_bill_day else null end,
        payment_due_day = case when v_new_is_liability then p_payment_due_day else null end,
        auto_debit_account_id = case when v_new_is_liability then p_auto_debit_account_id else null end,
        auto_confirm_repayment = case when v_new_is_liability then coalesce(p_auto_confirm_repayment, false) else false end,
        is_default_expense = coalesce(p_is_default_expense, false),
        is_default_income = coalesce(p_is_default_income, false),
        updated_at = now()
    where id = p_account_id
      and user_id = v_user_id
    returning * into v_account;
  end if;

  return v_account;
end;
$$;

create or replace function public.set_account_archived(
  p_account_id uuid,
  p_archived boolean
)
returns public.accounts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_account public.accounts%rowtype;
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;
  if p_account_id is null or p_archived is null then
    raise exception 'invalid_account_data: account id and archived state are required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 66066));

  select *
  into v_account
  from public.accounts
  where id = p_account_id
    and user_id = v_user_id
  for update;

  if not found then
    raise exception 'account_not_found: account not found or permission denied';
  end if;

  update public.accounts
  set is_archived = p_archived,
      is_default_expense = case when p_archived then false else is_default_expense end,
      is_default_income = case when p_archived then false else is_default_income end,
      updated_at = now()
  where id = p_account_id
    and user_id = v_user_id
  returning * into v_account;

  if p_archived then
    update public.accounts
    set auto_debit_account_id = null,
        updated_at = now()
    where user_id = v_user_id
      and auto_debit_account_id = p_account_id;

    update public.account_repayment_cycles
    set auto_debit_account_id = null,
        updated_at = now()
    where user_id = v_user_id
      and auto_debit_account_id = p_account_id
      and status not in ('paid', 'ignored', 'reconciled', 'replaced');
  end if;

  return v_account;
end;
$$;

revoke all on function public.save_account(
  text, public.account_type, uuid, text, text, numeric,
  integer, integer, uuid, boolean, boolean, boolean
) from public, anon;
revoke all on function public.set_account_archived(uuid, boolean) from public, anon;
revoke all on function public.normalize_account_management_write() from public, anon, authenticated;

grant execute on function public.save_account(
  text, public.account_type, uuid, text, text, numeric,
  integer, integer, uuid, boolean, boolean, boolean
) to authenticated, service_role;
grant execute on function public.set_account_archived(uuid, boolean)
  to authenticated, service_role;

comment on function public.save_account(
  text, public.account_type, uuid, text, text, numeric,
  integer, integer, uuid, boolean, boolean, boolean
) is 'Canonical account create/edit command. Account ownership comes from auth.uid().';

comment on function public.set_account_archived(uuid, boolean)
  is 'Canonical soft archive/restore command preserving balances and historical records.';

commit;
