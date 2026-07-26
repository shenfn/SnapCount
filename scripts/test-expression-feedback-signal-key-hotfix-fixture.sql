-- Test-only fixture: recreate the deployed operator-precedence bug so CI exercises
-- the forward hotfix path instead of only its already-fixed no-op path.

do $fixture$
declare
  v_signature regprocedure := to_regprocedure(
    'public.replace_expression_feedback_bundle(uuid,uuid,jsonb,jsonb)'
  );
  v_definition text;
  v_fixed constant text := $fixed$v_feedback_key || ':' || (signal.value ->> 'issue_code')$fixed$;
  v_buggy constant text := $buggy$v_feedback_key || ':' || signal.value ->> 'issue_code'$buggy$;
begin
  if v_signature is null then
    raise exception 'replace_expression_feedback_bundle is missing';
  end if;

  select pg_get_functiondef(v_signature::oid) into v_definition;
  if position(v_fixed in v_definition) = 0 then
    raise exception 'replace_expression_feedback_bundle does not contain the fixed expression';
  end if;

  execute replace(v_definition, v_fixed, v_buggy);
end;
$fixture$;
