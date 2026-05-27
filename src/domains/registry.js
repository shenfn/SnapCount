const SYSTEM_DOMAIN_DEFINITIONS = [
  {
    id: 'expense',
    name: '消费记账',
    shortName: '消费',
    icon: '💸',
    tone: 'expense',
    color: '#C2410C',
    description: '识别消费截图、账单详情和手动支出记录。',
    kind: 'system',
    storage: {
      recordKind: 'expense',
      sourceTable: 'transactions',
    },
  },
  {
    id: 'income',
    name: '收入记录',
    shortName: '收入',
    icon: '💰',
    tone: 'income',
    color: '#1565C0',
    description: '记录工资、转账收款、报销和其他收入来源。',
    kind: 'system',
    storage: {
      recordKind: 'income',
      sourceTable: 'income_records',
    },
  },
  {
    id: 'sport',
    name: '运动记录',
    shortName: '运动',
    icon: '🏃',
    tone: 'sport',
    color: '#B45309',
    description: '后续承接华为健康、Keep 等运动截图。',
    kind: 'system',
    storage: {
      recordKind: 'universal',
      sourceTable: 'data_records',
    },
    universalMeta: {
      title: '添加运动',
      editTitle: '编辑运动',
      primaryLabel: '运动时长',
      primaryKey: 'duration_minutes',
      primaryUnit: 'duration',
      dimensionLabel: '运动类型',
      dimensionKey: 'sport_type',
      placeholder: '如：跑步、步行、力量训练',
      defaultTitle: '运动记录',
      reportMeta: {
        icon: '动',
        primaryLabel: '运动时长',
        totalLabel: '累计运动',
        unit: '分钟',
        dimensionLabel: '主要类型',
      },
      formFields: [
        { model: 'title', label: '标题（可选）', type: 'text', placeholder: '不填则使用下面的名称', maxlength: 50 },
        { model: 'dimension', label: '运动类型', type: 'text', placeholder: '如：跑步、步行、力量训练', maxlength: 50, required: true },
        { model: 'primaryValue', label: '运动时长', type: 'number', input: 'duration', placeholder: '0', min: '0', step: '1', required: true },
        { model: 'date', label: '日期', type: 'date', required: true },
        { model: 'time', label: '具体时刻（可选）', type: 'time' },
        { model: 'note', label: '备注（可选）', type: 'text', placeholder: '补充说明…', maxlength: 100 },
      ],
    },
  },
  {
    id: 'sleep',
    name: '睡眠记录',
    shortName: '睡眠',
    icon: '🌙',
    tone: 'sleep',
    color: '#4338CA',
    description: '后续承接睡眠追踪截图和睡眠日志。',
    kind: 'system',
    storage: {
      recordKind: 'universal',
      sourceTable: 'data_records',
    },
    universalMeta: {
      title: '添加睡眠',
      editTitle: '编辑睡眠',
      primaryLabel: '睡眠时长',
      primaryKey: 'sleep_minutes',
      primaryUnit: 'duration',
      dimensionLabel: '质量等级',
      dimensionKey: 'quality_level',
      placeholder: '如：良好、一般、深睡不足',
      defaultTitle: '睡眠记录',
      defaultDimension: '良好',
      reportMeta: {
        icon: '眠',
        primaryLabel: '睡眠时长',
        totalLabel: '累计睡眠',
        unit: '小时',
        dimensionLabel: '主要质量',
      },
      formFields: [
        { model: 'title', label: '标题（可选）', type: 'text', placeholder: '不填则使用下面的名称', maxlength: 50 },
        { model: 'dimension', label: '质量等级', type: 'text', placeholder: '如：良好、一般、深睡不足', maxlength: 50, required: true, defaultValue: '良好' },
        { model: 'primaryValue', label: '睡眠时长', type: 'number', input: 'duration', placeholder: '0', min: '0', step: '1', required: true },
        { model: 'date', label: '起床日期', type: 'date', required: true },
        { model: 'sleepStartTime', label: '入睡时间（可选）', type: 'time' },
        { model: 'wakeTime', label: '起床时间（可选）', type: 'time' },
        { model: 'note', label: '备注（可选）', type: 'text', placeholder: '补充说明…', maxlength: 100 },
      ],
    },
  },
  {
    id: 'reading',
    name: '阅读记录',
    shortName: '阅读',
    icon: '📚',
    tone: 'reading',
    color: '#0369A1',
    description: '后续承接阅读时长、页数和书籍进度记录。',
    kind: 'system',
    storage: {
      recordKind: 'universal',
      sourceTable: 'data_records',
    },
    universalMeta: {
      title: '添加阅读',
      editTitle: '编辑阅读',
      primaryLabel: '阅读时长',
      primaryKey: 'reading_minutes',
      primaryUnit: 'duration',
      dimensionLabel: '书名',
      dimensionKey: 'book_name',
      placeholder: '如：原则、微信读书',
      defaultTitle: '阅读记录',
      reportMeta: {
        icon: '读',
        primaryLabel: '阅读时长',
        totalLabel: '累计阅读',
        unit: '分钟',
        dimensionLabel: '主要书籍',
      },
      formFields: [
        { model: 'title', label: '标题（可选）', type: 'text', placeholder: '不填则使用下面的名称', maxlength: 50 },
        { model: 'dimension', label: '书名', type: 'text', placeholder: '如：原则、微信读书', maxlength: 50, required: true },
        { model: 'primaryValue', label: '阅读时长', type: 'number', input: 'duration', placeholder: '0', min: '0', step: '1', required: true },
        { model: 'date', label: '日期', type: 'date', required: true },
        { model: 'time', label: '具体时刻（可选）', type: 'time' },
        { model: 'note', label: '备注（可选）', type: 'text', placeholder: '补充说明…', maxlength: 100 },
      ],
    },
  },
  {
    id: 'food',
    name: '饮食记录',
    shortName: '饮食',
    icon: '🍱',
    tone: 'food',
    color: '#EA580C',
    description: '拍照估算餐盘热量与三大营养素（数值为 AI 估算）。',
    kind: 'system',
    storage: {
      recordKind: 'universal',
      sourceTable: 'data_records',
    },
    universalMeta: {
      title: '添加饮食',
      editTitle: '编辑饮食',
      primaryLabel: '总热量（千卡）',
      primaryKey: 'total_calorie_kcal',
      dimensionLabel: '餐次',
      dimensionKey: 'meal_type',
      placeholder: '如：午餐、加餐',
      defaultTitle: '饮食记录',
      reportMeta: {
        icon: '餐',
        primaryLabel: '总热量',
        totalLabel: '累计热量',
        unit: '千卡',
        dimensionLabel: '餐次分布',
      },
      formFields: [
        { model: 'title', label: '标题（可选）', type: 'text', placeholder: '不填则使用下面的名称', maxlength: 50 },
        { model: 'dimension', label: '餐次', type: 'text', placeholder: '如：午餐、加餐', maxlength: 50, required: true },
        { model: 'primaryValue', label: '总热量（千卡）', type: 'number', placeholder: '0', min: '0.01', step: '0.01', required: true },
        { model: 'date', label: '日期', type: 'date', required: true },
        { model: 'time', label: '具体时刻（可选）', type: 'time' },
        { model: 'note', label: '备注（可选）', type: 'text', placeholder: '补充说明…', maxlength: 100 },
      ],
    },
  },
  {
    id: 'wallet',
    name: '钱包与待还',
    shortName: '钱包',
    icon: '👛',
    tone: 'wallet',
    color: '#7C3AED',
    description: '记录当前账户余额、花呗/白条/月付等待还款快照，用于现金流判断。',
    kind: 'system',
    storage: {
      recordKind: 'universal',
      sourceTable: 'data_records',
    },
    universalMeta: {
      title: '添加钱包快照',
      editTitle: '编辑钱包快照',
      primaryLabel: '金额',
      primaryKey: 'amount',
      primaryUnit: 'currency',
      dimensionLabel: '账户/平台',
      dimensionKey: 'account_name',
      placeholder: '如：微信余额、招商银行卡、花呗、京东白条',
      defaultTitle: '钱包快照',
      defaultDimension: '微信余额',
      reportMeta: {
        icon: '钱',
        primaryLabel: '金额',
        totalLabel: '钱包快照',
        unit: '元',
        dimensionLabel: '账户/平台',
      },
      formFields: [
        { model: 'title', label: '标题（可选）', type: 'text', placeholder: '不填则使用账户/平台名', maxlength: 50 },
        { model: 'recordKind', label: '记录类型', type: 'text', placeholder: 'cash_snapshot 或 liability_snapshot', maxlength: 40, required: true, defaultValue: 'cash_snapshot' },
        { model: 'dimension', label: '账户/平台', type: 'text', placeholder: '如：微信余额、花呗、京东白条、抖音月付', maxlength: 50, required: true, defaultValue: '微信余额' },
        { model: 'accountType', label: '账户类型', type: 'text', placeholder: 'cash / bank_card / wechat / alipay / huabei / jd_baitiao / douyin_monthly / credit_card / other', maxlength: 40, required: true, defaultValue: 'wechat' },
        { model: 'primaryValue', label: '金额（元）', type: 'number', placeholder: '0.00', min: '0.01', step: '0.01', required: true },
        { model: 'dueDate', label: '还款日（待还款可选）', type: 'date', allowFuture: true },
        { model: 'billDay', label: '每月还款日（可选）', type: 'number', placeholder: '如：10', min: '1', max: '31', step: '1' },
        { model: 'date', label: '快照日期', type: 'date', required: true },
        { model: 'time', label: '具体时刻（可选）', type: 'time' },
        { model: 'note', label: '备注（可选）', type: 'text', placeholder: '补充账单周期、最低还款等…', maxlength: 120 },
      ],
    },
  },
]

const DOMAIN_DEFINITION_MAP = Object.fromEntries(
  SYSTEM_DOMAIN_DEFINITIONS.map(domain => [domain.id, domain])
)

export function getSystemDomainDefinitions() {
  return SYSTEM_DOMAIN_DEFINITIONS
}

export function getSystemDomainDefinition(domainId) {
  return DOMAIN_DEFINITION_MAP[domainId] || SYSTEM_DOMAIN_DEFINITIONS[0]
}

export function getSystemDomainLabel(domainId, fallback = '未知域') {
  return DOMAIN_DEFINITION_MAP[domainId]?.name || fallback
}

export function getUniversalDomainMeta(domainKey = 'sport') {
  return getSystemDomainDefinition(domainKey).universalMeta || getSystemDomainDefinition('sport').universalMeta
}

export function getUniversalReportMeta(domainKey = 'sport') {
  return getUniversalDomainMeta(domainKey).reportMeta || getUniversalDomainMeta('sport').reportMeta
}

export function getReportDomainDefinitions() {
  return SYSTEM_DOMAIN_DEFINITIONS.map(domain => ({
    id: domain.id,
    name: domain.shortName,
    icon: domain.icon,
    color: domain.color,
  }))
}

export function getArchiveTargetDomainDefinitions() {
  return SYSTEM_DOMAIN_DEFINITIONS
}

// ════════════════════════════════════════════════════════════════════
// 协议化重构 Phase 1：新协议层（沉默存在，Phase 3 才会被消费）
// ────────────────────────────────────────────────────────────────────
// 设计原则：
// 1. 单一事实源 = data_domains.schema_json / display_json
// 2. 前端 registry 只持有"视觉样式"，schema/display 从 DB hydrate
// 3. DB 不可达时回退到 BUILTIN_SCHEMAS（兜底），不白屏
// 4. 旧 API 完全保留，新 API 并行存在
// ════════════════════════════════════════════════════════════════════

// 视觉样式：唯一应该写在前端的域信息
const VISUAL_REGISTRY = {
  expense: { color: '#C2410C', icon: '💸', tone: 'expense', shortName: '消费', name: '消费记账', description: '识别消费截图、账单详情和手动支出记录。' },
  income:  { color: '#1565C0', icon: '💰', tone: 'income',  shortName: '收入', name: '收入记录', description: '记录工资、转账收款、报销和其他收入来源。' },
  sport:   { color: '#B45309', icon: '🏃', tone: 'sport',   shortName: '运动', name: '运动记录', description: '后续承接华为健康、Keep 等运动截图。' },
  sleep:   { color: '#4338CA', icon: '🌙', tone: 'sleep',   shortName: '睡眠', name: '睡眠记录', description: '后续承接睡眠追踪截图和睡眠日志。' },
  reading: { color: '#0369A1', icon: '📚', tone: 'reading', shortName: '阅读', name: '阅读记录', description: '后续承接阅读时长、页数和书籍进度记录。' },
  food:    { color: '#EA580C', icon: '🍱', tone: 'food',    shortName: '饮食', name: '饮食记录', description: '拍照估算餐盘热量与三大营养素（数值为 AI 估算）。' },
  wallet:  { color: '#7C3AED', icon: '👛', tone: 'wallet',  shortName: '钱包', name: '钱包与待还', description: '记录当前账户余额、花呗/白条/月付等待还款快照。' },
}

// 内置兜底 schema：DB 不可达时使用，确保应用永不白屏
// 只声明最小可用结构，DB 同步成功后会被 hydrate 覆盖
const BUILTIN_SCHEMAS = {
  expense: {
    time_field: 'occurred_at',
    facts: [{ key: 'amount', label: '金额', type: 'number', unit: '元', priority: 1 }],
    dimensions: [
      { key: 'category', label: '分类', priority: 1 },
      { key: 'platform', label: '消费平台', priority: 2 },
      { key: 'payment_method', label: '支付方式', priority: 3 },
    ],
    storage: { target_table: 'transactions', kind: 'specialized' },
  },
  income: {
    time_field: 'income_date',
    facts: [{ key: 'amount', label: '金额', type: 'number', unit: '元', priority: 1 }],
    dimensions: [
      { key: 'category', label: '类别', priority: 1 },
      { key: 'source_name', label: '来源', priority: 2 },
    ],
    storage: { target_table: 'income_records', kind: 'specialized' },
  },
  sport: {
    time_field: 'occurred_at',
    facts: [
      { key: 'duration_minutes', label: '运动时长', type: 'number', unit: '分钟' },
      { key: 'distance_km', label: '距离', type: 'number', unit: '公里' },
      { key: 'calories', label: '消耗', type: 'number', unit: '千卡' },
    ],
    dimensions: [
      { key: 'sport_type', label: '运动类型' },
      { key: 'source_app', label: '来源' },
    ],
  },
  sleep: {
    time_field: 'occurred_at',
    facts: [
      { key: 'sleep_minutes', label: '睡眠时长', type: 'number', unit: '分钟', input: 'duration' },
      { key: 'quality_score', label: '睡眠评分', type: 'number', unit: '分' },
    ],
    dimensions: [
      { key: 'quality_level', label: '质量等级' },
      { key: 'source_app', label: '来源' },
    ],
  },
  reading: {
    time_field: 'occurred_at',
    facts: [
      { key: 'reading_minutes', label: '阅读时长', type: 'number', unit: '分钟' },
      { key: 'pages', label: '页数', type: 'number', unit: '页' },
    ],
    dimensions: [
      { key: 'book_name', label: '书名' },
      { key: 'source_app', label: '来源' },
    ],
  },
  food: {
    time_field: 'occurred_at',
    facts: [
      { key: 'total_calorie_kcal', label: '总热量', type: 'number', unit: '千卡' },
    ],
    dimensions: [
      { key: 'meal_type', label: '餐次' },
      { key: 'source_app', label: '来源' },
    ],
  },
  wallet: {
    time_field: 'occurred_at',
    facts: [
      { key: 'amount', label: '金额', type: 'number', unit: '元', priority: 1 },
      { key: 'minimum_payment', label: '最低还款', type: 'number', unit: '元', optional: true },
    ],
    dimensions: [
      { key: 'record_kind', label: '记录类型', priority: 1 },
      { key: 'account_name', label: '账户/平台', priority: 2 },
      { key: 'account_type', label: '账户类型', priority: 3 },
      { key: 'due_date', label: '还款日', priority: 4, optional: true },
      { key: 'bill_day', label: '每月还款日', priority: 5, optional: true },
    ],
  },
}

const BUILTIN_DISPLAYS = {
  expense: { primary_fact: 'amount', primary_dimension: 'category', title_field: 'merchant_name' },
  income:  { primary_fact: 'amount', primary_dimension: 'category', title_field: 'source_name' },
  sport:   { primary_fact: 'duration_minutes', primary_dimension: 'sport_type', title_field: 'sport_type' },
  sleep:   { primary_fact: 'sleep_minutes', primary_dimension: 'quality_level', title_field: 'quality_level' },
  reading: { primary_fact: 'reading_minutes', primary_dimension: 'book_name', title_field: 'book_name' },
  food:    { primary_fact: 'total_calorie_kcal', primary_dimension: 'meal_type', title_field: 'title' },
  wallet:  { primary_fact: 'amount', primary_dimension: 'account_name', title_field: 'account_name' },
}

// 运行时态：DB hydrate 后存放到这里
// 默认初始化为 BUILTIN_*（兜底），hydrate 后被 DB 数据覆盖
const runtimeState = {
  hydrated: false,
  hydratedAt: null,
  schemas: { ...BUILTIN_SCHEMAS },
  displays: { ...BUILTIN_DISPLAYS },
}

/**
 * 把从 DB 拉到的 data_domains 行合并进运行时 registry
 * @param {Array} dbDomains 形如 [{ key, schema_json, display_json, ... }]
 */
export function hydrateDomainRegistry(dbDomains) {
  if (!Array.isArray(dbDomains)) return

  for (const row of dbDomains) {
    if (!row || !row.key) continue
    if (!VISUAL_REGISTRY[row.key]) continue // 只接受已知的系统域，未知域忽略

    const schema = row.schema_json || row.schemaJson
    const display = row.display_json || row.displayJson

    if (schema && typeof schema === 'object' && Array.isArray(schema.facts)) {
      runtimeState.schemas[row.key] = schema
    }
    if (display && typeof display === 'object') {
      runtimeState.displays[row.key] = display
    }
  }

  runtimeState.hydrated = true
  runtimeState.hydratedAt = new Date().toISOString()
}

/** 取域的视觉样式（颜色/icon/简称等）—— 永远本地，零网络依赖 */
export function getDomainVisual(domainId) {
  return VISUAL_REGISTRY[domainId] || VISUAL_REGISTRY.sport
}

/** 取域的 schema（facts/dimensions/time_field）—— DB hydrate 后是 DB 值，否则是兜底 */
export function getDomainSchema(domainId) {
  return runtimeState.schemas[domainId] || BUILTIN_SCHEMAS[domainId] || { facts: [], dimensions: [] }
}

/** 取域的 display（primary_fact/primary_dimension/title_field）—— 同上 */
export function getDomainDisplay(domainId) {
  return runtimeState.displays[domainId] || BUILTIN_DISPLAYS[domainId] || {}
}

/** 调试用：返回当前 registry 是否已 hydrate 以及最近一次 hydrate 时间 */
export function getDomainRegistryStatus() {
  return {
    hydrated: runtimeState.hydrated,
    hydratedAt: runtimeState.hydratedAt,
    knownDomains: Object.keys(VISUAL_REGISTRY),
    schemaSnapshot: runtimeState.schemas,
    displaySnapshot: runtimeState.displays,
  }
}

/** 列出所有视觉注册的域 id（含 system + 未来扩展） */
export function getRegisteredDomainIds() {
  return Object.keys(VISUAL_REGISTRY)
}
