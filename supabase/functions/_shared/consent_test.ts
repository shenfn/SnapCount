import { assert, assertEquals } from "jsr:@std/assert@1";
import { isConsentCurrent, loadMyConsentStatus, type ConsentStatus } from "./consent.ts";

function status(overrides: Partial<ConsentStatus> = {}): ConsentStatus {
  return {
    user_id: "00000000-0000-0000-0000-000000000001",
    is_active: true,
    needs_consent: false,
    missing: [],
    required_versions: {
      terms: "2026-07-19",
      privacy: "2026-07-22",
      sensitive_data: "2026-07-22",
    },
    accepted_versions: {
      terms: "2026-07-19",
      privacy: "2026-07-22",
      sensitive_data: "2026-07-22",
    },
    legal_consent_at: "2026-07-22T00:00:00.000Z",
    sensitive_data_consent_at: "2026-07-22T00:00:00.000Z",
    ...overrides,
  };
}

Deno.test("current consent versions pass the gate", () => {
  assert(isConsentCurrent(status()));
});

Deno.test("legacy account without sensitive-data version is blocked", () => {
  assertEquals(isConsentCurrent(status({
    needs_consent: true,
    missing: ["sensitive_data"],
    accepted_versions: {
      terms: "2026-07-19",
      privacy: "2026-07-22",
      sensitive_data: null,
    },
  })), false);
});

Deno.test("missing acceptance timestamp is blocked even when version matches", () => {
  assertEquals(isConsentCurrent(status({
    needs_consent: true,
    missing: ["sensitive_data"],
    sensitive_data_consent_at: null,
  })), false);
});

Deno.test("inactive account never passes the AI gate", () => {
  assertEquals(isConsentCurrent(status({ is_active: false })), false);
});

Deno.test("inconsistent accepted versions fail closed", () => {
  assertEquals(isConsentCurrent(status({
    accepted_versions: {
      terms: "2026-07-19",
      privacy: "2026-07-19",
      sensitive_data: "2026-07-22",
    },
  })), false);
});

Deno.test("acceptance timestamps are required independently of RPC flags", () => {
  assertEquals(isConsentCurrent(status({ legal_consent_at: null })), false);
  assertEquals(isConsentCurrent(status({ sensitive_data_consent_at: null })), false);
});

Deno.test("malformed acceptance timestamps fail closed", () => {
  assertEquals(isConsentCurrent(status({ legal_consent_at: "2026/08/01 10:00:00" })), false);
  assertEquals(isConsentCurrent(status({ sensitive_data_consent_at: "2026-13-01T10:00:00Z" })), false);
});

Deno.test("malformed RPC status fails closed", async () => {
  const check = await loadMyConsentStatus({
    async rpc() {
      return {
        data: {
          needs_consent: false,
          missing: [],
          required_versions: status().required_versions,
          accepted_versions: status().accepted_versions,
        },
        error: null,
      };
    },
  });
  assertEquals(check.ok, false);
  assertEquals(check.unavailable, true);
});
