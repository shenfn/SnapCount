-- Fix the deployed feedback bundle function without duplicating its full body.
-- The original expression was parsed as `(text || jsonb) ->> key` at runtime.

do $migration$
declare
  v_signature regprocedure := to_regprocedure(
    'public.replace_expression_feedback_bundle(uuid,uuid,jsonb,jsonb)'
  );
  v_definition text;
  v_buggy constant text := $buggy$v_feedback_key || ':' || signal.value ->> 'issue_code'$buggy$;
  v_fixed constant text := $fixed$v_feedback_key || ':' || (signal.value ->> 'issue_code')$fixed$;
begin
  if v_signature is null then
    raise exception 'replace_expression_feedback_bundle is missing';
  end if;

  select pg_get_functiondef(v_signature::oid) into v_definition;
  if position(v_fixed in v_definition) > 0 then
    return;
  end if;
  if position(v_buggy in v_definition) = 0 then
    raise exception 'replace_expression_feedback_bundle does not contain the expected expression';
  end if;

  execute replace(v_definition, v_buggy, v_fixed);
end;
$migration$;

revoke all on function public.replace_expression_feedback_bundle(uuid, uuid, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.replace_expression_feedback_bundle(uuid, uuid, jsonb, jsonb)
  to service_role;
