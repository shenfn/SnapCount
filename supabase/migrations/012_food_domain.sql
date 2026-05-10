-- ════════════════════════════════════════════════════════════════════
-- 阶段 1C：饮食热量域（food）
-- 目的：扩展第一个非截图来源（拍照）数据域，承接餐盘照片的热量估算
-- ════════════════════════════════════════════════════════════════════

insert into public.data_domains (
  key, name, description, icon, status, is_system,
  schema_json, display_json, routing_json, extraction_json, version, privacy_level
) values
(
  'food',
  '饮食记录',
  '承接餐盘拍照与外卖照片，估算每餐热量与三大营养素摄入。',
  '🍱',
  'active',
  true,
  '{
    "time_field": "occurred_at",
    "facts": [
      {"key": "total_calorie_kcal", "label": "总热量", "type": "number", "unit": "千卡"},
      {"key": "dishes_count", "label": "菜品数", "type": "number", "unit": "道", "computed": "dishes.length"}
    ],
    "dimensions": [
      {"key": "meal_type", "label": "餐次", "options": [
        {"value": "breakfast", "label": "早餐"},
        {"value": "lunch", "label": "午餐"},
        {"value": "dinner", "label": "晚餐"},
        {"value": "snack", "label": "加餐"}
      ]},
      {"key": "source_app", "label": "来源"}
    ],
    "nested": {
      "key": "dishes",
      "label": "菜品",
      "fields": [
        {"key": "name", "label": "名称", "type": "string", "required": true},
        {"key": "estimated_grams", "label": "估算克重", "type": "number", "unit": "克"},
        {"key": "calorie_kcal", "label": "热量", "type": "number", "unit": "千卡"},
        {"key": "protein_g", "label": "蛋白质", "type": "number", "unit": "克"},
        {"key": "carb_g", "label": "碳水", "type": "number", "unit": "克"},
        {"key": "fat_g", "label": "脂肪", "type": "number", "unit": "克"}
      ]
    },
    "notes": {
      "is_estimated": "热量为基于视觉的近似估算，误差通常 ±20-40%，建议用户校准后纳入个人趋势分析"
    }
  }'::jsonb,
  '{
    "primary_fact": "total_calorie_kcal",
    "primary_dimension": "meal_type",
    "title_field": "title",
    "summary_fields": ["meal_type", "total_calorie_kcal", "dishes"],
    "show_estimated_badge": true
  }'::jsonb,
  '{"keywords": ["千卡", "kcal", "营养", "蛋白质", "碳水", "脂肪", "热量"], "confidence_threshold": 0.8}'::jsonb,
  '{}'::jsonb,
  '1.0',
  'private'
)
on conflict (key, user_id) do update set
  name = excluded.name,
  description = excluded.description,
  icon = excluded.icon,
  status = excluded.status,
  is_system = excluded.is_system,
  schema_json = excluded.schema_json,
  display_json = excluded.display_json,
  routing_json = excluded.routing_json,
  extraction_json = excluded.extraction_json,
  version = excluded.version,
  privacy_level = excluded.privacy_level;
