import {
  candidate,
  formatLocalTime,
  median,
  num,
  payloadValue,
  round,
  textValue,
} from './generic-domain-shared.mjs'

function dishItems(record) {
  const dishes = payloadValue(record, 'dishes')
  return Array.isArray(dishes) ? dishes.filter(item => item && typeof item === 'object') : []
}

function dishNames(record) {
  return dishItems(record).map(item => textValue(item.name)).filter(Boolean)
}

function numericDishTotal(record, key) {
  const values = dishItems(record).map(item => num(item[key]))
  if (!values.length || values.some(value => value === null)) return null
  return round(values.reduce((sum, value) => sum + value, 0))
}

function mealTypeLabel(value) {
  return ({ breakfast: '早餐', lunch: '午餐', dinner: '晚餐', snack: '加餐' })[value]
    ?? value
    ?? '未标注餐次'
}

export function generateFoodCandidates(current, prior, domainProfile = {}) {
  const mealType = textValue(payloadValue(current, 'meal_type'))
  const names = dishNames(current)
  const currentKcal = num(payloadValue(current, 'total_calorie_kcal'))
  const output = []

  if (mealType || names.length || current.occurred_at) {
    const time = formatLocalTime(current.occurred_at)
    output.push(candidate({
      id: `fact:food:context:${current.id}`,
      domainKey: 'food',
      semanticKey: 'food_record_context',
      subtype: 'observed',
      dimension: 'record_context',
      value: {
        domain_key: 'food',
        occurred_at: current.occurred_at,
        meal_type: mealType,
        dish_names: names,
        dish_count: names.length,
      },
      text: `记录于${time ?? '当前时间'}，${mealTypeLabel(mealType)}${names.length ? `，${names.slice(0, 3).join('、')}${names.length > 3 ? '等' : ''}` : ''}`,
      records: [current],
      numbers: [{ value: names.length, meaning: 'recognized_dish_count', derivation: 'count(payload.dishes)' }],
      evidenceFields: ['occurred_at', 'meal_type', 'dishes', 'time_context'],
      selectionHints: { allowed_surfaces: ['pwa_pending_ai_card', 'record_detail'] },
    }))
  }

  const macroValues = {
    protein_g: numericDishTotal(current, 'protein_g'),
    carb_g: numericDishTotal(current, 'carb_g'),
    fat_g: numericDishTotal(current, 'fat_g'),
  }
  if (names.length && Object.values(macroValues).some(value => value !== null && value > 0)) {
    const macroText = Object.entries(macroValues)
      .filter(([, value]) => value !== null && value > 0)
      .map(([key, value]) => `${{ protein_g: '蛋白质', carb_g: '碳水', fat_g: '脂肪' }[key]} ${value} 克`)
      .join('，')
    output.push(candidate({
      id: `fact:food:composition:${current.id}`,
      domainKey: 'food',
      semanticKey: 'food_composition',
      subtype: 'derived',
      dimension: 'record_composition',
      value: {
        dish_names: names,
        dish_count: names.length,
        macros: macroValues,
        estimated: payloadValue(current, 'is_estimated') ?? null,
      },
      text: `记录了${names.length}道菜：${names.slice(0, 3).join('、')}${names.length > 3 ? '等' : ''}；${macroText}`,
      records: [current],
      numbers: [
        { value: names.length, meaning: 'recognized_dish_count', role: 'count', derivation: 'count(payload.dishes)' },
        ...Object.entries(macroValues)
          .filter(([, value]) => value !== null && value > 0)
          .map(([meaning, value]) => ({ value, meaning, derivation: `sum(payload.dishes.${meaning})` })),
      ],
      confidence: 0.86,
      evidenceFields: ['occurred_at', 'dishes', 'is_estimated', 'confidence_note'],
      selectionHints: { allowed_surfaces: ['pwa_pending_ai_card', 'record_detail'] },
    }))
  }

  if (mealType && currentKcal !== null) {
    const mealPrior = prior
      .filter(record => textValue(payloadValue(record, 'meal_type')) === mealType)
      .map(record => num(payloadValue(record, 'total_calorie_kcal')))
      .filter(value => value !== null)
    const profileMeal = domainProfile?.meal_baseline?.[mealType]
    const profileMedian = num(profileMeal?.median_kcal)
    const profileN = num(profileMeal?.n)
    if (mealPrior.length >= 3 || (profileMedian !== null && profileN !== null && profileN >= 5)) {
      const useProfile = profileMedian !== null && profileN !== null && profileN >= 5
      const baseline = useProfile ? profileMedian : median(mealPrior)
      const sampleCount = useProfile ? profileN : mealPrior.length
      output.push(candidate({
        id: `comparison:food:meal-median:${current.id}`,
        domainKey: 'food',
        semanticKey: 'food_meal_vs_personal_median',
        claimType: 'comparison',
        dimension: 'meal_baseline',
        value: {
          meal_type: mealType,
          current: currentKcal,
          median: baseline,
          delta: round(currentKcal - baseline),
          unit: '千卡',
          sample_count: sampleCount,
          baseline_source: useProfile ? 'domain_profile' : 'record_history',
        },
        text: `这顿${mealTypeLabel(mealType)}约 ${round(currentKcal)} 千卡；你历史同餐次中位数为 ${baseline} 千卡`,
        records: [current, ...prior.filter(record => textValue(payloadValue(record, 'meal_type')) === mealType)],
        numbers: [
          { value: currentKcal, meaning: 'current_meal_calorie_kcal', derivation: 'source_record.total_calorie_kcal' },
          { value: baseline, meaning: 'historical_meal_median_calorie_kcal', derivation: 'median(meal_history.total_calorie_kcal)' },
          { value: sampleCount, meaning: 'meal_baseline_sample_count', role: 'count', derivation: 'count(meal_history)' },
        ],
        confidence: sampleCount >= 7 ? 0.92 : 0.82,
        evidenceFields: ['occurred_at', 'meal_type', 'total_calorie_kcal'],
      }))
    }
  }

  const priorDishCounts = new Map()
  for (const record of prior) {
    for (const name of dishNames(record)) {
      priorDishCounts.set(name, (priorDishCounts.get(name) ?? 0) + 1)
    }
  }
  const recurring = names.find(name => (priorDishCounts.get(name) ?? 0) >= 3)
  if (recurring) output.push(candidate({
    id: `pattern:food:recurring-dish:${current.id}`,
    domainKey: 'food',
    semanticKey: 'food_recurring_dish',
    claimType: 'pattern',
    dimension: 'recurrence',
    value: { dish_name: recurring, prior_count: priorDishCounts.get(recurring), window: 'available_history' },
    text: `「${recurring}」在你的历史饮食中已出现 ${priorDishCounts.get(recurring)} 次`,
    records: [current, ...prior.filter(record => dishNames(record).includes(recurring))],
    numbers: [{
      value: priorDishCounts.get(recurring),
      meaning: 'prior_dish_occurrence_count',
      role: 'count',
      derivation: 'count(prior_records_with_dish)',
    }],
    confidence: 0.9,
    evidenceFields: ['occurred_at', 'meal_type', 'dishes'],
  }))

  return output
}
