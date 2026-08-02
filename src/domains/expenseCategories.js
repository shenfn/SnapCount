export const EXPENSE_CATEGORY_DEFINITIONS = Object.freeze([
  { code: 'food', label: '餐饮', icon: '🍜', uiGroup: 'food', aliases: ['餐饮', '美食', '餐厅'] },
  { code: 'shopping', label: '购物', icon: '🛒', uiGroup: 'shopping', aliases: ['购物', '网购'] },
  { code: 'transport', label: '出行', icon: '🚗', uiGroup: 'transport', aliases: ['出行', '交通', '打车', 'transportation'] },
  { code: 'entertainment', label: '娱乐', icon: '🎮', uiGroup: 'entertainment', aliases: ['娱乐', '休闲'] },
  { code: 'life', label: '生活', icon: '🏠', uiGroup: 'life', aliases: ['生活', '日用', '缴费', 'living', 'housing', 'rent'] },
  { code: 'health', label: '健康', icon: '🏥', uiGroup: 'life', aliases: ['健康', '医疗', '药品', 'medical', 'healthcare'] },
  { code: 'education', label: '教育', icon: '📚', uiGroup: 'other', aliases: ['教育', '学习', 'learning'] },
  { code: 'other', label: '其他', icon: '📌', uiGroup: 'other', aliases: ['其他'] },
])

const CATEGORY_BY_CODE = new Map(EXPENSE_CATEGORY_DEFINITIONS.map(item => [item.code, item]))
const CATEGORY_CODE_BY_ALIAS = new Map()

for (const definition of EXPENSE_CATEGORY_DEFINITIONS) {
  CATEGORY_CODE_BY_ALIAS.set(definition.code, definition.code)
  for (const alias of definition.aliases) {
    CATEGORY_CODE_BY_ALIAS.set(String(alias).trim().toLowerCase(), definition.code)
  }
}

export const EXPENSE_CATEGORY_UI_OPTIONS = Object.freeze(
  EXPENSE_CATEGORY_DEFINITIONS.map(item => Object.freeze({
    val: item.code,
    label: `${item.icon} ${item.label}`,
  })),
)

export function normalizeExpenseCategory(value, fallback = null) {
  if (value === null || value === undefined) return fallback
  const key = String(value).trim().toLowerCase()
  if (!key) return fallback
  return CATEGORY_CODE_BY_ALIAS.get(key) ?? fallback
}

export function expenseCategoryLabel(value, fallback = '其他') {
  const code = normalizeExpenseCategory(value)
  return code ? CATEGORY_BY_CODE.get(code)?.label ?? fallback : fallback
}

export function expenseCategoryUiGroup(value, fallback = 'other') {
  const code = normalizeExpenseCategory(value)
  return code ? CATEGORY_BY_CODE.get(code)?.uiGroup ?? fallback : fallback
}
