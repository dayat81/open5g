"use client";

import { useEffect, useState, type ReactNode } from "react";
import { LoginForm } from "./LoginForm";
import { Shell } from "./Shell";
import { requestJson, type SessionUser } from "@/lib/http";
import { clearCsrf, readCsrf } from "@/lib/session";

export function SessionFrame({
  active,
  mode,
  apiBase,
  children,
}: {
  active: string;
  mode: "demo" | "api";
  apiBase?: string;
  children: ReactNode;
}) {
  const api = mode === "api" && apiBase ? apiBase : "";
  const [phase, setPhase] = useState<"loading" | "anon" | "in">(api ? "loading" : "in");
  const [user, setUser] = useState<SessionUser | null>(null);

  useEffect(() => {
    if (!api) {
      return;
    }
    let cancel = false;
    requestJson(api, "/api/auth/me")
      .then((result) => {
        if (cancel) {
          return;
        }
        if (result.status === 401) {
          setUser(null);
          setPhase("anon");
          return;
        }
        if (result.status !== 200) {
          setPhase("anon");
          return;
        }
        setUser(result.body as SessionUser);
        setPhase("in");
      })
      .catch(() => {
        if (!cancel) {
          setPhase("anon");
        }
      });
    return () => {
      cancel = true;
    };
  }, [api]);

  async function logout() {
    if (!api) {
      return;
    }
    try {
      await requestJson(api, "/api/auth/logout", { method: "POST", csrf: readCsrf(), body: {} });
    } catch {
      /* local session still ends */
    }
    clearCsrf();
    setUser(null);
    setPhase("anon");
  }

  const account =
    api && user ? (
      <span className="meta">
        <span data-testid="account-email">{user.email}</span>
        <span className="role-badge" data-testid="account-role">
          {user.role}
        </span>
        <button className="btn ghost" type="button" onClick={() => void logout()}>
          Keluar
        </button>
      </span>
    ) : api && phase === "anon" ? (
      <a href="/login">Masuk</a>
    ) : null;

  return (
    <Shell active={active} mode={mode} account={account}>
      {api && phase === "loading" ? <p className="note">Memeriksa sesi…</p> : null}
      {api && phase === "anon" ? (
        <LoginForm
          apiBase={api}
          onSuccess={(next) => {
            setUser(next);
            setPhase("in");
          }}
        />
      ) : null}
      {phase === "in" ? children : null}
    </Shell>
  );
}
