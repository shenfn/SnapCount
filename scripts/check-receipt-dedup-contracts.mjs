import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const edgeSource = await readFile('supabase/functions/ingest-receipt/index.ts', 'utf8')
const migration = await readFile('supabase/migrations/20260721190000_finance_perceptual_duplicate_review.sql', 'utf8')
const webPrivacy = await readFile('public/privacy.html', 'utf8')
const iosPrivacy = await readFile('ios/SnapCount/Models/LegalDocuments.swift', 'utf8')

assert.match(edgeSource, /Promise\.all\(\[\s*supabase[\s\S]*from\("transactions"\)[\s\S]*from\("income_records"\)[\s\S]*from\("data_records"\)[\s\S]*stagingDuplicateQuery/)
assert.match(edgeSource, /Exact duplicate check failed:/)
assert.match(edgeSource, /loadRecentFinancialPerceptualCandidates\(supabase, userId!, stagingRetryId\),\s*900,/)
assert.match(edgeSource, /financeColumnsAvailable: false/)
assert.match(edgeSource, /perceptualStorageAvailable \? \{ perceptual_hash: perceptualHash \} : \{\}/)
assert.match(edgeSource, /errorType: "POSSIBLE_DUPLICATE"/)
assert.match(edgeSource, /status: "staging",\s*staging_status: "pending_review"/)
assert.match(edgeSource, /文字事实已保留，原图会按你的设置删除/)
assert.doesNotMatch(edgeSource, /该截图疑似已记录（相似图片）/)

const reviewBranchStart = edgeSource.indexOf('if (perceptualMatch && (recordType === "expense" || recordType === "income"))')
const incomeBranchStart = edgeSource.indexOf('if (recordType === "income" && normalizedAmount', reviewBranchStart)
assert.ok(reviewBranchStart >= 0 && incomeBranchStart > reviewBranchStart, 'possible-duplicate review branch must exist before finance inserts')
const reviewBranch = edgeSource.slice(reviewBranchStart, incomeBranchStart)
assert.doesNotMatch(reviewBranch, /cleanupUploadedObjectOrQueue/, 'possible-duplicate review must retain the new image when privacy settings allow')
assert.doesNotMatch(reviewBranch, /createAutoAccountEntry/, 'possible-duplicate review must not affect account balances')

const uploadStart = edgeSource.indexOf('const storageUploadPromise =')
const visionStart = edgeSource.indexOf('await callVisionWithFallback', uploadStart)
const uploadJoin = edgeSource.indexOf('await storageUploadPromise', visionStart)
assert.ok(uploadStart >= 0 && visionStart > uploadStart && uploadJoin > visionStart, 'Storage upload must overlap the Qwen request and join before persistence')

assert.match(migration, /alter table public\.transactions\s+add column if not exists perceptual_hash text/i)
assert.match(migration, /alter table public\.income_records\s+add column if not exists perceptual_hash text/i)
assert.match(migration, /fill_finance_perceptual_hash_from_staging/)
assert.match(migration, /revoke execute on function public\.fill_finance_perceptual_hash_from_staging\(\) from anon, authenticated/i)

assert.match(webPrivacy, /不可逆的图片感知指纹/)
assert.match(iosPrivacy, /不可逆的感知指纹/)

console.log('Receipt duplicate-review contracts validated.')
