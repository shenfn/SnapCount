const USER_CHOICES = new Set(['incorrect', 'not_helpful', 'repetitive', 'style_dislike', 'other'])

export const INTERNAL_ISSUE_CODES = new Set([
  'content_wrong_unspecified', 'direction_wrong', 'fact_wrong', 'number_wrong',
  'presentation_format_wrong', 'duplicate_decision_wrong', 'output_inconsistent',
  'reasoning_overreach', 'not_relevant', 'not_helpful', 'too_repetitive',
  'tone_mismatch', 'too_verbose', 'too_vague', 'bad_timing', 'wrong_surface',
  'too_brief', 'missing_dimensions', 'wants_temporal_context',
  'missing_context', 'should_have_asked', 'recognition_wrong', 'system_failure',
])

const PRIMARY_CHOICE_ISSUES = {
  incorrect: ['content_wrong_unspecified'],
  not_helpful: ['not_helpful'],
  repetitive: ['too_repetitive'],
  style_dislike: ['tone_mismatch'],
  other: [],
}

const LEGACY_TAG_ISSUES = {
  wrong_amount: ['number_wrong'], wrong_domain: ['recognition_wrong'],
  wrong_date: ['recognition_wrong'], wrong_category: ['recognition_wrong'],
  missing_key_field: ['recognition_wrong'],
  ai_feedback_too_generic: ['too_vague', 'not_helpful'],
  ai_feedback_too_exaggerated: ['reasoning_overreach'],
  ai_feedback_wrong_tone: ['tone_mismatch'],
  hallucination: ['fact_wrong', 'reasoning_overreach'],
  model_timeout: ['system_failure'], parse_failure: ['system_failure'], other: [],
}

const NOTE_RULES = [
  { code: 'not_helpful', pattern: /没什么用|没有什么用|没帮助|没有帮助/ },
  { code: 'not_relevant', pattern: /没什么关系|没有关系|不相关|和这笔.*无关/ },
  { code: 'too_repetitive', pattern: /每一次都|每次都|重复|厌倦|老是说/ },
  { code: 'too_vague', pattern: /没懂|不明白|什么意思|太泛|含糊|不明确/ },
  { code: 'bad_timing', pattern: /时机不对|现在不想|现在不需要|不该现在/ },
  { code: 'wrong_surface', pattern: /展示位置|不该.*弹|不该.*通知|放在周报|放到详情/ },
  { code: 'tone_mismatch', pattern: /语气|阴阳|冒犯|说教|不喜欢.*表达/ },
  { code: 'too_brief', pattern: /(?:字数?|话|内容|信息).{0,8}(?:太少|少了点|有点少|不够|太短)|(?:多说|多写|展开|详细)(?:一点|一些)?/ },
  { code: 'missing_dimensions', pattern: /其他角度|更多角度|不同角度|多个角度|多些角度|更多维度|不同维度|多个维度/ },
  { code: 'wants_temporal_context', pattern: /时间(?:角度|维度|节奏|分布)|从时间|比如时间|例如时间/ },
  { code: 'presentation_format_wrong', pattern: /百进制|单位不对|格式不对|转化成.*分钟/ },
  { code: 'number_wrong', pattern: /金额错误|数字不对|数值不对/ },
  { code: 'duplicate_decision_wrong', pattern: /去重.*不应该|不应该.*去重|误判.*重复/ },
  { code: 'output_inconsistent', pattern: /去重.*不一样|数据.*不一样|哪一个.*准/ },
  { code: 'fact_wrong', pattern: /事实错误|编造|幻觉/ },
  { code: 'direction_wrong', pattern: /方向错|看成了消费|判断错/ },
  { code: 'missing_context', pattern: /缺少.*背景|没有.*上下文|原因.*记忆|希望.*记忆/ },
  { code: 'should_have_asked', pattern: /应该.*问|先问.*用户|请求.*补充/ },
]

function required(value, name) {
  if (value === null || value === undefined || value === '') throw new Error(`Missing required feedback field: ${name}`)
  return value
}

function addAnnotation(target, issueCode, source, confidence, evidence = null) {
  if (!INTERNAL_ISSUE_CODES.has(issueCode)) throw new Error(`Invalid internal issue code: ${issueCode}`)
  const existing = target.get(issueCode)
  if (!existing || confidence > existing.confidence) target.set(issueCode, { issue_code: issueCode, source, confidence, evidence })
}

export function inferIssueAnnotations({ primaryChoice, explicitIssueCodes = [], legacyIssueTags = [], notes = '' }) {
  const annotations = new Map()
  for (const code of PRIMARY_CHOICE_ISSUES[primaryChoice] ?? []) addAnnotation(annotations, code, 'user_primary_choice', 0.6)
  for (const code of explicitIssueCodes) addAnnotation(annotations, code, 'user_explicit_detail', 1)
  for (const tag of legacyIssueTags) {
    for (const code of LEGACY_TAG_ISSUES[tag] ?? []) addAnnotation(annotations, code, 'legacy_review_tag', 0.8, tag)
  }
  for (const rule of NOTE_RULES) {
    const match = String(notes).match(rule.pattern)
    if (match) addAnnotation(annotations, rule.code, 'deterministic_note_rule', 0.7, match[0])
  }
  return [...annotations.values()]
}

export function normalizeExposureFeedback(input, context = {}) {
  const primaryChoice = required(input?.primaryChoice, 'primary_choice')
  if (!USER_CHOICES.has(primaryChoice)) throw new Error(`Invalid user feedback choice: ${primaryChoice}`)
  const legacyImport = context.legacyImport === true
  if (!legacyImport) required(context.exposureEventId, 'exposure_event_id')
  return {
    schema_version: 'exposure-feedback-v0.1',
    feedback_key: required(context.feedbackKey, 'feedback_key'),
    occurred_at: required(context.occurredAt, 'occurred_at'),
    user_id: required(context.userId, 'user_id'),
    exposure_event_id: context.exposureEventId ?? null,
    exposure_resolution: context.exposureEventId ? 'resolved' : 'legacy_unresolved',
    candidate_id: context.candidateId ?? null,
    semantic_key: context.semanticKey ?? null,
    surface: context.surface ?? null,
    visible_field_paths: context.visibleFieldPaths ?? [],
    primary_choice: primaryChoice,
    issue_annotations: inferIssueAnnotations({ primaryChoice, explicitIssueCodes: input.explicitIssueCodes, legacyIssueTags: input.legacyIssueTags, notes: input.notes }),
    free_text: String(input.notes ?? '').slice(0, 2000),
    suggested_action: String(input.suggestedAction ?? '').slice(0, 500),
    source_review_schema: context.sourceReviewSchema ?? null,
    source_review_key: context.sourceReviewKey ?? null,
    metadata: context.metadata ?? {},
  }
}

export function primaryChoiceFromLegacyReview(review) {
  const tags = new Set(review?.issue_tags ?? [])
  const notes = String(review?.notes ?? '')
  if ([...tags].some(tag => ['wrong_amount', 'wrong_domain', 'wrong_date', 'wrong_category', 'hallucination'].includes(tag))) return 'incorrect'
  if (/重复|每一次都|每次都|厌倦/.test(notes)) return 'repetitive'
  if (tags.has('ai_feedback_wrong_tone') || /语气|表达不喜欢/.test(notes)) return 'style_dislike'
  if ((review?.ratings?.feedback_quality ?? 0) <= 3 || /没什么用|没帮助|没懂|没关系/.test(notes)) return 'not_helpful'
  return 'other'
}
