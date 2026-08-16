import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

function functionSlice(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker)
  const end = source.indexOf(endMarker, start + startMarker.length)
  assert.notEqual(start, -1, `missing start marker: ${startMarker}`)
  assert.notEqual(end, -1, `missing end marker: ${endMarker}`)
  return source.slice(start, end)
}

test('PWA-064B Store delegates manual repayment transport to the account boundary', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const confirmSource = functionSlice(source, 'async function confirmRepaymentCyclePaid(', 'async function revokeLiabilityPayment(')
  const revokeSource = functionSlice(source, 'async function revokeLiabilityPayment(', 'function openAccountEntrySource(')

  assert.match(source, /createAccountRepository/)
  assert.match(source, /createRepaymentFeature/)
  assert.match(source, /repaymentFeature\.reset\(\)/)
  assert.match(confirmSource, /repaymentFeature\.confirm\(/)
  assert.match(revokeSource, /repaymentFeature\.revoke\(/)
  assert.doesNotMatch(confirmSource, /set_repayment_cycle_paid_amount|p_cycle_id|p_paid_amount/)
  assert.doesNotMatch(revokeSource, /revoke_liability_payment|p_payment_id/)
  assert.doesNotMatch(source, /function mapRepaymentCycleRow\(/)
})

test('PWA-064F repayment amount, minimum, overpayment, debit preview, and revoke confirmation remain visible', async () => {
  const page = await readFile('src/components/pages/PageAccountDetail.vue', 'utf8')
  const store = await readFile('src/composables/useStore.js', 'utf8')

  assert.match(page, /repaymentMode/)
  assert.match(page, /partialRepaymentAmount/)
  assert.match(page, /minPaymentAmount/)
  assert.match(page, /repaymentOverpaymentAmount/)
  assert.match(page, /repaymentDebitAccount/)
  assert.match(store, /确认撤销这笔还款记录/)
})
