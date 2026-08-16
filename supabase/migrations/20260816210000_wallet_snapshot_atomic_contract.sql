create unique index if not exists uq_liability_payments_active_evidence
  on public.liability_payments(evidence_record_id)
  where evidence_record_id is not null and status <> 'voided';

create or replace function public.apply_wallet_snapshot(
  p_record_id uuid,
  p_account_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_record public.data_records%rowtype;
  v_account public.accounts%rowtype;
  v_cycle public.account_repayment_cycles%rowtype;
  v_payment public.liability_payments%rowtype;
  v_payload jsonb;
  v_kind text;
  v_amount_text text;
  v_amount numeric(14,2);
  v_snapshot_at timestamptz;
  v_account_id uuid;
  v_account_type public.account_type;
  v_account_name text;
  v_institution text;
  v_last4 text;
  v_bill_day integer;
  v_payment_due_day integer;
  v_cycle_month text;
  v_month_start date;
  v_due_date date;
  v_status text;
  v_balance_scope text;
  v_confidence numeric(5,4);
  v_active_entries integer := 0;
  v_active_payments integer := 0;
  v_delta numeric(14,2) := 0;
  v_inserted integer := 0;
  v_created boolean := false;
  v_adopted boolean := false;
  v_replayed boolean := false;
  v_review_required boolean := false;
  v_balance_changed boolean := false;
  v_outcome text;
begin
  if v_user_id is null then
    raise exception using message = 'not_authenticated';
  end if;
  if p_record_id is null then
    raise exception using message = 'wallet_snapshot_not_found';
  end if;

  select * into v_record
  from public.data_records
  where id = p_record_id
    and user_id = v_user_id
    and domain_key = 'wallet'
  for update;

  if not found then
    raise exception using message = 'wallet_snapshot_not_found';
  end if;

  v_payload := coalesce(v_record.payload_jsonb, '{}'::jsonb);
  v_kind := coalesce(
    nullif(v_record.account_snapshot_kind, ''),
    nullif(lower(v_payload->>'account_snapshot_kind'), ''),
    case lower(v_payload->>'record_kind')
      when 'liability_snapshot' then 'liability'
      when 'asset_snapshot' then 'asset'
      else null
    end
  );
  if v_kind is null or v_kind not in ('asset', 'liability') then
    raise exception using message = 'invalid_wallet_snapshot';
  end if;

  v_amount_text := coalesce(
    v_record.snapshot_balance::text,
    nullif(v_payload->>'snapshot_balance', ''),
    nullif(v_payload->>'amount', '')
  );
  if v_amount_text is null or v_amount_text !~ '^[0-9]+([.][0-9]+)?$' then
    raise exception using message = 'invalid_wallet_snapshot';
  end if;
  v_amount := round(v_amount_text::numeric, 2);
  if v_amount < 0 then
    raise exception using message = 'invalid_wallet_snapshot';
  end if;

  v_snapshot_at := coalesce(v_record.snapshot_at, v_record.occurred_at, v_record.created_at, now());
  v_status := lower(coalesce(nullif(v_payload->>'status', ''), 'unknown'));
  v_balance_scope := lower(coalesce(nullif(v_payload->>'balance_scope', ''), 'statement'));

  v_cycle_month := coalesce(
    nullif(v_payload->>'cycle_month', ''),
    nullif(v_payload->>'statement_month', ''),
    nullif(v_payload->>'bill_month', '')
  );
  if nullif(v_payload->>'due_date', '') is not null then
    if (v_payload->>'due_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception using message = 'invalid_wallet_snapshot';
    end if;
    begin
      v_due_date := (v_payload->>'due_date')::date;
    exception when others then
      raise exception using message = 'invalid_wallet_snapshot';
    end;
    if to_char(v_due_date, 'YYYY-MM-DD') <> v_payload->>'due_date' then
      raise exception using message = 'invalid_wallet_snapshot';
    end if;
    v_cycle_month := coalesce(v_cycle_month, to_char(v_due_date, 'YYYY-MM'));
  end if;
  if v_cycle_month is not null then
    if v_cycle_month !~ '^[0-9]{4}-[0-9]{2}$' then
      raise exception using message = 'invalid_wallet_snapshot';
    end if;
    v_month_start := to_date(v_cycle_month || '-01', 'YYYY-MM-DD');
    if to_char(v_month_start, 'YYYY-MM') <> v_cycle_month then
      raise exception using message = 'invalid_wallet_snapshot';
    end if;
  end if;

  if coalesce(v_payload->>'bill_day', '') ~ '^[0-9]{1,2}$' then
    v_bill_day := (v_payload->>'bill_day')::integer;
    if v_bill_day not between 1 and 31 then v_bill_day := null; end if;
  end if;
  if coalesce(v_payload->>'payment_due_day', '') ~ '^[0-9]{1,2}$' then
    v_payment_due_day := (v_payload->>'payment_due_day')::integer;
    if v_payment_due_day not between 1 and 31 then v_payment_due_day := null; end if;
  end if;
  if coalesce(v_payload->>'confidence', '') ~ '^[0-9]+([.][0-9]+)?$' then
    v_confidence := least(greatest((v_payload->>'confidence')::numeric, 0), 1)::numeric(5,4);
  end if;

  v_account_name := left(coalesce(nullif(v_payload->>'account_name', ''), nullif(v_record.title, ''), '未命名账户'), 120);
  v_institution := nullif(left(coalesce(v_payload->>'institution', v_payload->>'account_name', ''), 120), '');
  if coalesce(v_payload->>'last4', '') ~ '^[0-9]{4}$' then
    v_last4 := v_payload->>'last4';
  end if;

  if lower(coalesce(v_payload->>'account_type', '')) in (
    'cash', 'wallet_balance', 'debit_card', 'credit_card', 'credit_line', 'other'
  ) then
    v_account_type := lower(v_payload->>'account_type')::public.account_type;
  else
    v_account_type := case when v_kind = 'liability' then 'credit_line' else 'wallet_balance' end;
  end if;
  if (v_kind = 'liability' and v_account_type not in ('credit_card', 'credit_line'))
     or (v_kind = 'asset' and v_account_type in ('credit_card', 'credit_line')) then
    v_account_type := case when v_kind = 'liability' then 'credit_line' else 'wallet_balance' end;
  end if;

  if v_record.linked_account_id is not null then
    if p_account_id is not null and p_account_id <> v_record.linked_account_id then
      raise exception using message = 'snapshot_link_conflict';
    end if;
    v_account_id := v_record.linked_account_id;
    v_replayed := true;
  else
    v_account_id := p_account_id;
  end if;

  if v_account_id is null then
    select id into v_account_id
    from public.accounts
    where user_id = v_user_id
      and source_record_table = 'data_records'
      and source_record_id = v_record.id
    order by created_at asc, id asc
    limit 1;
    if found then v_replayed := true; end if;
  end if;

  if v_account_id is null then
    insert into public.accounts (
      user_id, name, type, institution, last4, currency,
      initial_balance, current_balance, snapshot_balance, snapshot_at,
      source_record_table, source_record_id, bill_day, payment_due_day,
      last_reconciled_at
    ) values (
      v_user_id, v_account_name, v_account_type, v_institution, v_last4, 'CNY',
      v_amount, v_amount, v_amount, v_snapshot_at,
      'data_records', v_record.id,
      case when v_kind = 'liability' then v_bill_day else null end,
      case when v_kind = 'liability' then v_payment_due_day else null end,
      case when v_kind = 'liability' and v_balance_scope = 'current_total' then v_snapshot_at else null end
    )
    returning * into v_account;
    v_account_id := v_account.id;
    v_created := true;
    v_adopted := true;
  else
    select * into v_account
    from public.accounts
    where id = v_account_id
      and user_id = v_user_id
    for update;
    if not found then
      raise exception using message = 'account_not_found';
    end if;
    if v_account.is_archived then
      raise exception using message = 'account_archived';
    end if;
    if (v_kind = 'liability' and v_account.type not in ('credit_card', 'credit_line'))
       or (v_kind = 'asset' and v_account.type in ('credit_card', 'credit_line')) then
      raise exception using message = 'account_kind_mismatch';
    end if;

    select count(*) into v_active_entries
    from public.account_entries
    where account_id = v_account.id
      and user_id = v_user_id
      and is_voided = false
      and entry_type <> 'snapshot_initialization';

    if coalesce(v_account.initial_balance, 0) = 0
       and coalesce(v_account.current_balance, 0) = 0
       and v_active_entries = 0 then
      update public.accounts
         set initial_balance = v_amount,
             current_balance = v_amount,
             last_reconciled_at = case
               when v_kind = 'liability' and v_balance_scope = 'current_total'
               then greatest(coalesce(last_reconciled_at, v_snapshot_at), v_snapshot_at)
               else last_reconciled_at
             end,
             updated_at = now()
       where id = v_account.id
       returning * into v_account;
      v_adopted := true;
    end if;
  end if;

  if v_adopted and v_amount > 0 then
    insert into public.account_entries (
      user_id, account_id, direction, amount, entry_type,
      source_table, source_id, occurred_at, note
    ) values (
      v_user_id, v_account_id, 'in', v_amount, 'snapshot_initialization',
      'data_records', v_record.id, v_snapshot_at, '钱包快照建立账户期初余额'
    )
    on conflict do nothing;
  end if;

  update public.accounts
     set snapshot_balance = case
           when snapshot_at is null or v_snapshot_at >= snapshot_at then v_amount
           else snapshot_balance
         end,
         snapshot_at = case
           when snapshot_at is null or v_snapshot_at >= snapshot_at then v_snapshot_at
           else snapshot_at
         end,
         bill_day = case
           when v_kind = 'liability' and (snapshot_at is null or v_snapshot_at >= snapshot_at)
           then coalesce(v_bill_day, bill_day)
           else bill_day
         end,
         payment_due_day = case
           when v_kind = 'liability' and (snapshot_at is null or v_snapshot_at >= snapshot_at)
           then coalesce(v_payment_due_day, payment_due_day)
           else payment_due_day
         end,
         updated_at = now()
   where id = v_account_id
   returning * into v_account;

  update public.data_records
     set linked_account_id = v_account_id,
         account_snapshot_kind = v_kind,
         snapshot_balance = v_amount,
         snapshot_at = v_snapshot_at,
         payload_jsonb = v_payload || jsonb_build_object(
           'linked_account_id', v_account_id,
           'account_snapshot_kind', v_kind,
           'snapshot_balance', v_amount
         ),
         updated_at = now()
   where id = v_record.id
     and user_id = v_user_id;

  if v_kind = 'liability'
     and v_balance_scope = 'current_total'
     and not v_created
     and not v_adopted
     and (v_account.last_reconciled_at is null or v_snapshot_at > v_account.last_reconciled_at) then
    v_delta := round(v_amount - coalesce(v_account.current_balance, 0), 2);
    if abs(v_delta) >= 0.01 then
      insert into public.account_entries (
        user_id, account_id, direction, amount, entry_type,
        source_table, source_id, occurred_at, note
      ) values (
        v_user_id,
        v_account.id,
        case when v_delta > 0 then 'in' else 'out' end,
        abs(v_delta),
        'adjustment',
        'data_records',
        v_record.id,
        v_snapshot_at,
        '钱包快照校准当前总欠款'
      )
      on conflict do nothing;
      get diagnostics v_inserted = row_count;
      v_balance_changed := v_inserted > 0;
    end if;
    if abs(v_delta) < 0.01 or v_inserted > 0 then
      update public.accounts
         set last_reconciled_at = greatest(coalesce(last_reconciled_at, v_snapshot_at), v_snapshot_at),
             updated_at = now()
       where id = v_account.id
       returning * into v_account;
    end if;
  end if;

  if v_kind = 'liability' then
    if v_cycle_month is null then
      v_review_required := true;
    elsif v_status = 'paid' then
      select * into v_cycle
      from public.account_repayment_cycles
      where account_id = v_account_id
        and user_id = v_user_id
        and cycle_month = v_cycle_month
      for update;

      if not found then
        v_review_required := true;
      else
        select * into v_payment
        from public.liability_payments
        where user_id = v_user_id
          and statement_id = v_cycle.id
          and evidence_record_id = v_record.id
          and status <> 'voided'
        order by created_at asc, id asc
        limit 1;

        if found then
          v_replayed := true;
        else
          select count(*) into v_active_payments
          from public.liability_payments
          where user_id = v_user_id
            and statement_id = v_cycle.id
            and status <> 'voided';

          if v_active_payments > 0
             or v_cycle.status not in ('draft_estimated', 'pending', 'due_today', 'overdue_unconfirmed') then
            v_review_required := true;
          else
            select * into v_cycle
            from public.set_repayment_cycle_paid_amount(
              p_cycle_id => v_cycle.id,
              p_paid_amount => v_amount,
              p_paid_at => v_snapshot_at,
              p_debit_account_id => null,
              p_status => null,
              p_note => '钱包快照显示已还款'
            );

            update public.liability_payments
               set source = 'screenshot',
                   evidence_record_id = v_record.id,
                   updated_at = now()
             where user_id = v_user_id
               and statement_id = v_cycle.id
               and status <> 'voided'
            returning * into v_payment;

            if v_payment.id is null then
              raise exception using message = 'repayment_evidence_conflict';
            end if;

            update public.account_repayment_cycles
               set source = 'screenshot',
                   evidence_record_id = v_record.id,
                   confidence = coalesce(v_confidence, confidence),
                   statement_source_priority = greatest(statement_source_priority, 90),
                   updated_at = now()
             where id = v_cycle.id
               and user_id = v_user_id
            returning * into v_cycle;
            v_balance_changed := true;
          end if;
        end if;
      end if;
    else
      if v_due_date is null and v_payment_due_day is null then
        v_payment_due_day := v_account.payment_due_day;
      end if;
      if v_due_date is null and v_payment_due_day is not null then
        v_due_date := make_date(
          extract(year from v_month_start)::integer,
          extract(month from v_month_start)::integer,
          least(
            v_payment_due_day,
            extract(day from (v_month_start + interval '1 month - 1 day'))::integer
          )
        );
      end if;

      select * into v_cycle
      from public.account_repayment_cycles
      where account_id = v_account_id
        and user_id = v_user_id
        and cycle_month = v_cycle_month
      for update;

      if not found then
        insert into public.account_repayment_cycles (
          user_id, account_id, cycle_month, due_date,
          statement_amount, original_statement_amount, paid_amount,
          remaining_amount, carried_over_amount, status, source,
          evidence_record_id, confidence, statement_source_priority, note
        ) values (
          v_user_id, v_account_id, v_cycle_month, v_due_date,
          v_amount, v_amount, 0,
          v_amount, 0,
          case
            when v_due_date = current_date then 'due_today'
            when v_due_date < current_date then 'overdue_unconfirmed'
            else 'pending'
          end,
          'screenshot', v_record.id, v_confidence, 90, '钱包快照生成待还账期'
        )
        returning * into v_cycle;
      elsif v_cycle.evidence_record_id = v_record.id then
        v_replayed := true;
      else
        select count(*) into v_active_payments
        from public.liability_payments
        where user_id = v_user_id
          and statement_id = v_cycle.id
          and status <> 'voided';

        if v_cycle.source = 'system'
           and v_cycle.paid_amount = 0
           and v_cycle.status in ('draft_estimated', 'pending', 'due_today', 'overdue_unconfirmed')
           and v_cycle.statement_source_priority <= 90
           and v_active_payments = 0 then
          update public.account_repayment_cycles
             set due_date = coalesce(v_due_date, due_date),
                 statement_amount = v_amount,
                 original_statement_amount = v_amount,
                 remaining_amount = v_amount,
                 source = 'screenshot',
                 evidence_record_id = v_record.id,
                 confidence = coalesce(v_confidence, confidence),
                 statement_source_priority = 90,
                 note = '钱包快照更新待还账期',
                 updated_at = now()
           where id = v_cycle.id
           returning * into v_cycle;
        else
          v_review_required := true;
        end if;
      end if;
    end if;
  end if;

  select * into v_account
  from public.accounts
  where id = v_account_id and user_id = v_user_id;

  v_outcome := case
    when v_review_required then 'needs_confirmation'
    when v_replayed then 'replayed'
    when v_created then 'created'
    else 'linked'
  end;

  return jsonb_build_object(
    'outcome', v_outcome,
    'record_id', v_record.id,
    'linked_account_id', v_account_id,
    'account', to_jsonb(v_account),
    'cycle', case when v_cycle.id is null then null else to_jsonb(v_cycle) end,
    'payment', case when v_payment.id is null then null else to_jsonb(v_payment) end,
    'balance_changed', v_balance_changed or v_adopted,
    'review_required', v_review_required
  );
end;
$$;

revoke all on function public.apply_wallet_snapshot(uuid, uuid) from public, anon;
grant execute on function public.apply_wallet_snapshot(uuid, uuid) to authenticated;
