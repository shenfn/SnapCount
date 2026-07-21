import { createHash, randomUUID } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";

const args = new Set(process.argv.slice(2));
const execute = args.has("--execute");
const confirmed = args.has("--yes");
const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const bucket = "receipt-images";
const pageSize = 500;
const workerLeaseToken = randomUUID();

if (!supabaseUrl || !serviceRoleKey) {
  console.error("Missing SUPABASE_URL/VITE_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

if (execute && !confirmed) {
  console.error("Write mode requires both --execute and --yes.");
  process.exit(2);
}

const projectOrigin = new URL(supabaseUrl).origin;
const signedPathPrefix = "/storage/v1/object/sign/receipt-images/";
const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const targets = [
  ["transactions", "image_url"],
  ["income_records", "image_url"],
  ["data_records", "source_image_path"],
  ["staging_records", "image_path"],
  ["ai_recognition_logs", "image_url"],
];

function parseLegacySignedPath(value) {
  if (typeof value !== "string" || !/^https:\/\//i.test(value)) return null;
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    return null;
  }
  if (parsed.origin !== projectOrigin || !parsed.pathname.startsWith(signedPathPrefix)) return null;
  try {
    return decodeURIComponent(parsed.pathname.slice(signedPathPrefix.length)) || null;
  } catch {
    return null;
  }
}

function pathFingerprint(objectPath) {
  return createHash("sha256").update(objectPath).digest("hex").slice(0, 16);
}

function destinationPath(userId, oldPath) {
  const digest = createHash("sha256").update(oldPath).digest("hex").slice(0, 24);
  const basename = path.posix.basename(oldPath).replace(/[^A-Za-z0-9._-]/g, "_") || "image";
  return `${userId}/legacy-signed-url/${digest}-${basename}`;
}

function resultRow(data) {
  return Array.isArray(data) ? data[0] : data;
}

async function collectCandidates() {
  const groups = new Map();
  let externalUrls = 0;
  for (const [table, column] of targets) {
    let lastId = null;
    for (;;) {
      let query = supabase
        .from(table)
        .select(`id,user_id,${column}`)
        .not(column, "is", null)
        .order("id", { ascending: true })
        .limit(pageSize);
      if (lastId) query = query.gt("id", lastId);
      const { data, error } = await query;
      if (error) throw new Error(`Failed to scan ${table}.${column}: ${error.message}`);

      for (const row of data ?? []) {
        const value = row[column];
        if (typeof value !== "string" || !/^https?:\/\//i.test(value)) continue;
        externalUrls += 1;
        const oldPath = parseLegacySignedPath(value);
        if (!oldPath) continue;
        const current = groups.get(oldPath) ?? {
          oldPath,
          users: new Set(),
          referenceCount: 0,
          unownedReferenceCount: 0,
          businessReferenceCount: 0,
          aiLogReferenceCount: 0,
        };
        if (row.user_id) current.users.add(row.user_id);
        else current.unownedReferenceCount += 1;
        current.referenceCount += 1;
        if (table === "ai_recognition_logs") current.aiLogReferenceCount += 1;
        else current.businessReferenceCount += 1;
        groups.set(oldPath, current);
      }
      if (!data || data.length < pageSize) break;
      const nextId = data.at(-1)?.id;
      if (!nextId || nextId === lastId) throw new Error(`Candidate pagination did not advance for ${table}.${column}`);
      lastId = nextId;
    }
  }
  return { groups, externalUrls };
}

async function listOpenJobs() {
  const jobs = [];
  let lastId = null;
  for (;;) {
    let query = supabase
      .from("receipt_image_migration_jobs")
      .select("*")
      .neq("status", "done")
      .order("id", { ascending: true })
      .limit(pageSize);
    if (lastId) query = query.gt("id", lastId);
    const { data, error } = await query;
    if (error) throw new Error(`Failed to read migration jobs: ${error.message}`);
    jobs.push(...(data ?? []));
    if (!data || data.length < pageSize) break;
    const nextId = data.at(-1)?.id;
    if (!nextId || nextId === lastId) throw new Error("Migration job pagination did not advance");
    lastId = nextId;
  }
  return jobs;
}

async function objectExists(objectPath) {
  const parent = path.posix.dirname(objectPath);
  const name = path.posix.basename(objectPath);
  const { data, error } = await supabase.storage.from(bucket).list(parent === "." ? "" : parent, {
    limit: 100,
    search: name,
  });
  if (error) throw new Error(`Failed to inspect Storage object ${pathFingerprint(objectPath)}: ${error.message}`);
  return (data ?? []).some((item) => item.name === name);
}

async function objectSha256(objectPath) {
  const { data, error } = await supabase.storage.from(bucket).download(objectPath);
  if (error || !data) {
    throw new Error(`Failed to download Storage object ${pathFingerprint(objectPath)}: ${error?.message ?? "missing data"}`);
  }
  const bytes = Buffer.from(await data.arrayBuffer());
  return createHash("sha256").update(bytes).digest("hex");
}

async function claimJob(job) {
  const { data, error } = await supabase.rpc("claim_receipt_image_migration_job", {
    p_job_id: job.id,
    p_lease_token: workerLeaseToken,
    p_lease_seconds: 900,
  });
  if (error) throw new Error(`Failed to claim migration job: ${error.message}`);
  const claimed = resultRow(data);
  if (!claimed) throw new Error("Migration claim returned no job");
  return claimed;
}

async function recordJobError(job, error) {
  try {
    const { error: auditError } = await supabase.rpc("record_receipt_image_migration_error", {
      p_job_id: job.id,
      p_lease_token: workerLeaseToken,
      p_expected_status: job.status,
      p_error: error.message,
    });
    if (auditError) throw new Error(auditError.message);
  } catch (auditError) {
    return `${error.message}; additionally failed to persist job error: ${auditError.message}`;
  }
  return error.message;
}

async function prepareCandidates(groups) {
  const jobs = [];
  const errors = [];
  for (const group of groups.values()) {
    if (group.users.size !== 1) {
      errors.push({
        path_fingerprint: pathFingerprint(group.oldPath),
        message: `Path is referenced by ${group.users.size} users`,
      });
      continue;
    }
    const [userId] = group.users;
    const { data, error } = await supabase.rpc("prepare_receipt_image_migration", {
      p_user_id: userId,
      p_old_path: group.oldPath,
      p_new_path: destinationPath(userId, group.oldPath),
    });
    if (error) {
      errors.push({ path_fingerprint: pathFingerprint(group.oldPath), message: error.message });
      continue;
    }
    const job = resultRow(data);
    if (!job) {
      errors.push({ path_fingerprint: pathFingerprint(group.oldPath), message: "Preparation returned no job" });
      continue;
    }
    if (job.status === "done") {
      errors.push({ path_fingerprint: pathFingerprint(group.oldPath), message: "Completed job still has signed URL references" });
      continue;
    }
    jobs.push(job);
  }
  return { jobs, errors };
}

async function preflightCandidates(groups, openJobs) {
  const errors = [];
  const openJobsByPath = new Map(openJobs.map((job) => [job.old_path, job]));
  for (const group of groups.values()) {
    const fingerprint = pathFingerprint(group.oldPath);
    if (group.users.size !== 1 || group.unownedReferenceCount > 0) continue;
    const [userId] = group.users;
    const expectedDestination = destinationPath(userId, group.oldPath);

    const { data: owner, error: ownerError } = await supabase
      .from("receipt_image_owners")
      .select("user_id")
      .eq("bucket_name", bucket)
      .eq("bucket_path", group.oldPath)
      .maybeSingle();
    if (ownerError) {
      errors.push({ path_fingerprint: fingerprint, message: `Ownership check failed: ${ownerError.message}` });
      continue;
    }
    if (!owner || owner.user_id !== userId) {
      errors.push({ path_fingerprint: fingerprint, message: "Storage ownership is missing or does not match" });
      continue;
    }

    try {
      if (!await objectExists(group.oldPath)) {
        errors.push({ path_fingerprint: fingerprint, message: "Referenced legacy Storage object is missing" });
        continue;
      }
      const openJob = openJobsByPath.get(group.oldPath);
      if (openJob && (openJob.user_id !== userId || openJob.new_path !== expectedDestination)) {
        errors.push({ path_fingerprint: fingerprint, message: "Open migration job has a different owner or destination" });
        continue;
      }
      if (!openJob && await objectExists(expectedDestination)) {
        errors.push({ path_fingerprint: fingerprint, message: "Destination object exists without an open migration job" });
        continue;
      }
    } catch (error) {
      errors.push({ path_fingerprint: fingerprint, message: error.message });
      continue;
    }

    const { count, error: cleanupError } = await supabase
      .from("image_cleanup_queue")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("bucket_name", bucket)
      .eq("bucket_path", group.oldPath)
      .in("status", ["pending", "failed", "processing", "dead_letter"]);
    if (cleanupError) {
      errors.push({ path_fingerprint: fingerprint, message: `Cleanup overlap check failed: ${cleanupError.message}` });
    } else if ((count ?? 0) > 0) {
      errors.push({ path_fingerprint: fingerprint, message: "An active image cleanup task already exists" });
    }
  }

  for (const job of openJobs) {
    const fingerprint = pathFingerprint(String(job.old_path ?? "invalid-open-job"));
    if (typeof job.user_id !== "string"
      || typeof job.old_path !== "string"
      || typeof job.new_path !== "string"
      || !job.new_path.startsWith(`${job.user_id}/`)) {
      errors.push({ path_fingerprint: fingerprint, message: "Open migration job has an invalid owner or destination" });
      continue;
    }
    if (["pending", "copied"].includes(job.status) && !groups.has(job.old_path)) {
      errors.push({ path_fingerprint: fingerprint, message: "Open migration job no longer has a signed URL reference" });
      continue;
    }
    try {
      const oldExists = await objectExists(job.old_path);
      const newExists = await objectExists(job.new_path);
      if (job.status === "pending" && !oldExists) {
        errors.push({ path_fingerprint: fingerprint, message: "Pending migration source object is missing" });
        continue;
      }
      if (job.status === "copied" && (!oldExists || !newExists)) {
        errors.push({ path_fingerprint: fingerprint, message: "Copied migration source or destination is missing" });
        continue;
      }
      if (job.status === "references_updated" && !newExists) {
        errors.push({ path_fingerprint: fingerprint, message: "Reference-updated migration destination is missing" });
        continue;
      }
    } catch (error) {
      errors.push({ path_fingerprint: fingerprint, message: error.message });
      continue;
    }
    if (["copied", "references_updated"].includes(job.status)
      && (typeof job.old_sha256 !== "string"
        || !/^[0-9a-f]{64}$/.test(job.old_sha256)
        || job.old_sha256 !== job.new_sha256)) {
      errors.push({ path_fingerprint: fingerprint, message: "Open migration job has invalid copy hashes" });
      continue;
    }
    const { count, error: cleanupError } = await supabase
      .from("image_cleanup_queue")
      .select("id", { count: "exact", head: true })
      .eq("user_id", job.user_id)
      .eq("bucket_name", bucket)
      .eq("bucket_path", job.old_path)
      .in("status", ["pending", "failed", "processing", "dead_letter"]);
    if (cleanupError) {
      errors.push({ path_fingerprint: fingerprint, message: `Open-job cleanup check failed: ${cleanupError.message}` });
    } else if ((count ?? 0) > 0) {
      errors.push({ path_fingerprint: fingerprint, message: "Open migration job overlaps an active cleanup task" });
    }
  }
  return errors;
}

async function ensureCopied(job) {
  const oldHash = await objectSha256(job.old_path);
  const destinationExists = await objectExists(job.new_path);
  if (!destinationExists) {
    const { error } = await supabase.storage.from(bucket).copy(job.old_path, job.new_path);
    if (error) throw new Error(`Storage copy failed for ${pathFingerprint(job.old_path)}: ${error.message}`);
  }
  const newHash = await objectSha256(job.new_path);
  if (oldHash !== newHash) {
    throw new Error(`Storage copy hash mismatch for ${pathFingerprint(job.old_path)}`);
  }
  const { data, error } = await supabase.rpc("mark_receipt_image_migration_copied", {
    p_job_id: job.id,
    p_lease_token: workerLeaseToken,
    p_old_sha256: oldHash,
    p_new_sha256: newHash,
  });
  if (error) throw new Error(`Copy verification commit failed: ${error.message}`);
  const copied = resultRow(data);
  if (!copied) throw new Error("Copy verification returned no job");
  return copied;
}

async function advanceReferences(job) {
  const { data, error } = await supabase.rpc("advance_receipt_image_migration_references", {
    p_job_id: job.id,
    p_lease_token: workerLeaseToken,
  });
  if (error) throw new Error(`Reference migration failed: ${error.message}`);
  const updated = resultRow(data);
  if (!updated) throw new Error("Reference migration returned no job");
  return updated;
}

async function removeOldObjectAndFinalize(job) {
  const currentNewHash = await objectSha256(job.new_path);
  if (!job.new_sha256 || currentNewHash !== job.new_sha256) {
    throw new Error(`Migrated object hash changed for ${pathFingerprint(job.old_path)}`);
  }
  if (await objectExists(job.old_path)) {
    const currentOldHash = await objectSha256(job.old_path);
    if (!job.old_sha256 || currentOldHash !== job.old_sha256) {
      throw new Error(`Legacy object hash changed for ${pathFingerprint(job.old_path)}`);
    }
    const { error } = await supabase.storage.from(bucket).remove([job.old_path]);
    if (error) throw new Error(`Legacy object deletion failed: ${error.message}`);
  }
  if (await objectExists(job.old_path)) {
    throw new Error(`Legacy object still exists after deletion for ${pathFingerprint(job.old_path)}`);
  }
  const { data, error } = await supabase.rpc("finalize_receipt_image_migration", {
    p_job_id: job.id,
    p_lease_token: workerLeaseToken,
  });
  if (error) throw new Error(`Migration finalization failed: ${error.message}`);
  const completed = resultRow(data);
  if (!completed) throw new Error("Migration finalization returned no job");
  return completed;
}

async function processJob(inputJob) {
  let job = inputJob;
  try {
    job = await claimJob(job);
    if (job.status === "pending") job = await ensureCopied(job);
    if (job.status === "copied") job = await advanceReferences(job);
    if (job.status === "references_updated") job = await removeOldObjectAndFinalize(job);
    if (job.status !== "done") throw new Error(`Unexpected migration job state: ${job.status}`);
    return job;
  } catch (error) {
    throw new Error(await recordJobError(job, error));
  }
}

function publicJobSummary(job) {
  return {
    job_id: job.id,
    status: job.status,
    path_fingerprint: pathFingerprint(job.old_path),
    reference_count: Number(job.reference_count ?? 0),
    attempts: Number(job.attempts ?? 0),
    has_error: Boolean(job.last_error),
  };
}

const generatedAt = new Date();
const runId = generatedAt.toISOString().replace(/[:.]/g, "-");
const outputDir = path.resolve("local-only", "legacy-signed-image-migration", runId);
await mkdir(outputDir, { recursive: true });

const { groups, externalUrls } = await collectCandidates();
let openJobs = [];
let jobReadError = null;
try {
  openJobs = await listOpenJobs();
} catch (error) {
  jobReadError = error.message;
}

const candidateSummaries = [...groups.values()].map((group) => ({
  path_fingerprint: pathFingerprint(group.oldPath),
  user_count: group.users.size,
  has_unowned_references: group.unownedReferenceCount > 0,
  reference_count: group.referenceCount,
  business_reference_count: group.businessReferenceCount,
  ai_log_reference_count: group.aiLogReferenceCount,
}));
let reportPreflightErrors = [];
if (!jobReadError) {
  reportPreflightErrors = await preflightCandidates(groups, openJobs);
}
const report = {
  status: execute ? "execution_started" : "dry_run_complete",
  generated_at: generatedAt.toISOString(),
  project_origin: projectOrigin,
  bucket,
  external_url_references: externalUrls,
  signed_url_paths: candidateSummaries.length,
  blocked_shared_paths: candidateSummaries.filter((candidate) => (
    candidate.user_count !== 1 || candidate.has_unowned_references
  )).length,
  candidates: candidateSummaries,
  open_jobs_before: openJobs.map(publicJobSummary),
  results: [],
  errors: jobReadError ? [{ message: jobReadError }] : reportPreflightErrors,
};

if (!execute && (report.errors.length > 0 || report.blocked_shared_paths > 0)) {
  report.status = "dry_run_blocked";
}

if (execute && report.errors.length === 0 && report.blocked_shared_paths === 0) {
  const preparation = await prepareCandidates(groups);
  report.errors.push(...preparation.errors);
  if (report.errors.length === 0) {
    openJobs = await listOpenJobs();
    for (const job of openJobs) {
      try {
        const completed = await processJob(job);
        report.results.push(publicJobSummary(completed));
      } catch (error) {
        report.errors.push({
          job_id: job.id,
          path_fingerprint: pathFingerprint(job.old_path),
          message: error.message,
        });
      }
    }
  }
  const remainingJobs = await listOpenJobs();
  report.open_jobs_after = remainingJobs.map(publicJobSummary);
  report.status = report.errors.length === 0 && remainingJobs.length === 0
    ? "execution_complete"
    : "execution_incomplete";
} else if (execute) {
  report.status = "execution_blocked";
  if (report.blocked_shared_paths > 0) {
    report.errors.push({ message: "At least one Storage path is referenced by multiple users." });
  }
}

const reportPath = path.join(outputDir, "report.json");
await writeFile(reportPath, JSON.stringify(report, null, 2), "utf8");
console.log(JSON.stringify({
  status: report.status,
  signed_url_paths: report.signed_url_paths,
  blocked_shared_paths: report.blocked_shared_paths,
  completed_jobs: report.results.length,
  errors: report.errors.length,
  report_path: reportPath,
}, null, 2));

if (report.errors.length > 0
  || report.status === "execution_incomplete"
  || report.status === "execution_blocked"
  || report.status === "dry_run_blocked") {
  process.exitCode = 1;
}
