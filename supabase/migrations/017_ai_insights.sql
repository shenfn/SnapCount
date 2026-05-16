-- ════════════════════════════════════════════════════════════════════
-- 017_ai_insights.sql
-- AI 洞察缓存表：供 PageInsights 调用 generate-insights Edge Function 写入
-- ────────────────────────────────────────────────────────────────────
-- 缓存策略：
--   - data_hash 由 Edge Function 计算，包含 days_range + 日聚合摘要
--   - 相同 hash 在 TTL 内复用，不重复调 AI（节省 token）
--   - 用户手动「刷新」可强制重新生成
-- ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_insights (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  user_id uuid,
  generated_at timestamptz NOT NULL DEFAULT now(),
  days_range int NOT NULL,
  maturity_stage text NOT NULL,
  active_days int NOT NULL,
  data_hash text NOT NULL,
  content_md text NOT NULL,
  payload_jsonb jsonb NOT NULL DEFAULT '{}'::jsonb,
  model text,
  prompt_version text,
  token_usage jsonb,
  status text NOT NULL DEFAULT 'success' CHECK (status IN ('success', 'error', 'pending')),
  error_message text
);

CREATE INDEX IF NOT EXISTS idx_ai_insights_user_range ON public.ai_insights(user_id, days_range, generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_insights_hash ON public.ai_insights(data_hash);

ALTER TABLE public.ai_insights ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_insights_read_all ON public.ai_insights FOR SELECT USING (true);
CREATE POLICY ai_insights_write_all ON public.ai_insights FOR INSERT WITH CHECK (true);
CREATE POLICY ai_insights_update_all ON public.ai_insights FOR UPDATE USING (true);
CREATE POLICY ai_insights_delete_all ON public.ai_insights FOR DELETE USING (true);

COMMENT ON TABLE public.ai_insights IS 'PageInsights AI 洞察缓存：相同 data_hash 在 TTL 内不重复调用 AI';
COMMENT ON COLUMN public.ai_insights.data_hash IS '输入数据指纹，由 Edge Function 计算（含 days_range + 各域日聚合摘要）';
COMMENT ON COLUMN public.ai_insights.maturity_stage IS 'seed/sprout/growing/mature/rich';
COMMENT ON COLUMN public.ai_insights.content_md IS 'AI 输出的 markdown 正文';
COMMENT ON COLUMN public.ai_insights.payload_jsonb IS '结构化字段：{ headline, observations[], suggestions[], encouragement }';
