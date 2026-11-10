import { demoClient } from "./demo";
import type { ApplyResult, DashboardClient, Draft, ProvisionResult } from "./types";

export type ApiSession = {
  baseUrl: string;
  profileId?: string;
  etag?: string;
  csrfToken?: string;
};

type ErrorBody = { error?: { code?: string; message?: string } };
type JobBody = ApplyResult & ErrorBody & { lifecycle?: Draft["lifecycle"] };

const SESSION_REASON = "API mode membutuhkan profile id, If-Match, dan CSRF dari sesi yang sudah ada. Scaffold ini tidak membuat login palsu.";

function rejected(reason: string, op = "api_session_required"): ApplyResult {
  return {
    status: "rejected",
    executed: false,
    core_restart: false,
    data_origin: "api",
    reasons: [{ op, capability: "not_integrated", reason }],
  };
}

function httpClient(session: ApiSession): DashboardClient {
  const root = session.baseUrl.replace(/\/$/, "");
  const ready = Boolean(session.profileId && session.etag && session.csrfToken);
  return {
    mode: "api",
    async validate(draft) {
      if (!ready || !session.profileId || !session.etag || !session.csrfToken) {
        return { draft, error: SESSION_REASON };
      }
      const response = await fetch(`${root}/api/profiles/${session.profileId}/validate`, {
        method: "POST",
        credentials: "include",
        headers: {
          "content-type": "application/json",
          "if-match": session.etag,
          "x-csrf-token": session.csrfToken,
        },
      });
      const body = (await response.json()) as JobBody;
      if (!response.ok) {
        return { draft, error: body.error?.message ?? "Validasi ditolak oleh API" };
      }
      return { draft: { ...draft, lifecycle: body.lifecycle ?? "validated" }, error: null };
    },
    async apply() {
      if (!ready || !session.profileId || !session.etag || !session.csrfToken) {
        return rejected(SESSION_REASON);
      }
      const response = await fetch(`${root}/api/profiles/${session.profileId}/apply`, {
        method: "POST",
        credentials: "include",
        headers: {
          "content-type": "application/json",
          "if-match": session.etag,
          "x-csrf-token": session.csrfToken,
          "idempotency-key": crypto.randomUUID(),
        },
        body: JSON.stringify({}),
      });
      const body = (await response.json()) as JobBody;
      if (body.status === "rejected") {
        return {
          status: "rejected",
          executed: false,
          core_restart: false,
          data_origin: "api",
          reasons: body.reasons ?? [],
        };
      }
      return rejected(body.error?.message ?? "API tidak mengembalikan pushed atau active dari scaffold ini", body.error?.code ?? "api_rejected");
    },
    async provision(): Promise<ProvisionResult> {
      if (!ready || !session.profileId || !session.etag || !session.csrfToken) {
        return { error: SESSION_REASON, written: false };
      }
      const response = await fetch(`${root}/api/profiles/${session.profileId}/provision`, {
        method: "POST",
        credentials: "include",
        headers: {
          "content-type": "application/json",
          "if-match": session.etag,
          "x-csrf-token": session.csrfToken,
        },
      });
      const body = (await response.json()) as ErrorBody & { status?: string; error?: { message?: string } };
      if (!response.ok) {
        return { error: body.error?.message ?? "Tulis subscriber ditolak oleh API", written: false };
      }
      if (body.status !== "written") {
        return { error: body.error?.message ?? "API tidak menulis dokumen subscriber", written: false };
      }
      return { error: null, written: true };
    },
  };
}

export function createClient(baseUrl: string | undefined, session?: Omit<ApiSession, "baseUrl">): DashboardClient {
  if (!baseUrl) {
    return demoClient;
  }
  return httpClient({ baseUrl, ...session });
}
