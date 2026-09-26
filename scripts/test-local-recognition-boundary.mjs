import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const source = fs.readFileSync("supabase/functions/ingest-receipt/index.ts", "utf8");
const branchStart = source.indexOf("if (recognizeOnly) {");
const branchEnd = source.indexOf("// 慢请求采样：vision 阶段", branchStart);
const recognizeOnlyBranch = source.slice(branchStart, branchEnd);

test("LOCAL-P1-SPORT-001 J: recognize_only is an explicit operation", () => {
  assert.match(source, /const operation = normalizeString\(form\.get\("operation"\)\) \?\? "ingest"/);
  assert.match(source, /const recognizeOnly = operation === "recognize_only"/);
  assert.match(source, /operation: "recognize_only"/);
});

test("LOCAL-P1-SPORT-001 J: recognize_only returns the provider-neutral candidate envelope", () => {
  assert.match(recognizeOnlyBranch, /schema_version: "local-recognition-candidate-v1"/);
  assert.match(recognizeOnlyBranch, /candidate: responseCandidate/);
  assert.match(recognizeOnlyBranch, /missing_fields: missingFields/);
  assert.match(recognizeOnlyBranch, /evidence_fields: evidenceFields/);
  assert.match(recognizeOnlyBranch, /provider: \{ kind: "hosted_ai", name: aiProvider, model: aiModel \}/);
});

test("LOCAL-P1-SPORT-001 K-001: Hosted AI recognize_only keeps the existing authenticated boundary", () => {
  const authStart = source.indexOf("// 既没有有效 JWT，也没有有效 upload_token，拒绝请求");
  const authEnd = source.indexOf("if (userId) {", authStart);
  assert.notEqual(authStart, -1);
  assert.notEqual(authEnd, -1);
  const authBlock = source.slice(authStart, authEnd);
  assert.match(authBlock, /if \(!userId\) \{/);
  assert.doesNotMatch(authBlock, /!recognizeOnly/);
});

test("LOCAL-P1-SPORT-001 J: recognize_only has no cloud business fact or source-image write", () => {
  assert.doesNotMatch(recognizeOnlyBranch, /\.storage\.from\([^)]*\)\s*\.upload/);
  assert.doesNotMatch(recognizeOnlyBranch, /\.from\("(?:transactions|income_records|data_records|staging_records)"\)/);
  assert.doesNotMatch(recognizeOnlyBranch, /writeTraceAiLog|respondWithExpressionShadow|\.insert\(/);
  assert.match(source, /const storageUploadPromise = recognizeOnly\s*\n\s*\? Promise\.resolve/);
});

test("LOCAL-P1-SPORT-001 J: legacy ingest remains the default operation", () => {
  assert.match(source, /const operation = normalizeString\(form\.get\("operation"\)\) \?\? "ingest"/);
  assert.match(source, /if \(!recognizeOnly && operation !== "ingest"\)/);
  assert.match(source, /const storageUploadPromise = recognizeOnly[\s\S]*?\.storage\.from\(BUCKET_NAME\)/);
});
