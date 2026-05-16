-- ════════════════════════════════════════════════════════════════════
-- Phase 1：补全 expense / income 域的 schema_json 协议
-- 目的：把老格式（target_table + fields 扁平描述）升级为新格式（facts + dimensions）
-- 与 sport / sleep / reading / food 对齐，使前端可以统一按协议消费
-- 注意：本 migration 只更新 data_domains 行，不改任何业务表结构
--      纯元数据补全，零业务影响；前端在 Phase 3 才会真正消费这些字段
-- ════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────────
-- expense（消费）
-- facts: amount（主指标）
-- dimensions: category / platform / payment_method / merchant / transport_type
-- ────────────────────────────────────────────────────────────────────
update public.data_domains
set
  schema_json = '{
    "time_field": "occurred_at",
    "facts": [
      {"key": "amount", "label": "金额", "type": "number", "unit": "元", "priority": 1}
    ],
    "dimensions": [
      {"key": "category", "label": "分类", "priority": 1},
      {"key": "platform", "label": "消费平台", "priority": 2},
      {"key": "payment_method", "label": "支付方式", "priority": 3},
      {"key": "merchant_name", "label": "商家", "priority": 4},
      {"key": "transport_type", "label": "交通类型", "priority": 5, "optional": true}
    ],
    "storage": {
      "target_table": "transactions",
      "kind": "specialized"
    },
    "required_fields": ["amount", "platform", "category", "payment_method"]
  }'::jsonb,
  display_json = '{
    "primary_fact": "amount",
    "primary_dimension": "category",
    "secondary_dimensions": ["platform", "payment_method"],
    "title_field": "merchant_name",
    "summary_fields": ["merchant_name", "category", "platform"],
    "list_view": "transaction_list"
  }'::jsonb,
  updated_at = now()
where key = 'expense';

-- ────────────────────────────────────────────────────────────────────
-- income（收入）
-- facts: amount（主指标）
-- dimensions: category / source_name / is_passive / frequency
-- 说明：is_passive / frequency 当前 income_records 表无字段，先在 schema 声明
--      未来抽取链路或手动录入可以写入 payload_jsonb（如果需要的话）
-- ────────────────────────────────────────────────────────────────────
update public.data_domains
set
  schema_json = '{
    "time_field": "income_date",
    "facts": [
      {"key": "amount", "label": "金额", "type": "number", "unit": "元", "priority": 1}
    ],
    "dimensions": [
      {"key": "category", "label": "类别", "priority": 1},
      {"key": "source_name", "label": "来源", "priority": 2},
      {"key": "is_passive", "label": "被动收入", "type": "boolean", "priority": 3, "optional": true},
      {"key": "frequency", "label": "频率", "priority": 4, "optional": true,
       "options": [
         {"value": "one_time", "label": "一次性"},
         {"value": "recurring", "label": "周期性"}
       ]}
    ],
    "storage": {
      "target_table": "income_records",
      "kind": "specialized"
    },
    "required_fields": ["amount", "source_name", "income_date"]
  }'::jsonb,
  display_json = '{
    "primary_fact": "amount",
    "primary_dimension": "category",
    "secondary_dimensions": ["source_name"],
    "title_field": "source_name",
    "summary_fields": ["source_name", "category"],
    "list_view": "income_list"
  }'::jsonb,
  updated_at = now()
where key = 'income';

-- ────────────────────────────────────────────────────────────────────
-- 完成性校验：确保 6 个系统域 schema_json 都包含 facts 数组
-- 如果有遗漏，下面查询会返回行；线上手动检查即可
-- ────────────────────────────────────────────────────────────────────
-- select key, name,
--   (schema_json ? 'facts')      as has_facts,
--   (schema_json ? 'dimensions') as has_dimensions,
--   (schema_json ? 'time_field') as has_time_field
-- from public.data_domains
-- where is_system = true
-- order by key;
