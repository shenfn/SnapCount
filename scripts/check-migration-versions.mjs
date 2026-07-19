import { readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const migrationsDir = path.join(repoRoot, "supabase", "migrations");
const files = (await readdir(migrationsDir)).filter((file) => file.endsWith(".sql")).sort();
const versions = new Map();
const invalidFiles = [];

for (const file of files) {
  const match = /^(\d+)_.*\.sql$/.exec(file);
  if (!match) {
    invalidFiles.push(file);
    continue;
  }

  const existing = versions.get(match[1]) ?? [];
  existing.push(file);
  versions.set(match[1], existing);
}

const duplicateVersions = [...versions.entries()].filter(([, versionFiles]) => versionFiles.length > 1);

if (invalidFiles.length > 0 || duplicateVersions.length > 0) {
  if (invalidFiles.length > 0) {
    console.error(`Invalid migration filenames:\n${invalidFiles.map((file) => `- ${file}`).join("\n")}`);
  }
  if (duplicateVersions.length > 0) {
    console.error("Duplicate migration versions:");
    for (const [version, versionFiles] of duplicateVersions) {
      console.error(`- ${version}: ${versionFiles.join(", ")}`);
    }
  }
  process.exit(1);
}

console.log(`Validated ${files.length} migration files with unique numeric versions.`);
