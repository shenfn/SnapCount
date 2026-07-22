create or replace function public.security_test_assert(p_condition boolean, p_message text)
returns void
language plpgsql
as $$
begin
  if p_condition is not true then
    raise exception 'security test failed: %', p_message;
  end if;
end;
$$;

select public.security_test_assert(
  (select companion_message from public.transactions where id = '17171717-1717-4717-8717-171717171717') is null,
  'known unsupported historical finance companion text must be cleared'
);

select public.security_test_assert(
  (
    select companion_message is null
      and not (extracted_json ? 'ai_feedback')
      and not (extracted_json ? 'companion_message')
    from public.staging_records
    where id = '18181818-1818-4818-8818-181818181818'
  ),
  'unsafe staging tone and unverified feedback must be cleared'
);

select public.security_test_assert(
  not exists (
    select 1
    from public.user_companion_memories
    where id = '19191919-1919-4919-8919-191919191919'
  ),
  'unsafe historical statistics must not remain in companion memory'
);

select public.security_test_assert(
  not exists (
    select 1 from public.user_configs
    where expression_improvement_enabled is true
  ),
  'Expression improvement must default to opt-out'
);
select public.security_test_assert(
  not has_function_privilege(
    'authenticated',
    'public.cleanup_expression_improvement_retention()',
    'EXECUTE'
  ),
  'authenticated users must not execute Expression retention cleanup directly'
);
select public.security_test_assert(
  has_function_privilege(
    'service_role',
    'public.cleanup_expression_improvement_retention()',
    'EXECUTE'
  ),
  'service role must execute Expression retention cleanup'
);

update public.user_configs
set expression_improvement_enabled = true,
    expression_improvement_consent_at = '2000-01-01'::timestamptz
where user_id = '11111111-1111-4111-8111-111111111111';

select public.security_test_assert(
  (
    select expression_improvement_consent_at > '2026-01-01'::timestamptz
      and expression_improvement_withdrawn_at is null
    from public.user_configs
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'Expression improvement opt-in must use a server timestamp'
);

insert into public.expression_shadow_runs (id, user_id) values (
  '18181818-1818-4818-8818-181818181818',
  '11111111-1111-4111-8111-111111111111'
);
insert into public.expression_exposure_events (id, user_id, metadata, selection_mode) values
  (
    '19191919-1919-4919-8919-191919191919',
    '11111111-1111-4111-8111-111111111111',
    '{"source":"production_baseline"}'::jsonb,
    'legacy_voice'
  ),
  (
    '20202020-2020-4020-8020-202020202020',
    '11111111-1111-4111-8111-111111111111',
    '{"source":"production_baseline"}'::jsonb,
    'legacy_voice'
  );
insert into public.expression_feedback_events (id, user_id, exposure_event_id) values (
  '21212121-2121-4121-8121-212121212121',
  '11111111-1111-4111-8111-111111111111',
  '20202020-2020-4020-8020-202020202020'
);

update public.user_configs
set expression_improvement_enabled = false
where user_id = '11111111-1111-4111-8111-111111111111';

select public.security_test_assert(
  not exists (
    select 1 from public.expression_shadow_runs
    where id = '18181818-1818-4818-8818-181818181818'
  ),
  'opt-out must purge background Shadow rows immediately'
);
select public.security_test_assert(
  not exists (
    select 1 from public.expression_exposure_events
    where id = '19191919-1919-4919-8919-191919191919'
  ),
  'opt-out must purge unlinked background exposure rows immediately'
);
select public.security_test_assert(
  exists (
    select 1 from public.expression_exposure_events
    where id = '20202020-2020-4020-8020-202020202020'
  ),
  'opt-out must preserve exposure context linked to explicit feedback'
);
select public.security_test_assert(
  (
    select expression_improvement_withdrawn_at is not null
    from public.user_configs
    where user_id = '11111111-1111-4111-8111-111111111111'
  ),
  'Expression improvement opt-out must record a server withdrawal timestamp'
);

select public.security_test_assert(
  not has_function_privilege('anon', 'public.rebuild_sleep_profile(uuid)', 'execute'),
  'anon must not execute profile rebuilds'
);
select public.security_test_assert(
  not has_function_privilege('authenticated', 'public.recalculate_account_balance(uuid)', 'execute'),
  'authenticated must not execute balance repair'
);
select public.security_test_assert(
  has_function_privilege('authenticated', 'public.normalize_receipt_image_path(text)', 'execute'),
  'authenticated writes need the immutable index helper'
);
select public.security_test_assert(
  not has_function_privilege('authenticated', 'public.prepare_receipt_image_migration(uuid,text,text)', 'execute'),
  'migration preparation must remain service-only'
);
select public.security_test_assert(
  (
    select user_id
    from public.ai_recognition_logs
    where image_url like '%/2026-01-02/owner.jpg?token=legacy-unowned-log'
  ) = '11111111-1111-4111-8111-111111111111'::uuid,
  'unowned legacy AI logs must inherit the only known image owner'
);

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
set role authenticated;

insert into public.data_records (user_id, source_image_path) values (
  '11111111-1111-4111-8111-111111111111',
  '11111111-1111-4111-8111-111111111111/new.jpg'
);

update public.staging_records
set image_path = '2026-01-03/missing-object.jpg'
where user_id = '11111111-1111-4111-8111-111111111111'
  and image_path = '2026-01-03/missing-object.jpg';

select public.security_test_assert(
  public.can_access_receipt_image('2026-01-03/missing-object.jpg'),
  'missing objects must retain unambiguous ownership for record compatibility'
);
select public.security_test_assert(
  (select count(*) from storage.objects where name = '2026-01-03/missing-object.jpg') = 0,
  'missing object references must not create Storage objects'
);

do $$
declare
  blocked boolean := false;
begin
  begin
    insert into public.data_records (user_id, source_image_path) values (
      '11111111-1111-4111-8111-111111111111',
      '2026-01-01/victim.jpg'
    );
  exception when others then
    blocked := position('belongs to another user' in sqlerrm) > 0;
  end;
  if not blocked then
    raise exception 'foreign legacy path injection was not blocked';
  end if;
end;
$$;

select public.security_test_assert(
  public.can_access_receipt_image('2026-01-02/owner.jpg'),
  'owner must access an owned legacy image'
);
select public.security_test_assert(
  not public.can_access_receipt_image('2026-01-01/victim.jpg'),
  'owner must not access another user image'
);
select public.security_test_assert(
  (select count(*) from storage.objects where bucket_id = 'receipt-images' and name = '2026-01-01/victim.jpg') = 0,
  'Storage RLS must hide the foreign object'
);

reset role;

select public.security_test_assert(
  public.is_business_image_path_referenced(
    '11111111-1111-4111-8111-111111111111',
    '2026-01-02/owner.jpg'
  ),
  'signed URL references must match their normalized Storage path'
);

insert into public.receipt_image_owners (
  bucket_name,
  bucket_path,
  user_id,
  ownership_source
) values (
  'receipt-images',
  '2026-01-04/delete-signed.jpg',
  '11111111-1111-4111-8111-111111111111',
  'security_test'
);

insert into storage.objects (bucket_id, name) values (
  'receipt-images',
  '2026-01-04/delete-signed.jpg'
);

insert into public.transactions (user_id, image_url) values (
  '11111111-1111-4111-8111-111111111111',
  'https://fixture.supabase.co/storage/v1/object/sign/receipt-images/2026-01-04/delete-signed.jpg?token=legacy'
);

insert into public.image_cleanup_queue (user_id, bucket_path, status) values (
  '11111111-1111-4111-8111-111111111111',
  '2026-01-04/delete-signed.jpg',
  'processing'
);

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
set role authenticated;
do $$
declare
  blocked boolean := false;
begin
  begin
    insert into public.data_records (user_id, source_image_path) values (
      '11111111-1111-4111-8111-111111111111',
      'https://fixture.supabase.co/storage/v1/object/sign/receipt-images/2026-01-04/delete-signed.jpg?token=new'
    );
  exception when others then
    blocked := position('cleanup is in progress' in sqlerrm) > 0;
  end;
  if not blocked then
    raise exception 'signed URL reference was not blocked during cleanup';
  end if;
end;
$$;
reset role;

delete from public.image_cleanup_queue
where bucket_path = '2026-01-04/delete-signed.jpg';

delete from public.transactions
where image_url like '%/2026-01-04/delete-signed.jpg?token=legacy';

select public.security_test_assert(
  exists (
    select 1 from public.image_cleanup_queue
    where user_id = '11111111-1111-4111-8111-111111111111'
      and bucket_path = '2026-01-04/delete-signed.jpg'
      and cleanup_reason = 'record_delete'
      and status = 'pending'
  ),
  'deleting a signed URL record must queue the normalized Storage path'
);

delete from public.image_cleanup_queue
where bucket_path = '2026-01-04/delete-signed.jpg';

insert into public.account_deletion_requests (user_id, status) values (
  '11111111-1111-4111-8111-111111111111',
  'cleaning'
);

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
set role authenticated;
do $$
declare
  blocked boolean := false;
begin
  begin
    insert into public.data_records (user_id, source_image_path) values (
      '11111111-1111-4111-8111-111111111111',
      '11111111-1111-4111-8111-111111111111/late-upload.jpg'
    );
  exception when others then
    blocked := position('account deletion is in progress' in sqlerrm) > 0;
  end;
  if not blocked then
    raise exception 'new image reference was not blocked during account deletion';
  end if;
end;
$$;
reset role;

delete from public.account_deletion_requests
where user_id = '11111111-1111-4111-8111-111111111111';

select set_config('request.jwt.claim.sub', '', false);
select set_config('request.jwt.claim.role', 'anon', false);
set role anon;
select public.security_test_assert(
  (select count(*) from storage.objects where bucket_id = 'receipt-images') = 0,
  'anon must not list receipt images'
);
reset role;

do $$
declare
  blocked boolean := false;
begin
  begin
    insert into auth.users (id, raw_user_meta_data) values (
      '33333333-3333-4333-8333-333333333333',
      '{}'::jsonb
    );
  exception when others then
    blocked := position('current terms, privacy, and sensitive data consent are required' in sqlerrm) > 0;
  end;
  if not blocked then
    raise exception 'registration without current consent was not blocked';
  end if;
end;
$$;

insert into auth.users (id, raw_user_meta_data) values (
  '44444444-4444-4444-8444-444444444444',
  jsonb_build_object(
    'legal_consent_at', '2020-01-01T00:00:00Z',
    'sensitive_data_consent_at', '2020-01-01T00:00:00Z',
    'terms_version', '2026-07-19',
    'privacy_version', '2026-07-19'
  )
);

insert into auth.users (id, raw_user_meta_data) values (
  '66666666-6666-4666-8666-666666666666',
  jsonb_build_object(
    'legal_consent_at', '2020-01-01T00:00:00Z',
    'sensitive_data_consent_at', '2020-01-01T00:00:00Z',
    'terms_version', '2026-07-19',
    'privacy_version', '2026-07-22'
  )
);

select public.security_test_assert(
  exists (
    select 1 from public.user_configs
    where user_id = '44444444-4444-4444-8444-444444444444'
      and terms_version = '2026-07-19'
      and privacy_version = '2026-07-19'
      and legal_consent_at > '2026-01-01'::timestamptz
      and sensitive_data_consent_at = legal_consent_at
  ),
  'valid consent must use the server timestamp and current versions'
);
select public.security_test_assert(
  exists (
    select 1 from public.user_configs
    where user_id = '66666666-6666-4666-8666-666666666666'
      and privacy_version = '2026-07-22'
      and expression_improvement_enabled is false
  ),
  'new privacy version must register with Expression improvement disabled'
);

select set_config('request.jwt.claim.role', 'service_role', false);
set role service_role;

insert into public.accounts (id, user_id) values
  ('aaaaaaaa-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111'),
  ('aaaaaaaa-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222');

reset role;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
set role authenticated;

select public.record_user_finance_vocabulary('platform', 'Costco', null, null);
select public.record_user_finance_vocabulary(
  'payment',
  'Apple Pay',
  null,
  'aaaaaaaa-1111-4111-8111-111111111111'
);

select public.security_test_assert(
  (select count(*) from public.user_finance_vocabulary) = 2,
  'authenticated users must only see their own finance vocabulary'
);

do $$
declare
  blocked boolean := false;
begin
  begin
    insert into public.user_finance_vocabulary (
      user_id,
      kind,
      display_name,
      normalized_name
    ) values (
      '11111111-1111-4111-8111-111111111111',
      'platform',
      '绕过 RPC',
      '绕过 rpc'
    );
  exception when insufficient_privilege then
    blocked := true;
  end;
  if not blocked then
    raise exception 'authenticated users must not write finance vocabulary directly';
  end if;
end;
$$;

do $$
declare
  blocked boolean := false;
begin
  begin
    perform public.record_user_finance_vocabulary('category', '咖啡', null, null);
  exception when others then
    blocked := position('stable primary taxonomy' in sqlerrm) > 0;
  end;
  if not blocked then
    raise exception 'custom values must not fragment primary expense categories';
  end if;
end;
$$;

do $$
declare
  blocked boolean := false;
begin
  begin
    perform public.record_user_finance_vocabulary(
      'payment',
      '他人银行卡',
      null,
      'aaaaaaaa-2222-4222-8222-222222222222'
    );
  exception when others then
    blocked := position('permission denied' in sqlerrm) > 0;
  end;
  if not blocked then
    raise exception 'finance vocabulary must not link another user account';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
set role authenticated;
select public.record_user_finance_vocabulary('platform', '盒马', null, null);
reset role;

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
set role authenticated;
select public.security_test_assert(
  not exists (
    select 1
    from public.user_finance_vocabulary
    where display_name = '盒马'
  ),
  'RLS must not expose another user finance vocabulary'
);
reset role;

select set_config('request.jwt.claim.role', 'service_role', false);
set role service_role;

do $$
declare
  blocked boolean := false;
begin
  begin
    insert into public.user_finance_vocabulary (
      user_id,
      kind,
      display_name,
      normalized_name
    ) values (
      '11111111-1111-4111-8111-111111111111',
      'platform',
      '服务端直写',
      '服务端直写'
    );
  exception when insufficient_privilege then
    blocked := true;
  end;
  if not blocked then
    raise exception 'service role must not turn unconfirmed AI values into personal vocabulary';
  end if;
end;
$$;

insert into auth.users (id, raw_user_meta_data) values (
  '55555555-5555-4555-8555-555555555555',
  jsonb_build_object(
    'legal_consent_at', now(),
    'sensitive_data_consent_at', now(),
    'terms_version', '2026-07-19',
    'privacy_version', '2026-07-19'
  )
);

insert into public.user_configs (user_id) values ('55555555-5555-4555-8555-555555555555')
on conflict (user_id) do nothing;

reset role;
select set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
set role authenticated;
select public.record_user_finance_vocabulary('platform', '待删除渠道', null, null);
reset role;
select set_config('request.jwt.claim.role', 'service_role', false);
set role service_role;

insert into storage.objects (bucket_id, name) values (
  'receipt-images',
  '55555555-5555-4555-8555-555555555555/account-delete.jpg'
);

insert into public.transactions (user_id, image_url) values (
  '55555555-5555-4555-8555-555555555555',
  '55555555-5555-4555-8555-555555555555/account-delete.jpg'
);

do $$
declare
  v_exposure_id uuid;
begin
  insert into public.expression_exposure_events (user_id)
  values ('55555555-5555-4555-8555-555555555555')
  returning id into v_exposure_id;
  insert into public.expression_feedback_events (user_id, exposure_event_id)
  values ('55555555-5555-4555-8555-555555555555', v_exposure_id);
  insert into public.expression_preference_signals (user_id, exposure_event_id)
  values ('55555555-5555-4555-8555-555555555555', v_exposure_id);
  insert into public.expression_preference_snapshots (user_id)
  values ('55555555-5555-4555-8555-555555555555');
  insert into public.expression_shadow_runs (user_id)
  values ('55555555-5555-4555-8555-555555555555');
end;
$$;

select public.delete_user_account_data('55555555-5555-4555-8555-555555555555');

select public.security_test_assert(
  exists (
    select 1 from public.image_cleanup_queue
    where user_id = '55555555-5555-4555-8555-555555555555'
      and bucket_path = '55555555-5555-4555-8555-555555555555/account-delete.jpg'
      and status = 'pending'
  ),
  'account deletion must preserve cleanup tasks created by record delete triggers'
);
select public.security_test_assert(
  not exists (select 1 from public.transactions where user_id = '55555555-5555-4555-8555-555555555555'),
  'account deletion must remove business records'
);
select public.security_test_assert(
  not exists (select 1 from public.expression_feedback_events where user_id = '55555555-5555-4555-8555-555555555555'),
  'account deletion must remove expression feedback before its exposure parent'
);
select public.security_test_assert(
  not exists (select 1 from public.user_finance_vocabulary where user_id = '55555555-5555-4555-8555-555555555555'),
  'account deletion must remove personal finance vocabulary before Auth deletion'
);
select public.security_test_assert(
  exists (select 1 from auth.users where id = '55555555-5555-4555-8555-555555555555'),
  'Auth deletion must wait while cleanup work remains'
);

select set_config(
  'security_test.job_id',
  (
    select id::text
    from public.prepare_receipt_image_migration(
      '11111111-1111-4111-8111-111111111111',
      '2026-01-02/owner.jpg',
      '11111111-1111-4111-8111-111111111111/legacy-signed-url/migrated.jpg'
    )
  ),
  false
);

select set_config(
  'security_test.lease_token',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  false
);

select public.claim_receipt_image_migration_job(
  current_setting('security_test.job_id')::uuid,
  current_setting('security_test.lease_token')::uuid,
  900
);

insert into storage.objects (bucket_id, name) values (
  'receipt-images',
  '11111111-1111-4111-8111-111111111111/legacy-signed-url/migrated.jpg'
);

select public.mark_receipt_image_migration_copied(
  current_setting('security_test.job_id')::uuid,
  current_setting('security_test.lease_token')::uuid,
  repeat('a', 64),
  repeat('a', 64)
);

do $$
declare
  blocked boolean := false;
begin
  begin
    update public.receipt_image_migration_jobs
    set status = 'pending'
    where id = current_setting('security_test.job_id')::uuid;
  exception when insufficient_privilege then
    blocked := true;
  end;
  if not blocked then
    raise exception 'service_role must not update migration jobs directly';
  end if;
end;
$$;

do $$
declare
  blocked boolean := false;
begin
  begin
    perform public.claim_receipt_image_migration_job(
      current_setting('security_test.job_id')::uuid,
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
      900
    );
  exception when others then
    blocked := position('leased by another worker' in sqlerrm) > 0;
  end;
  if not blocked then
    raise exception 'a second migration worker must not steal a live lease';
  end if;
end;
$$;

select public.record_receipt_image_migration_error(
  current_setting('security_test.job_id')::uuid,
  current_setting('security_test.lease_token')::uuid,
  'pending',
  'stale worker error'
);
select public.security_test_assert(
  (select status from public.receipt_image_migration_jobs where id = current_setting('security_test.job_id')::uuid) = 'copied',
  'stale error reporting must not move a copied job backwards'
);

insert into public.image_cleanup_queue (user_id, bucket_path, status) values (
  '11111111-1111-4111-8111-111111111111',
  '2026-01-02/owner.jpg',
  'pending'
);

do $$
declare
  blocked boolean := false;
begin
  begin
    update public.image_cleanup_queue
    set status = 'processing'
    where bucket_path = '2026-01-02/owner.jpg';
  exception when others then
    blocked := position('migration is in progress' in sqlerrm) > 0;
  end;
  if not blocked then
    raise exception 'cleanup worker claim was not blocked during migration';
  end if;
end;
$$;

select public.advance_receipt_image_migration_references(
  current_setting('security_test.job_id')::uuid,
  current_setting('security_test.lease_token')::uuid
);

select public.security_test_assert(
  exists (
    select 1 from public.transactions
    where user_id = '11111111-1111-4111-8111-111111111111'
      and image_url = '11111111-1111-4111-8111-111111111111/legacy-signed-url/migrated.jpg'
  ),
  'reference migration must atomically replace the signed URL'
);

delete from public.image_cleanup_queue where bucket_path = '2026-01-02/owner.jpg';
delete from storage.objects where bucket_id = 'receipt-images' and name = '2026-01-02/owner.jpg';

select public.finalize_receipt_image_migration(
  current_setting('security_test.job_id')::uuid,
  current_setting('security_test.lease_token')::uuid
);

select public.security_test_assert(
  (select status from public.receipt_image_migration_jobs where id = current_setting('security_test.job_id')::uuid) = 'done',
  'migration job must reach done only after old object deletion'
);
select public.security_test_assert(
  not exists (
    select 1 from public.receipt_image_owners
    where bucket_name = 'receipt-images' and bucket_path = '2026-01-02/owner.jpg'
  ),
  'finalization must remove stale legacy ownership'
);

reset role;

set role service_role;
select set_config(
  'security_test.ai_job_id',
  (
    select id::text
    from public.prepare_receipt_image_migration(
      '11111111-1111-4111-8111-111111111111',
      '2026-01-05/log-only.jpg',
      '11111111-1111-4111-8111-111111111111/legacy-signed-url/log-only.jpg'
    )
  ),
  false
);
select public.security_test_assert(
  exists (
    select 1 from public.receipt_image_migration_jobs
    where id = current_setting('security_test.ai_job_id')::uuid
      and user_id = '11111111-1111-4111-8111-111111111111'
      and status = 'pending'
  ),
  'AI-log-only signed URL references must be eligible for migration'
);
reset role;
delete from public.receipt_image_migration_jobs where id = current_setting('security_test.ai_job_id')::uuid;

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
set role authenticated;
select public.security_test_assert(
  public.can_access_receipt_image('11111111-1111-4111-8111-111111111111/legacy-signed-url/migrated.jpg'),
  'owner must access the migrated image'
);
reset role;

insert into public.staging_records (id, user_id, perceptual_hash) values (
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  '11111111-1111-4111-8111-111111111111',
  '0123456789abcdef'
);
insert into public.transactions (id, user_id, staging_record_id) values (
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  '11111111-1111-4111-8111-111111111111',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
);
insert into public.income_records (id, user_id, staging_record_id) values (
  'ffffffff-ffff-4fff-8fff-ffffffffffff',
  '11111111-1111-4111-8111-111111111111',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
);
select public.security_test_assert(
  (select perceptual_hash from public.transactions where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee') = '0123456789abcdef',
  'archived expense must inherit the staging perceptual hash'
);
select public.security_test_assert(
  (select perceptual_hash from public.income_records where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff') = '0123456789abcdef',
  'archived income must inherit the staging perceptual hash'
);
select public.security_test_assert(
  not has_function_privilege('authenticated', 'public.fill_finance_perceptual_hash_from_staging()', 'EXECUTE'),
  'authenticated users must not execute the trigger function directly'
);
delete from public.transactions where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
delete from public.income_records where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
delete from public.staging_records where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

select public.security_test_assert(
  has_function_privilege('authenticated', 'public.discard_staging_record(uuid,text)', 'EXECUTE'),
  'authenticated users must be able to discard their own staging records'
);
select public.security_test_assert(
  not has_function_privilege('anon', 'public.discard_staging_record(uuid,text)', 'EXECUTE'),
  'anonymous users must not discard staging records'
);

insert into storage.objects (bucket_id, name) values (
  'receipt-images',
  '11111111-1111-4111-8111-111111111111/staging-discard.jpg'
);
insert into public.staging_records (
  id,
  user_id,
  status,
  image_path,
  record_type,
  detected_domain_key
) values (
  'abababab-abab-4bab-8bab-abababababab',
  '11111111-1111-4111-8111-111111111111',
  'pending_review',
  '11111111-1111-4111-8111-111111111111/staging-discard.jpg',
  'expense',
  'expense'
);

select public.discard_staging_record(
  'abababab-abab-4bab-8bab-abababababab',
  'security_test'
);
select public.security_test_assert(
  exists (
    select 1
    from public.staging_records
    where id = 'abababab-abab-4bab-8bab-abababababab'
      and status = 'discarded'
      and image_path = '11111111-1111-4111-8111-111111111111/staging-discard.jpg'
  ),
  'discard must retain the managed image reference until Storage deletion succeeds'
);
select public.security_test_assert(
  exists (
    select 1
    from public.image_cleanup_queue
    where user_id = '11111111-1111-4111-8111-111111111111'
      and bucket_path = '11111111-1111-4111-8111-111111111111/staging-discard.jpg'
      and status = 'pending'
      and cleanup_reason = 'record_delete'
      and source_table = 'staging_records'
      and source_id = 'abababab-abab-4bab-8bab-abababababab'
  ),
  'discard must queue the original image with its staging source identity'
);

insert into public.staging_records (
  id,
  user_id,
  status,
  record_type,
  detected_domain_key,
  extracted_json,
  companion_message
) values (
  'cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd',
  '11111111-1111-4111-8111-111111111111',
  'pending_review',
  'expense',
  'expense',
  jsonb_build_object(
    'ai_feedback',
    jsonb_build_object('emotion_line', '这条反馈应被保留', 'utility_line', '可用于详情验证')
  ),
  '归档后的陪伴说明'
);
insert into public.transactions (id, user_id) values (
  'edededed-eded-4ded-8ded-edededededed',
  '11111111-1111-4111-8111-111111111111'
);
update public.staging_records
set status = 'archived',
    target_record_id = 'edededed-eded-4ded-8ded-edededededed'
where id = 'cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd';
select public.security_test_assert(
  (select ai_feedback->>'emotion_line' from public.transactions where id = 'edededed-eded-4ded-8ded-edededededed') = '这条反馈应被保留',
  'archiving must copy AI feedback into the target record'
);
select public.security_test_assert(
  (select companion_message from public.transactions where id = 'edededed-eded-4ded-8ded-edededededed') = '归档后的陪伴说明',
  'archiving must copy the companion message into the target record'
);

insert into public.staging_records (
  id,
  user_id,
  status,
  record_type,
  detected_domain_key,
  extracted_json,
  companion_message
) values (
  'acacacac-acac-4cac-8cac-acacacacacac',
  '11111111-1111-4111-8111-111111111111',
  'pending_review',
  'reading',
  'reading',
  jsonb_build_object(
    'ai_feedback',
    jsonb_build_object('emotion_line', '通用记录反馈应被保留')
  ),
  '通用记录陪伴说明'
);
insert into public.data_records (id, user_id) values (
  'dadadada-dada-4ada-8ada-dadadadadada',
  '11111111-1111-4111-8111-111111111111'
);
update public.staging_records
set status = 'archived',
    target_record_id = 'dadadada-dada-4ada-8ada-dadadadadada'
where id = 'acacacac-acac-4cac-8cac-acacacacacac';
select public.security_test_assert(
  (select payload_jsonb->'ai_feedback'->>'emotion_line' from public.data_records where id = 'dadadada-dada-4ada-8ada-dadadadadada') = '通用记录反馈应被保留',
  'archiving must copy AI feedback into a universal record'
);
select public.security_test_assert(
  (select payload_jsonb->>'companion_message' from public.data_records where id = 'dadadada-dada-4ada-8ada-dadadadadada') = '通用记录陪伴说明',
  'archiving must copy the companion message into a universal record'
);

insert into public.transactions (id, user_id) values (
  '12121212-1212-4212-8212-121212121212',
  '11111111-1111-4111-8111-111111111111'
);
insert into public.user_companion_memories (id, user_id, source_table, source_id) values (
  '13131313-1313-4313-8313-131313131313',
  '11111111-1111-4111-8111-111111111111',
  'transactions',
  '12121212-1212-4212-8212-121212121212'
);
insert into public.user_domain_profiles (id, user_id, domain_key, source_count) values (
  '14141414-1414-4414-8414-141414141414',
  '11111111-1111-4111-8111-111111111111',
  'expense',
  1
);
delete from public.transactions where id = '12121212-1212-4212-8212-121212121212';
select public.security_test_assert(
  not exists (
    select 1 from public.user_companion_memories
    where id = '13131313-1313-4313-8313-131313131313'
  ),
  'deleting a record must remove companion memory sourced only from that record'
);
select public.security_test_assert(
  not exists (
    select 1 from public.user_domain_profiles
    where id = '14141414-1414-4414-8414-141414141414'
  ),
  'deleting an expense must invalidate its cached domain profile'
);
select public.security_test_assert(
  not has_function_privilege(
    'authenticated',
    'public.invalidate_companion_context_after_record_delete()',
    'EXECUTE'
  ),
  'authenticated users must not execute the context invalidation trigger directly'
);

delete from public.transactions where id = 'edededed-eded-4ded-8ded-edededededed';
delete from public.data_records where id = 'dadadada-dada-4ada-8ada-dadadadadada';
delete from public.staging_records where id in (
  'abababab-abab-4bab-8bab-abababababab',
  'cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd',
  'acacacac-acac-4cac-8cac-acacacacacac'
);
delete from public.image_cleanup_queue
where bucket_path = '11111111-1111-4111-8111-111111111111/staging-discard.jpg';
delete from storage.objects
where bucket_id = 'receipt-images'
  and name = '11111111-1111-4111-8111-111111111111/staging-discard.jpg';

drop function public.security_test_assert(boolean, text);
