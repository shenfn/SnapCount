import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import {
  EXPENSE_CATEGORY_DEFINITIONS,
  expenseCategoryLabel,
  expenseCategoryUiGroup,
  normalizeExpenseCategory,
} from '../../../../src/domains/expenseCategories.js'

test('expense category contract normalizes canonical and legacy values', () => {
  assert.equal(normalizeExpenseCategory('food'), 'food')
  assert.equal(normalizeExpenseCategory('餐饮'), 'food')
  assert.equal(normalizeExpenseCategory('医疗'), 'health')
  assert.equal(normalizeExpenseCategory('学习'), 'education')
  assert.equal(normalizeExpenseCategory('unknown'), null)
})

test('expense category contract preserves detail while exposing current UI groups', () => {
  assert.equal(expenseCategoryLabel('health'), '健康')
  assert.equal(expenseCategoryLabel('education'), '教育')
  assert.equal(expenseCategoryUiGroup('health'), 'life')
  assert.equal(expenseCategoryUiGroup('education'), 'other')
})

test('expense profile SQL mirrors every canonical category and alias', () => {
  const sql = readFileSync('supabase/migrations/20260715090000_normalize_expense_categories.sql', 'utf8')
  for (const definition of EXPENSE_CATEGORY_DEFINITIONS) {
    assert.ok(sql.includes(`'${definition.code}'`), `missing canonical code ${definition.code}`)
    for (const alias of definition.aliases) {
      assert.ok(sql.includes(`'${alias}'`), `missing alias ${alias}`)
    }
  }
})
