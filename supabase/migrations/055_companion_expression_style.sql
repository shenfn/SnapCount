-- Companion reply expression style: plain text, emoji, or kaomoji.

alter table public.user_configs
  add column if not exists companion_expression_style text not null default 'plain'
    check (companion_expression_style in ('plain','emoji','kaomoji'));

comment on column public.user_configs.companion_expression_style is
  'Visual expression style for screenshot companion copy: plain, emoji, or kaomoji.';
