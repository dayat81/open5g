import type { ApiFailure } from "./errors";

export type SessionUser = {
  id: string;
  email: string;
  display_name: string;
  role: string;
  group_id: string | null;
};

export type JsonResult = {
  status: number;
  body: unknown;
};

export function apiRoot(apiBase: string): string {
  return apiBase.replace(/\/$/, "");
}

export async function requestJson(
  apiBase: string,
  path: string,
  options: {
    method?: string;
    csrf?: string | null;
    etag?: string | null;
    idempotencyKey?: string;
    body?: unknown;
  } = {},
): Promise<JsonResult> {
  const headers: Record<string, string> = { accept: "application/json" };
  if (options.body !== undefined) {
    headers["content-type"] = "application/json";
  }
  if (options.csrf) {
    headers["x-csrf-token"] = options.csrf;
  }
  if (options.etag) {
    headers["if-match"] = options.etag;
  }
  if (options.idempotencyKey) {
    headers["idempotency-key"] = options.idempotencyKey;
  }
  const response = await fetch(`${apiRoot(apiBase)}${path}`, {
    method: options.method ?? "GET",
    credentials: "include",
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const text = await response.text();
  let body: unknown = null;
  if (text) {
    try {
      body = JSON.parse(text) as unknown;
    } catch {
      body = { error: { code: "bad_response", message: "API returned a non-JSON body" } };
    }
  }
  return { status: response.status, body };
}

export function readFailure(status: number, body: unknown): ApiFailure {
  const error =
    body && typeof body === "object" && "error" in body
      ? (body as { error?: { code?: string; message?: string } }).error
      : undefined;
  return { status, code: error?.code, message: error?.message };
}

const SECRET_KEYS = new Set(["security", "k", "ki", "opc", "op", "password", "password_hash"]);

export function stripSecrets(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((item) => stripSecrets(item));
  }
  if (value && typeof value === "object") {
    const cleaned: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
      if (SECRET_KEYS.has(key.toLowerCase())) {
        continue;
      }
      cleaned[key] = stripSecrets(item);
    }
    return cleaned;
  }
  return value;
}
