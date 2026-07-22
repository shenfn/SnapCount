import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const migrationPath = path.join(
  repoRoot,
  "supabase",
  "migrations",
  "20260720100000_harden_privileged_rpcs_and_receipt_storage.sql",
);
const sql = await readFile(migrationPath, "utf8");
const consentSql = await readFile(
  path.join(repoRoot, "supabase", "migrations", "20260719220000_registration_consent_and_private_defaults.sql"),
  "utf8",
);
const financeVocabularySql = await readFile(
  path.join(repoRoot, "supabase", "migrations", "20260721110000_user_finance_vocabulary.sql"),
  "utf8",
);
const ingestSource = await readFile(
  path.join(repoRoot, "supabase", "functions", "ingest-receipt", "index.ts"),
  "utf8",
);
const insightsSource = await readFile(
  path.join(repoRoot, "supabase", "functions", "generate-insights", "index.ts"),
  "utf8",
);
const imageMigrationSource = await readFile(
  path.join(repoRoot, "scripts", "migrate-legacy-signed-image-urls.mjs"),
  "utf8",
);

for (const policy of [
  "allow_anon_select_receipt_images",
  "allow_anon_delete_receipt_images",
  "allow_auth_select_receipt_images",
  "allow_auth_delete_receipt_images",
]) {
  assert.match(sql, new RegExp(`drop policy if exists ${policy}`, "i"));
}

assert.match(sql, /create policy receipt_images_authenticated_select_own[\s\S]*to authenticated[\s\S]*can_access_receipt_image\(name\)/i);
assert.doesNotMatch(sql, /create policy[\s\S]{0,160}to anon[\s\S]{0,160}receipt-images/i);
assert.match(sql, /create table if not exists public\.receipt_image_owners/i);
assert.match(sql, /can_access_receipt_image[\s\S]*receipt_image_owners/i);
assert.match(sql, /grant execute on function public\.normalize_receipt_image_path\(text\) to authenticated, service_role/i);
assert.match(sql, /create or replace function public\.enforce_receipt_image_reference_ownership\(\)/i);
assert.match(sql, /receipt image path belongs to another user/i);
assert.match(sql, /account_deletion_requests[\s\S]*account deletion is in progress/i);
assert.match(sql, /is_business_image_path_referenced[\s\S]*normalize_receipt_image_path\(image_url\)/i);
assert.match(sql, /prevent_reference_during_image_cleanup[\s\S]*normalize_receipt_image_path\(q\.bucket_path\)/i);
assert.match(sql, /queue_legacy_image_after_record_delete[\s\S]*receipt_image_owners[\s\S]*cleanup_reason/i);
assert.match(sql, /create or replace function public\.delete_user_account_data\(p_user_id uuid\)[\s\S]*delete from public\.user_configs/i);
assert.doesNotMatch(sql, /create or replace function public\.delete_user_account_data\(p_user_id uuid\)[\s\S]*delete from public\.image_cleanup_queue/i);
assert.match(sql, /tr_ai_logs_receipt_image_owner/i);
assert.match(sql, /public\.ai_recognition_logs[\s\S]*no legacy signed URL reference matches/i);

for (const signature of [
  "rebuild_expense_profile\\(uuid\\)",
  "rebuild_sleep_profile\\(uuid\\)",
  "rebuild_sport_profile\\(uuid\\)",
  "rebuild_food_profile\\(uuid\\)",
  "rebuild_reading_profile\\(uuid\\)",
  "rebuild_wallet_profile\\(uuid\\)",
  "refresh_domain_profile\\(uuid, text\\)",
  "recalculate_account_balance\\(uuid\\)",
]) {
  assert.match(
    sql,
    new RegExp(`revoke all on function public\\.${signature} from public, anon, authenticated`, "i"),
  );
}

for (const signature of [
  "prepare_receipt_image_migration\\(uuid, text, text\\)",
  "claim_receipt_image_migration_job\\(uuid, uuid, integer\\)",
  "mark_receipt_image_migration_copied\\(uuid, uuid, text, text\\)",
  "record_receipt_image_migration_error\\(uuid, uuid, text, text\\)",
  "advance_receipt_image_migration_references\\(uuid, uuid\\)",
  "finalize_receipt_image_migration\\(uuid, uuid\\)",
]) {
  assert.match(sql, new RegExp(`revoke all on function public\\.${signature} from public, anon, authenticated`, "i"));
  assert.match(sql, new RegExp(`grant execute on function public\\.${signature} to service_role`, "i"));
}

assert.match(sql, /create table if not exists public\.receipt_image_migration_jobs/i);
assert.match(sql, /status in \('pending', 'copied', 'references_updated', 'done'\)/i);
assert.match(sql, /lease_token uuid[\s\S]*lease_expires_at timestamptz/i);
assert.match(sql, /having count\(distinct user_id\) = 1[\s\S]*update public\.ai_recognition_logs as log[\s\S]*where log\.user_id is null/i);
assert.match(sql, /revoke all on table public\.receipt_image_migration_jobs from public, anon, authenticated, service_role/i);
assert.match(sql, /grant select on table public\.receipt_image_migration_jobs to service_role/i);
assert.match(sql, /status = 'pending'[\s\S]*lease_token = p_lease_token/i);
assert.match(sql, /new image path must be scoped to the user/i);
assert.match(sql, /image path is referenced by another or unowned record/i);
assert.match(sql, /receipt image copy hashes are missing or do not match/i);
assert.match(sql, /prevent_cleanup_during_receipt_image_migration/i);

assert.match(consentSql, /current terms, privacy, and sensitive data consent are required/i);
assert.match(consentSql, /submitted_terms_version is distinct from '2026-07-19'/i);
assert.match(consentSql, /submitted_privacy_version is distinct from '2026-07-19'/i);
assert.match(consentSql, /accepted_at timestamptz := now\(\)/i);

assert.match(financeVocabularySql, /create table if not exists public\.user_finance_vocabulary/i);
assert.match(financeVocabularySql, /user_id uuid not null references auth\.users\(id\) on delete cascade/i);
assert.match(financeVocabularySql, /alter table public\.user_finance_vocabulary enable row level security/i);
assert.match(financeVocabularySql, /create policy user_finance_vocabulary_select_own[\s\S]*to authenticated[\s\S]*user_id = auth\.uid\(\)/i);
assert.match(financeVocabularySql, /revoke all on table public\.user_finance_vocabulary from public, anon, authenticated, service_role/i);
assert.match(financeVocabularySql, /grant select on table public\.user_finance_vocabulary to authenticated, service_role/i);
assert.doesNotMatch(financeVocabularySql, /grant (insert|update|delete|all)[^;]*user_finance_vocabulary[^;]*(authenticated|service_role)/i);
assert.match(financeVocabularySql, /create or replace function public\.record_user_finance_vocabulary/i);
assert.match(financeVocabularySql, /security definer[\s\S]*set search_path = pg_catalog, public/i);
assert.match(financeVocabularySql, /expense categories must use the stable primary taxonomy/i);
assert.match(financeVocabularySql, /linked account not found or permission denied/i);
assert.match(financeVocabularySql, /revoke all on function public\.record_user_finance_vocabulary\(text, text, text, uuid\)[\s\S]*from public, anon, authenticated, service_role/i);
assert.match(financeVocabularySql, /grant execute on function public\.record_user_finance_vocabulary\(text, text, text, uuid\)[\s\S]*to authenticated\s*;/i);

assert.match(ingestSource, /function normalizeManagedStoragePath\(value: string\)/);
assert.match(ingestSource, /collectUserImagePaths[\s\S]*normalizeManagedStoragePath\(rawPath\)/);
assert.match(ingestSource, /collectUserScopedStoragePaths[\s\S]*tmp\/\$\{userId\}/);
assert.match(ingestSource, /offset \+= 200[\s\S]*ignoreDuplicates: true/);
assert.match(ingestSource, /processAccountDeletionCleanupRows/);
assert.match(ingestSource, /clearImageReferencesBatch/);
assert.match(ingestSource, /\.remove\(rowsNeedingStorageDelete\.map/);
assert.match(ingestSource, /cleanupReason: "account_delete"[\s\S]*limit: 100/);
assert.match(ingestSource, /action === "delete_account"[\s\S]*invoke_image_cleanup_worker[\s\S]*cleanup: null/);
assert.doesNotMatch(ingestSource, /action === "delete_account"[\s\S]{0,1400}await prepareAccountDeletion/);
assert.doesNotMatch(ingestSource, /finalizeReadyAccountDeletions[\s\S]{0,2200}cleanupAllUserImages/);
assert.match(ingestSource, /status === "deleting"[\s\S]*rescanAccountDeletionImages/);
assert.match(ingestSource, /status: "deleting"[\s\S]*5 \* 60 \* 1000/);
assert.match(ingestSource, /postDeleteQueueCount/);
assert.doesNotMatch(ingestSource, /Uploaded image rollback deferred[\s\S]{0,100}userId/);
assert.doesNotMatch(ingestSource, /raw=\$\{rawText\.slice/);
assert.doesNotMatch(ingestSource, /console\.error\(e\)/);
assert.doesNotMatch(insightsSource, /AI 返回不是合法 JSON：/);
assert.doesNotMatch(insightsSource, /console\.error\("\[generate-insights\][^\n]*, e\)/);
assert.doesNotMatch(imageMigrationSource, /from\("receipt_image_migration_jobs"\)[\s\S]{0,160}\.update\(/);
assert.match(imageMigrationSource, /claim_receipt_image_migration_job/);
assert.match(imageMigrationSource, /mark_receipt_image_migration_copied/);
assert.match(imageMigrationSource, /record_receipt_image_migration_error/);

console.log("Security migration contracts validated.");
