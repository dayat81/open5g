"use client";

import { useEffect, useState } from "react";
import { messageForApiError } from "@/lib/errors";

type Target = {
  name: string;
  status: string;
  error?: string | null;
};

type StatusBody = {
  status?: string;
  gx_rar_enabled?: boolean;
  gx_rar_effective?: boolean;
  note?: string;
  targets?: Target[];
  error?: { message?: string };
};

const DEMO_TARGETS: Target[] = [
  { name: "mongo-subscriber", status: "not_configured" },
  { name: "smf", status: "not_configured" },
  { name: "upf", status: "not_configured" },
  { name: "upf-a", status: "not_configured" },
  { name: "upf-b", status: "not_configured" },
];

export function CoreStatusPanel({ mode, apiBase }: { mode: "demo" | "api"; apiBase?: string }) {
  const [targets, setTargets] = useState<Target[]>(mode === "demo" ? DEMO_TARGETS : []);
  const [summary, setSummary] = useState(mode === "demo" ? "not_configured" : "loading");
  const [note, setNote] = useState(
    mode === "demo" ? "Contoh UI. Bukan pengamatan lab dan bukan metrik Prometheus." : "",
  );
  const [gx, setGx] = useState("mati");
  const [problem, setProblem] = useState<string | null>(null);
  const [needsLogin, setNeedsLogin] = useState(false);

  useEffect(() => {
    if (mode !== "api" || !apiBase) {
      return;
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    const root = apiBase.replace(/\/$/, "");
    fetch(`${root}/api/core/status`, { credentials: "include", signal: controller.signal })
      .then(async (response) => {
        const body = (await response.json()) as StatusBody;
        if (response.status === 401) {
          setNeedsLogin(true);
          setProblem(messageForApiError({ status: 401, code: "unauthenticated" }).text);
          setSummary("unauthenticated");
          setTargets([]);
          return;
        }
        if (!response.ok) {
          setNeedsLogin(false);
          setProblem(body.error?.message ?? `HTTP ${response.status}`);
          setSummary("down");
          setTargets([]);
          return;
        }
        setNeedsLogin(false);
        setTargets(body.targets ?? []);
        setSummary(body.status ?? "unknown");
        setNote(body.note ?? "");
        setGx(body.gx_rar_effective ? "hidup" : body.gx_rar_enabled ? "flag nyala, push tetap mati" : "mati");
        setProblem(null);
      })
      .catch((error: Error) => {
        setProblem(error.name === "AbortError" ? "timeout" : "request_failed");
        setSummary("down");
      })
      .finally(() => clearTimeout(timer));
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [apiBase, mode]);

  return (
    <section className="panel" aria-label="Status NF" data-testid="core-status">
      <h2>Status NF</h2>
      <p className="note">
        Ringkasan: <span className="mono">{summary}</span>
        {problem ? ` · ${problem}` : ""} · Gx RAR {gx}
      </p>
      {needsLogin ? <a href="/login">Masuk</a> : null}
      <ul className="nf-list">
        {targets.map((target) => (
          <li key={target.name} data-testid={`nf-${target.name}`}>
            <span className="mono">{target.name}</span>
            <span>
              {target.status}
              {target.error ? ` · ${target.error}` : ""}
            </span>
          </li>
        ))}
      </ul>
      <p className="note">
        {note} NF yang down tetap ditampilkan. Beberapa UPF tidak menggagalkan halaman ini. Sesi hidup tidak diverifikasi dari
        tampilan ini.
      </p>
    </section>
  );
}
