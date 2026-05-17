-- ════════════════════════════════════════════════════════════════════
-- 018_wallet_domain.sql
-- 轻量钱包域：当前现金账户快照 + 花呗/白条/月付等待还款快照
-- 说明：不做专业账户流水/复式记账，只为 AI 现金流判断提供上下文。
-- ════════════════════════════════════════════════════════════════════

with wallet_domain as (
  select
    'wallet'::text as key,
    '钱包与待还'::text as name,
    '记录当前账户余额、花呗/白条/月付等待还款快照，用于现金流判断。'::text as description,
    '👛'::text as icon,
    'active'::text as status,
    true as is_system,
    '{
      "time_field": "occurred_at",
      "facts": [
        {"key": "amount", "label": "金额", "type": "number", "unit": "元", "priority": 1},
        {"key": "minimum_payment", "label": "最低还款", "type": "number", "unit": "元", "optional": true}
      ],
      "dimensions": [
        {"key": "record_kind", "label": "记录类型", "priority": 1,
         "options": [
           {"value": "cash_snapshot", "label": "现金/账户余额"},
           {"value": "liability_snapshot", "label": "待还款"}
         ]},
        {"key": "account_name", "label": "账户/平台", "priority": 2},
        {"key": "account_type", "label": "账户类型", "priority": 3},
        {"key": "due_date", "label": "还款日", "type": "date", "priority": 4, "optional": true},
        {"key": "bill_day", "label": "每月还款日", "type": "number", "priority": 5, "optional": true},
        {"key": "status", "label": "状态", "priority": 6, "optional": true}
      ],
      "notes": {
        "scope": "Phase 1 只记录快照，不自动联动收入/支出，不处理转账和复式记账。"
      }
    }'::jsonb as schema_json,
    '{
      "primary_fact": "amount",
      "primary_dimension": "account_name",
      "title_field": "account_name",
      "summary_fields": ["record_kind", "account_name", "amount", "due_date"],
      "list_view": "wallet_snapshot_list"
    }'::jsonb as display_json,
    '{
      "keywords": ["花呗", "白条", "京东白条", "抖音月付", "月付", "待还", "还款日", "本月应还", "剩余应还", "账户余额", "可用余额", "银行卡余额", "零钱", "余额宝"],
      "trigger_apps": ["支付宝", "京东", "抖音", "微信", "银行"],
      "confidence_threshold": 0.74
    }'::jsonb as routing_json,
    '{
      "record_kinds": ["cash_snapshot", "liability_snapshot"],
      "providers": ["花呗", "京东白条", "抖音月付", "信用卡", "微信", "支付宝", "银行卡", "现金", "其他"]
    }'::jsonb as extraction_json,
    '1.0'::text as version,
    'private'::text as privacy_level
),
updated as (
  update public.data_domains d
  set
    name = w.name,
    description = w.description,
    icon = w.icon,
    status = w.status,
    is_system = w.is_system,
    schema_json = w.schema_json,
    display_json = w.display_json,
    routing_json = w.routing_json,
    extraction_json = w.extraction_json,
    version = w.version,
    privacy_level = w.privacy_level,
    updated_at = now()
  from wallet_domain w
  where d.key = w.key and d.user_id is null
  returning d.id
)
insert into public.data_domains (
  key, name, description, icon, status, is_system,
  schema_json, display_json, routing_json, extraction_json, version, privacy_level
)
select
  key, name, description, icon, status, is_system,
  schema_json, display_json, routing_json, extraction_json, version, privacy_level
from wallet_domain
where not exists (select 1 from updated);
