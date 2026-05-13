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
      primaryLabel: '运动时长（分钟）',
      primaryKey: 'duration_minutes',
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
        { model: 'primaryValue', label: '运动时长（分钟）', type: 'number', placeholder: '0', min: '0.01', step: '0.01', required: true },
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
      primaryLabel: '睡眠时长（小时）',
      primaryKey: 'sleep_hours',
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
        { model: 'primaryValue', label: '睡眠时长（小时）', type: 'number', placeholder: '0', min: '0.01', step: '0.01', required: true },
        { model: 'date', label: '日期', type: 'date', required: true },
        { model: 'time', label: '具体时刻（可选）', type: 'time' },
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
      primaryLabel: '阅读时长（分钟）',
      primaryKey: 'reading_minutes',
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
        { model: 'primaryValue', label: '阅读时长（分钟）', type: 'number', placeholder: '0', min: '0.01', step: '0.01', required: true },
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
