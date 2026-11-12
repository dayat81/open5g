import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { LiveProfileEditor } from "./LiveProfileEditor";

const userBody = {
  id: "u1",
  email: "student@example.test",
  display_name: "Student",
  role: "student",
  group_id: "g1",
};

const assignment = { id: "a1", imsi: "001010000000001", owner_user_id: "u1", group_id: "g1" };

type Call = { url: string; method: string; headers: Headers; body: string | null };

function json(status: number, body: unknown) {
  return { status, text: async () => JSON.stringify(body) };
}

afterEach(() => {
  vi.unstubAllGlobals();
  sessionStorage.clear();
});

function installFetch(handler: (call: Call) => { status: number; text: () => Promise<string> }) {
  const calls: Call[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string, init?: RequestInit) => {
      const call = {
        url: String(url),
        method: init?.method ?? "GET",
        headers: new Headers(init?.headers),
        body: init?.body === undefined ? null : String(init.body),
      };
      calls.push(call);
      return handler(call);
    }),
  );
  return calls;
}

describe("LiveProfileEditor", () => {
  it("sends CSRF and If-Match through save, validate, provision, and rollback", async () => {
    const user = userEvent.setup();
    let profile: Record<string, unknown> | null = null;
    const calls = installFetch((call) => {
      if (call.url.endsWith("/api/auth/me")) {
        return json(200, userBody);
      }
      if (call.url.endsWith("/api/assignments") && call.method === "GET") {
        return json(200, [assignment]);
      }
      if (call.url.endsWith("/api/profiles") && call.method === "GET") {
        return json(200, profile ? [profile] : []);
      }
      if (call.url.endsWith("/subscriber")) {
        return json(200, {
          found: true,
          security: { k: "SECRET-K", opc: "SECRET-OPC" },
          ki: "SECRET-KI",
          sessions: [
            {
              name: "internet",
              qci: 6,
              arp: { priority: 5 },
              ambr_ul: { value: 50, unit: "mbps" },
              ambr_dl: { value: 100, unit: "mbps" },
              pcc_rules: [
                { owned: true, qci: 6, flows: [{ description: "permit out ip from 203.0.113.0/24 to assigned" }] },
                { owned: false, flows: [{ description: "foreign-rule" }] },
              ],
            },
          ],
        });
      }
      if (call.url.endsWith("/api/profiles") && call.method === "POST") {
        profile = {
          id: "p1",
          assignment_id: "a1",
          version_etag: "etag-1",
          desired_version: 1,
          lifecycle: "saved",
          content: JSON.parse(call.body ?? "{}").content,
        };
        return json(201, profile);
      }
      if (call.url.endsWith("/api/profiles/p1") && call.method === "PUT") {
        profile = {
          id: "p1",
          assignment_id: "a1",
          version_etag: "etag-2",
          desired_version: 2,
          lifecycle: "saved",
          content: JSON.parse(call.body ?? "{}"),
        };
        return json(200, profile);
      }
      if (call.url.endsWith("/validate")) {
        profile = { ...(profile ?? {}), lifecycle: "validated" };
        return json(200, profile);
      }
      if (call.url.endsWith("/provision")) {
        return json(200, { status: "written", live_gx_rar: false });
      }
      if (call.url.endsWith("/rollback")) {
        profile = {
          id: "p1",
          assignment_id: "a1",
          version_etag: "etag-3",
          desired_version: 3,
          lifecycle: "saved",
          content: {},
        };
        return json(409, { profile, subscriber_document: { status: "written" } });
      }
      return json(500, { error: { code: "unexpected", message: call.url } });
    });
    sessionStorage.setItem("open5g.csrf", "csrf-test");
    render(<LiveProfileEditor apiBase="http://dashboard.local" />);
    expect(await screen.findByRole("button", { name: "Simpan draf" })).toBeTruthy();
    expect(screen.getByTestId("account-role").textContent).toBe("student");
    expect(screen.getByTestId("subscriber-view").textContent).toContain("203.0.113.0/24");
    expect(screen.getByTestId("subscriber-view").textContent).not.toContain("SECRET-K");
    expect(screen.getByTestId("subscriber-view").textContent).not.toContain("foreign-rule");

    await user.click(screen.getByRole("button", { name: "Simpan draf" }));
    await waitFor(() => expect(calls.some((call) => call.method === "POST" && call.url.endsWith("/api/profiles"))).toBe(true));
    const created = calls.find((call) => call.method === "POST" && call.url.endsWith("/api/profiles"));
    expect(created?.headers.get("x-csrf-token")).toBe("csrf-test");
    expect(created?.headers.get("if-match")).toBeNull();

    const qci = screen.getByRole("spinbutton", { name: "QCI" });
    await user.clear(qci);
    await user.type(qci, "8");
    await user.click(screen.getByRole("button", { name: "Simpan draf" }));
    await waitFor(() => expect(calls.some((call) => call.method === "PUT")).toBe(true));
    const updated = calls.find((call) => call.method === "PUT");
    expect(updated?.headers.get("x-csrf-token")).toBe("csrf-test");
    expect(updated?.headers.get("if-match")).toBe("etag-1");

    await waitFor(() => expect(screen.getByRole("button", { name: "Validasi" })).toHaveProperty("disabled", false));
    await user.click(screen.getByRole("button", { name: "Validasi" }));
    const validated = calls.find((call) => call.url.endsWith("/validate"));
    expect(validated?.headers.get("x-csrf-token")).toBe("csrf-test");
    expect(validated?.headers.get("if-match")).toBe("etag-2");

    await waitFor(() => expect(screen.getByRole("button", { name: "Tulis subscriber" })).toHaveProperty("disabled", false));
    await user.click(screen.getByRole("button", { name: "Tulis subscriber" }));
    const written = calls.find((call) => call.url.endsWith("/provision"));
    expect(written?.headers.get("x-csrf-token")).toBe("csrf-test");
    expect(written?.headers.get("if-match")).toBe("etag-2");
    expect(screen.getByTestId("provision-note").textContent).toMatch(/attach ulang/i);
    expect(screen.getByTestId("provision-note").textContent).toMatch(/tidak diterapkan/i);

    await waitFor(() => expect(screen.getByRole("button", { name: "Pulihkan versi sebelumnya" })).toHaveProperty("disabled", false));
    await user.click(screen.getByRole("button", { name: "Pulihkan versi sebelumnya" }));
    const rolled = calls.find((call) => call.url.endsWith("/rollback"));
    expect(rolled?.headers.get("x-csrf-token")).toBe("csrf-test");
    expect(rolled?.headers.get("if-match")).toBe("etag-2");
    expect(rolled?.headers.get("idempotency-key")).toBeTruthy();
    expect(JSON.parse(rolled?.body ?? "{}")).toEqual({ to_version: 1 });
    expect(screen.getByTestId("phase2-apply")).toHaveProperty("disabled", true);
  });

  it("blocks a QCI outside 5-9 before calling the API", async () => {
    const user = userEvent.setup();
    const calls = installFetch((call) => {
      if (call.url.endsWith("/api/auth/me")) return json(200, userBody);
      if (call.url.endsWith("/api/assignments")) return json(200, [assignment]);
      if (call.url.endsWith("/api/profiles")) return json(200, []);
      if (call.url.endsWith("/subscriber")) return json(200, { found: true, sessions: [] });
      return json(500, { error: { code: "unexpected" } });
    });
    sessionStorage.setItem("open5g.csrf", "csrf-test");
    render(<LiveProfileEditor apiBase="http://dashboard.local" />);
    const qci = await screen.findByRole("spinbutton", { name: "QCI" });
    await user.clear(qci);
    await user.type(qci, "4");
    await user.click(screen.getByRole("button", { name: "Simpan draf" }));
    expect(screen.getByRole("alert").textContent).toMatch(/QCI harus 5–9/);
    expect(calls.some((call) => call.method === "POST")).toBe(false);
  });

  it("maps 401, 403, and 409 onto Indonesian messages", async () => {
    const user = userEvent.setup();
    installFetch((call) => {
      if (call.url.endsWith("/api/auth/login")) {
        return json(401, { error: { code: "invalid_login", message: "Email or password is wrong" } });
      }
      if (call.url.endsWith("/api/auth/me")) {
        return json(401, { error: { code: "unauthenticated", message: "Login required" } });
      }
      return json(500, { error: { code: "unexpected" } });
    });
    render(<LiveProfileEditor apiBase="http://dashboard.local" />);
    expect(await screen.findByTestId("login-form")).toBeTruthy();
    await user.type(screen.getByRole("textbox", { name: "Email" }), "student@example.test");
    await user.type(screen.getByLabelText("Kata sandi"), "wrong-password");
    await user.click(screen.getByRole("button", { name: "Masuk" }));
    expect(screen.getByTestId("login-error").textContent).toMatch(/kata sandi salah/i);
  });

  it("maps a 403 cross-group denial and a 409 conflict with reload", async () => {
    const user = userEvent.setup();
    let mode: "forbidden" | "conflict" = "forbidden";
    installFetch((call) => {
      if (call.url.endsWith("/api/auth/me")) return json(200, userBody);
      if (call.url.endsWith("/api/assignments") && call.method === "GET") return json(200, [assignment]);
      if (call.url.endsWith("/api/profiles") && call.method === "GET") return json(200, []);
      if (call.url.endsWith("/subscriber")) return json(200, { found: false, sessions: [] });
      if (call.method === "POST" && mode === "forbidden") {
        return json(403, { error: { code: "cross_group_forbidden", message: "Request is outside the caller scope" } });
      }
      if (call.method === "POST") {
        return json(409, { error: { code: "subscriber_conflict", message: "Subscriber document changed" } });
      }
      return json(500, { error: { code: "unexpected" } });
    });
    sessionStorage.setItem("open5g.csrf", "csrf-test");
    render(<LiveProfileEditor apiBase="http://dashboard.local" />);
    await user.click(await screen.findByRole("button", { name: "Simpan draf" }));
    expect(screen.getByRole("alert").textContent).toMatch(/luar grup/i);
    mode = "conflict";
    await user.click(screen.getByRole("button", { name: "Simpan draf" }));
    expect(screen.getByRole("alert").textContent).toMatch(/muat ulang/i);
    expect(screen.getByRole("button", { name: "Muat ulang" })).toBeTruthy();
  });
});
