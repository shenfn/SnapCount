import { readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const migrationsDir = path.join(repoRoot, "supabase", "migrations");
const deferredMigrationsDir = path.join(repoRoot, "supabase", "deferred-migrations");
const baselinePath = path.join(repoRoot, "supabase", "production-migration-baseline.json");
const baseline = JSON.parse(await readFile(baselinePath, "utf8"));
const files = (await readdir(migrationsDir)).filter((file) => file.endsWith(".sql")).sort();
const deferredFiles = (await readdir(deferredMigrationsDir)).filter((file) => file.endsWith(".sql")).sort();
const versions = new Map();
const invalidFiles = [];
const invalidHistoricalVersions = [];
const pendingVersions = [];

const maximumAppliedVersion = BigInt(baseline.maximumAppliedVersion);
const appliedTimestampVersions = new Set(baseline.appliedTimestampVersions);
const legacyNumberedRanges = baseline.legacyNumberedRanges.map(({ start, end }) => ({
  start: BigInt(start),
  end: BigInt(end),
}));

for (const file of files) {
  const match = /^(\d+)_([a-z0-9_]+)\.sql$/.exec(file);
  if (!match) {
    invalidFiles.push(file);
    continue;
  }

  const version = match[1];
  const numericVersion = BigInt(version);
  const normalizedVersion = numericVersion.toString();
  const existing = versions.get(normalizedVersion) ?? [];
  existing.push(file);
  versions.set(normalizedVersion, existing);

  if (version.length <= 3) {
    const isKnownLegacyVersion = legacyNumberedRanges.some(({ start, end }) => (
      numericVersion >= start && numericVersion <= end
    ));
    if (!isKnownLegacyVersion) invalidHistoricalVersions.push(file);
    continue;
  }

  if (version.length !== 14) {
    invalidFiles.push(file);
    continue;
  }

  if (numericVersion <= maximumAppliedVersion) {
    if (!appliedTimestampVersions.has(version)) invalidHistoricalVersions.push(file);
  } else {
    pendingVersions.push(file);
  }
}

const duplicateVersions = [...versions.entries()].filter(([, versionFiles]) => versionFiles.length > 1);
const invalidDeferredFiles = deferredFiles.filter((file) => (
  !/^[a-z0-9_]+\.template\.sql$/.test(file) || /^\d+_/.test(file)
));

if (
  invalidFiles.length > 0 ||
  duplicateVersions.length > 0 ||
  invalidHistoricalVersions.length > 0 ||
  invalidDeferredFiles.length > 0
) {
  if (invalidFiles.length > 0) {
    console.error(`Invalid migration filenames:\n${invalidFiles.map((file) => `- ${file}`).join("\n")}`);
  }
  if (duplicateVersions.length > 0) {
    console.error("Duplicate migration versions:");
    for (const [version, versionFiles] of duplicateVersions) {
      console.error(`- ${version}: ${versionFiles.join(", ")}`);
    }
  }
  if (invalidHistoricalVersions.length > 0) {
    console.error(`Migrations inserted outside the recorded production history:\n${invalidHistoricalVersions.map((file) => `- ${file}`).join("\n")}`);
  }
  if (invalidDeferredFiles.length > 0) {
    console.error(`Deferred migrations must use an unversioned ASCII .template.sql name:\n${invalidDeferredFiles.map((file) => `- ${file}`).join("\n")}`);
  }
  process.exit(1);
}

console.log(`Validated ${files.length} active migrations against production ${baseline.maximumAppliedVersion}.`);
console.log(`Pending active migrations: ${pendingVersions.join(", ") || "none"}.`);
console.log(`Validated ${deferredFiles.length} deferred migration templates.`);
