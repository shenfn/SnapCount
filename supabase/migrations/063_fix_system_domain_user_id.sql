-- ════════════════════════════════════════════════════════════════════
-- 修正系统域 user_id 错误绑定
--
-- 背景：
--   系统域（is_system=true）设计上应为共享域，user_id 必须为 null。
--   但 expense/income/sport/sleep/reading 五个系统域的 user_id
--   被错误绑定到了种子用户 602a1568，导致：
--   1. Edge Function 域查询时可能匹配到错误用户的域
--   2. 其他用户的数据无法正确关联到这些系统域
--
-- 本迁移：
--   把所有 is_system=true 且 user_id IS NOT NULL 的系统域 user_id 清回 null。
--
-- 影响范围：
--   - data_domains 表 5 行的 user_id 从 602a1568 改为 null
--   - data_records 里的 domain_id 不变（仍指向同一个域 ID）
--   - RLS 策略不受影响（is_system=true 的域本来就对所有人可读）
--
-- 回滚 SQL：
--   UPDATE public.data_domains
--      SET user_id = '602a1568-a3dd-4f53-86c1-84be44f1b159'
--    WHERE is_system = true
--      AND key IN ('expense', 'income', 'sport', 'sleep', 'reading');
-- ════════════════════════════════════════════════════════════════════

-- 1. 修正系统域 user_id：is_system=true 的域应为共享域，user_id 必须为 null
UPDATE public.data_domains
   SET user_id = NULL,
       updated_at = now()
 WHERE is_system = true
   AND user_id IS NOT NULL;

-- 2. 验证：修复后应该返回 0 行
-- SELECT id, key, name, user_id, is_system
--   FROM public.data_domains
--  WHERE is_system = true AND user_id IS NOT NULL;
