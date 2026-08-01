/**
 * Shared versioned-consent gate for Edge Functions.
 *
 * The database owns the required versions and the comparison logic. Edge
 * Functions call the service-only RPC with a user id, or the authenticated RPC
 * when they already have a user-scoped client. Keeping the response normalized
 * here prevents one function from accidentally treating a legacy account as
 * consented while another one blocks it.
 */

export const CONSENT_REQUIRED_CODE = "consent_required";
export const CONSENT_GATE_UNAVAILABLE_CODE = "consent_gate_unavailable";

const ISO_TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

export interface ConsentStatus {
  user_id?: string | null;
  is_active: boolean;
  needs_consent: boolean;
  missing: string[];
  required_versions: Record<string, string>;
  accepted_versions: Record<string, string | null>;
  legal_consent_at?: string | null;
  sensitive_data_consent_at?: string | null;
}

export interface ConsentCheck {
  ok: boolean;
  status?: ConsentStatus;
  unavailable?: boolean;
  error?: unknown;
}

interface ConsentRpcClient {
  rpc(
    name: string,
    args?: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>;
}

function normalizeTimestamp(value: unknown): string | null {
  if (typeof value !== "string" || !ISO_TIMESTAMP_PATTERN.test(value)) return null;
  return Number.isNaN(Date.parse(value)) ? null : value;
}

function normalizeStatus(value: unknown): ConsentStatus | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  const required = raw.required_versions;
  const accepted = raw.accepted_versions;
  const missing = raw.missing;
  if (!required || typeof required !== "object" || Array.isArray(required)) return null;
  if (!accepted || typeof accepted !== "object" || Array.isArray(accepted)) return null;
  if (typeof raw.is_active !== "boolean" || typeof raw.needs_consent !== "boolean") return null;
  if (!Array.isArray(missing) || missing.some((key) => typeof key !== "string")) return null;
  const requiredObject = required as Record<string, unknown>;
  const acceptedObject = accepted as Record<string, unknown>;
  if (["terms", "privacy", "sensitive_data"].some((key) => typeof requiredObject[key] !== "string")) {
    return null;
  }
  if (["terms", "privacy", "sensitive_data"].some((key) => {
    const version = acceptedObject[key];
    return version !== null && typeof version !== "string";
  })) return null;
  return {
    user_id: typeof raw.user_id === "string" ? raw.user_id : null,
    is_active: raw.is_active,
    needs_consent: raw.needs_consent,
    missing: missing as string[],
    required_versions: Object.fromEntries(
      Object.entries(requiredObject)
        .filter((entry): entry is [string, string] => typeof entry[1] === "string"),
    ),
    accepted_versions: Object.fromEntries(
      Object.entries(acceptedObject)
        .filter((entry): entry is [string, string | null] => entry[1] === null || typeof entry[1] === "string"),
    ),
    legal_consent_at: normalizeTimestamp(raw.legal_consent_at),
    sensitive_data_consent_at: normalizeTimestamp(raw.sensitive_data_consent_at),
  };
}

/**
 * Pure comparison helper used by unit tests and by callers that already have
 * the DB status payload. Missing versions and missing timestamps are both
 * treated as requiring a fresh explicit acceptance.
 */
export function isConsentCurrent(status: ConsentStatus | null | undefined): boolean {
  if (!status || status.is_active !== true || status.needs_consent || status.missing.length > 0) return false;
  const keys = ["terms", "privacy", "sensitive_data"];
  if (!keys.every((key) => {
    const required = status.required_versions[key];
    return typeof required === "string"
      && required.length > 0
      && status.accepted_versions[key] === required;
  })) return false;
  return normalizeTimestamp(status.legal_consent_at) !== null
    && normalizeTimestamp(status.sensitive_data_consent_at) !== null;
}

async function callConsentRpc(
  client: ConsentRpcClient,
  rpcName: string,
  args: Record<string, unknown>,
): Promise<ConsentCheck> {
  try {
    const { data, error } = await client.rpc(rpcName, args);
    if (error) return { ok: false, unavailable: true, error };
    const status = normalizeStatus(data);
    if (!status) return { ok: false, unavailable: true, error: new Error("Invalid consent status payload") };
    return { ok: isConsentCurrent(status), status };
  } catch (error) {
    return { ok: false, unavailable: true, error };
  }
}

/** Service-role path used by ingest-receipt after it resolves a user id. */
export function loadConsentStatusForUser(
  client: ConsentRpcClient,
  userId: string,
): Promise<ConsentCheck> {
  return callConsentRpc(client, "get_consent_status_for_user", { p_user_id: userId });
}

/** Authenticated user-scoped path used by generate-insights. */
export function loadMyConsentStatus(
  client: ConsentRpcClient,
): Promise<ConsentCheck> {
  return callConsentRpc(client, "get_my_consent_status", {});
}

export function consentGateBody(check: ConsentCheck): Record<string, unknown> {
  if (check.unavailable) {
    return {
      error: "账户权限暂时不可用，请稍后重试",
      code: CONSENT_GATE_UNAVAILABLE_CODE,
    };
  }
  return {
    error: "请先完成最新的协议、隐私政策和敏感数据处理确认",
    code: CONSENT_REQUIRED_CODE,
    consent_required: true,
    required_versions: check.status?.required_versions ?? {},
    accepted_versions: check.status?.accepted_versions ?? {},
    missing: check.status?.missing ?? [],
  };
}

export function consentGateStatus(check: ConsentCheck): number {
  return check.unavailable ? 503 : 403;
}
