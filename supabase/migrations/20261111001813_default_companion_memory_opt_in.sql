-- Companion memory is an explicit opt-in for newly created accounts.
-- Existing user choices remain untouched.
alter table public.user_configs
  alter column companion_memory_enabled set default false;
