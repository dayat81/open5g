"use client";

import { useState, type FormEvent } from "react";
import { messageForApiError } from "@/lib/errors";
import { readFailure, requestJson, type SessionUser } from "@/lib/http";
import { writeCsrf } from "@/lib/session";

export function LoginForm({
  apiBase,
  onSuccess,
}: {
  apiBase: string;
  onSuccess: (user: SessionUser) => void;
}) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const result = await requestJson(apiBase, "/api/auth/login", {
        method: "POST",
        body: { email, password },
      });
      if (result.status !== 200) {
        setError(messageForApiError(readFailure(result.status, result.body)).text);
        return;
      }
      const body = result.body as { csrf_token?: string; user?: SessionUser };
      if (!body.csrf_token || !body.user) {
        setError("Jawaban login tidak berisi sesi.");
        return;
      }
      writeCsrf(body.csrf_token);
      onSuccess(body.user);
    } catch {
      setError("Permintaan ke API gagal.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="panel" onSubmit={(event) => void onSubmit(event)} data-testid="login-form">
      <h2>Masuk</h2>
      <p className="note">Pakai akun uji. Jendela uji tidak memakai akun instructor.</p>
      <div className="fields">
        <label className="field">
          Email
          <input
            className="box"
            type="email"
            autoComplete="username"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            required
          />
        </label>
        <label className="field">
          Kata sandi
          <input
            className="box"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
        </label>
      </div>
      {error ? (
        <p className="note" role="alert" data-testid="login-error">
          {error}
        </p>
      ) : null}
      <div className="actions">
        <button className="btn primary" type="submit" disabled={busy}>
          Masuk
        </button>
      </div>
    </form>
  );
}
