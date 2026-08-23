import test from 'node:test'
import assert from 'node:assert/strict'
import { access, readFile } from 'node:fs/promises'

const useCasePath = 'ios/SnapCount/Features/Records/LocalExpenseUseCase.swift'
const mapperPath = 'ios/SnapCount/Features/Records/LocalExpenseMapper.swift'
const recordsPath = 'ios/SnapCount/Features/Records/RecordsView.swift'
const accountPreparationPath = 'ios/SnapCount/Features/Records/LocalAccountPreparationView.swift'
const expenseEntryPath = 'ios/SnapCount/Features/Records/LocalExpenseEntryView.swift'

test('LOCAL-002UIB application contract exposes workspace and account creation', async () => {
  const source = await readFile(useCasePath, 'utf8')
  assert.match(source, /struct LocalExpenseWorkspace/u)
  assert.match(source, /struct LocalAccountSetupCommand/u)
  assert.match(source, /func prepareWorkspace\(\)/u)
  assert.match(source, /func createAccount\(_ command: LocalAccountSetupCommand\)/u)
  assert.match(source, /func accounts\b/u)
  assert.match(source, /func accountBalanceMinor\(_ accountID: UUID\)/u)
})

test('LOCAL-002UIB amount contract uses Decimal minor units and allows zero opening balance', async () => {
  const source = await readFile(mapperPath, 'utf8')
  assert.match(source, /static func openingBalanceMinor\(/u)
  assert.match(source, /Decimal\(string:/u)
  assert.match(source, /Int64\.max/u)
  assert.doesNotMatch(source, /Double\(.*opening|opening.*Double\(/u)
})

test('LOCAL-002UIB local records expose an explicit account preparation path', async () => {
  await access(accountPreparationPath)
  await access(expenseEntryPath)
  const source = await readFile(recordsPath, 'utf8')
  assert.match(source, /showLocalAccountPreparation/u)
  assert.match(source, /LocalAccountPreparationView/u)
  assert.doesNotMatch(source, /else\s*\{\s*showManualRecordSheet\s*=\s*true/u)
})

test('LOCAL-002UIB local entry is expense-only and has no cloud vocabulary/account load', async () => {
  const source = await readFile(expenseEntryPath, 'utf8')
  assert.match(source, /expense/u)
  assert.doesNotMatch(source, /income|universal|loadAccounts|loadFinanceVocabulary|暂不绑定/u)
  assert.match(source, /已保存在本机/u)
})

test('LOCAL-002UIB local account preparation is explicit and does not create a default account', async () => {
  const source = await readFile(accountPreparationPath, 'utf8')
  assert.match(source, /账户名称|name/u)
  assert.match(source, /期初余额|openingBalance/u)
  assert.match(source, /cash|wallet_balance|debit_card/u)
  assert.doesNotMatch(source, /defaultAccount|默认账户|setDefault/u)
})

console.log('iOS LOCAL-002-UIB local account boundary checks passed')
