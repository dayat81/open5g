"use client";

import { useCallback, useEffect, useState } from "react";
import { LoginForm } from "./LoginForm";
import { Shell } from "./Shell";
import { messageForApiError } from "@/lib/errors";
import { readFailure, requestJson, stripSecrets, type SessionUser } from "@/lib/http";
import {
  clientDraftError,
  draftFromContent,
  draftToContent,
  EMPTY_DRAFT,
  type EditorDraft,
} from "@/lib/profileDraft";
import { clearCsrf, readCsrf } from "@/lib/session";

type Assignment = { id: string; imsi: string; owner_user_id: string; group_id: string };
type ProfileRow = {
  id: string;
  assignment_id: string;
  version_etag: string;
  desired_version: number;
  lifecycle: string;
  content: unknown;
};
type FlowView = { description?: string };
type RuleView = { owned?: boolean; qci?: number; flows?: FlowView[] };
type BitrateView = { value?: number; unit?: string };
type SessionView = {
  name?: string;
  qci?: number;
  arp?: { priority?: number };
  ambr_ul?: BitrateView;
  ambr_dl?: BitrateView;
  pcc_rules?: RuleView[];
};
type SubscriberView = {
  found?: boolean;
  sessions?: SessionView[];
  error?: { code?: string; message?: string };
};

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : null;
}

function bitrateText(node: BitrateView | undefined): string {
  if (!node || node.value === undefined) {
    return "—";
  }
  return `${node.value} ${node.unit ?? ""}`.trim();
}

export function LiveProfileEditor({ apiBase }: { apiBase: string }) {
  const [phase, setPhase] = useState<"loading" | "anon" | "ready">("loading");
  const [user, setUser] = useState<SessionUser | null>(null);
  const [assignments, setAssignments] = useState<Assignment[]>([]);
  const [assignmentId, setAssignmentId] = useState("");
  const [profiles, setProfiles] = useState<ProfileRow[]>([]);
  const [profileId, setProfileId] = useState<string | null>(null);
  const [etag, setEtag] = useState<string | null>(null);
  const [version, setVersion] = useState(0);
  const [lifecycle, setLifecycle] = useState("saved");
  const [draft, setDraft] = useState<EditorDraft>(EMPTY_DRAFT);
  const [dirty, setDirty] = useState(false);
  const [subscriber, setSubscriber] = useState<SubscriberView | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [offerReload, setOfferReload] = useState(false);
  const [provisionNote, setProvisionNote] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  function showFailure(status: number, body: unknown) {
    const mapped = messageForApiError(readFailure(status, body));
    setError(mapped.text);
    setOfferReload(mapped.offerReload);
    if (status === 401) {
      clearCsrf();
      setUser(null);
      setPhase("anon");
    }
  }

  function applyProfile(row: ProfileRow | undefined) {
    if (!row) {
      setProfileId(null);
      setEtag(null);
      setVersion(0);
      setLifecycle("saved");
      setDraft(EMPTY_DRAFT);
      setDirty(false);
      return;
    }
    setProfileId(row.id);
    setEtag(row.version_etag);
    setVersion(row.desired_version);
    setLifecycle(row.lifecycle);
    setDraft(draftFromContent(row.content));
    setDirty(false);
  }

  const loadSubscriber = useCallback(async (id: string) => {
    const result = await requestJson(apiBase, `/api/assignments/${id}/subscriber`);
    if (result.status !== 200) {
      showFailure(result.status, result.body);
      setSubscriber(null);
      return result.status !== 401;
    }
    setSubscriber(stripSecrets(result.body) as SubscriberView);
    return true;
  }, [apiBase]);

  const loadWorkspace = useCallback(
    async (preferredId?: string) => {
      const listed = await requestJson(apiBase, "/api/assignments");
      if (listed.status !== 200) {
        showFailure(listed.status, listed.body);
        return listed.status !== 401;
      }
      const rows = (listed.body as Assignment[]) ?? [];
      setAssignments(rows);
      const nextId = preferredId && rows.some((row) => row.id === preferredId) ? preferredId : (rows[0]?.id ?? "");
      setAssignmentId(nextId);
      const profileResult = await requestJson(apiBase, "/api/profiles");
      if (profileResult.status !== 200) {
        showFailure(profileResult.status, profileResult.body);
        return profileResult.status !== 401;
      }
      const found = (profileResult.body as ProfileRow[]) ?? [];
      setProfiles(found);
      applyProfile(found.filter((row) => row.assignment_id === nextId).at(-1));
      if (!nextId) {
        setSubscriber(null);
        return true;
      }
      return loadSubscriber(nextId);
    },
    [apiBase, loadSubscriber],
  );

  useEffect(() => {
    let cancel = false;
    requestJson(apiBase, "/api/auth/me")
      .then(async (result) => {
        if (cancel) {
          return;
        }
        if (result.status === 401) {
          setPhase("anon");
          return;
        }
        if (result.status !== 200) {
          showFailure(result.status, result.body);
          setPhase("anon");
          return;
        }
        setUser(result.body as SessionUser);
        const opened = await loadWorkspace();
        if (!cancel && opened) {
          setPhase("ready");
        }
      })
      .catch(() => {
        if (!cancel) {
          setError("Permintaan ke API gagal.");
          setPhase("anon");
        }
      });
    return () => {
      cancel = true;
    };
  }, [apiBase, loadWorkspace]);

  function update<K extends keyof EditorDraft>(key: K, value: EditorDraft[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
    setDirty(true);
    setLifecycle("saved");
    setProvisionNote(null);
  }

  function selectAssignment(id: string) {
    setAssignmentId(id);
    setError(null);
    setOfferReload(false);
    setProvisionNote(null);
    applyProfile(profiles.filter((row) => row.assignment_id === id).at(-1));
    void loadSubscriber(id);
  }

  async function onSave() {
    const local = clientDraftError(draft);
    if (local) {
      setError(local);
      setOfferReload(false);
      return;
    }
    if (!assignmentId) {
      setError("Tidak ada assignment untuk akun ini.");
      return;
    }
    setBusy(true);
    setError(null);
    const content = draftToContent(draft);
    const result = profileId
      ? await requestJson(apiBase, `/api/profiles/${profileId}`, {
          method: "PUT",
          csrf: readCsrf(),
          etag,
          body: content,
        })
      : await requestJson(apiBase, "/api/profiles", {
          method: "POST",
          csrf: readCsrf(),
          body: { assignment_id: assignmentId, content },
        });
    setBusy(false);
    if (result.status !== 200 && result.status !== 201) {
      showFailure(result.status, result.body);
      return;
    }
    const saved = result.body as ProfileRow;
    setProfiles((current) => {
      const rest = current.filter((row) => row.id !== saved.id);
      return [...rest, saved];
    });
    applyProfile(saved);
    setProvisionNote(null);
  }

  async function onValidate() {
    if (!profileId || !etag || dirty) {
      setError("Simpan draf dulu, lalu validasi.");
      return;
    }
    setBusy(true);
    const result = await requestJson(apiBase, `/api/profiles/${profileId}/validate`, {
      method: "POST",
      csrf: readCsrf(),
      etag,
      body: {},
    });
    setBusy(false);
    if (result.status !== 200) {
      showFailure(result.status, result.body);
      return;
    }
    applyProfile(result.body as ProfileRow);
    setError(null);
    setOfferReload(false);
  }

  async function onProvision() {
    if (!profileId || !etag || lifecycle !== "validated" || dirty) {
      setError("Validasi draf dulu sebelum menulis subscriber.");
      return;
    }
    setBusy(true);
    const result = await requestJson(apiBase, `/api/profiles/${profileId}/provision`, {
      method: "POST",
      csrf: readCsrf(),
      etag,
      body: {},
    });
    setBusy(false);
    const record = asRecord(result.body);
    if (result.status !== 200 || record?.status !== "written") {
      showFailure(result.status, result.body);
      setProvisionNote(null);
      return;
    }
    setProvisionNote(
      "Perubahan berlaku setelah UE attach ulang atau menyambungkan lagi PDN-nya. Perubahan ini tidak diterapkan pada sesi yang sedang hidup.",
    );
    setError(null);
    setOfferReload(false);
    await loadSubscriber(assignmentId);
  }

  async function onRollback() {
    if (!profileId || !etag || version < 2) {
      setError("Belum ada versi sebelumnya untuk dipulihkan.");
      return;
    }
    setBusy(true);
    const result = await requestJson(apiBase, `/api/profiles/${profileId}/rollback`, {
      method: "POST",
      csrf: readCsrf(),
      etag,
      idempotencyKey: crypto.randomUUID(),
      body: { to_version: version - 1 },
    });
    setBusy(false);
    const record = asRecord(result.body);
    const profile = record?.profile as ProfileRow | undefined;
    if (!profile || record?.error) {
      showFailure(result.status, result.body);
      return;
    }
    applyProfile(profile);
    setProfiles((current) => current.map((row) => (row.id === profile.id ? profile : row)));
    setProvisionNote(
      "Versi sebelumnya ditulis ke dokumen subscriber. UE perlu attach ulang atau menyambungkan lagi PDN-nya. Sesi yang sedang hidup tidak berubah.",
    );
    setError(null);
    setOfferReload(false);
    await loadSubscriber(assignmentId);
  }

  async function logout() {
    try {
      await requestJson(apiBase, "/api/auth/logout", { method: "POST", csrf: readCsrf(), body: {} });
    } catch {
      /* local session still ends */
    }
    clearCsrf();
    setUser(null);
    setPhase("anon");
  }

  const account = user ? (
    <span className="meta">
      <span data-testid="account-email">{user.email}</span>
      <span className="role-badge" data-testid="account-role">
        {user.role}
      </span>
      <button className="btn ghost" type="button" onClick={() => void logout()}>
        Keluar
      </button>
    </span>
  ) : (
    <a href="/login">Masuk</a>
  );

  const selected = assignments.find((row) => row.id === assignmentId);
  const sessions = subscriber?.sessions ?? [];

  return (
    <Shell active="/profil" mode="api" account={account}>
      {phase === "anon" ? (
        <LoginForm
          apiBase={apiBase}
          onSuccess={(next) => {
            setUser(next);
            void loadWorkspace().then((opened) => {
              if (opened) {
                setPhase("ready");
              }
            });
          }}
        />
      ) : null}
      {phase === "loading" ? <p className="note">Memeriksa sesi…</p> : null}
      {phase === "ready" ? (
        <>
          <h1>Editor profil PCRF</h1>
          <p className="sub">
            Tulisan ini mengubah dokumen subscriber untuk attach berikutnya. Bukan sesi yang sedang hidup, dan bukan Gx RAR.
          </p>
          <div className="profile-header">
            <label className="field">
              Assignment
              <select className="box" value={assignmentId} onChange={(event) => selectAssignment(event.target.value)}>
                {assignments.length === 0 ? <option value="">Tidak ada assignment</option> : null}
                {assignments.map((row) => (
                  <option key={row.id} value={row.id}>
                    {row.imsi}
                  </option>
                ))}
              </select>
            </label>
            <div className="ph-block">
              <div className="k">imsi</div>
              <div className="v mono">{selected?.imsi ?? "—"}</div>
            </div>
            <div className="ph-block">
              <div className="k">lifecycle</div>
              <div className="v">{lifecycle}</div>
            </div>
          </div>
          <div className="split">
            <form
              className="panel"
              noValidate
              onSubmit={(event) => {
                event.preventDefault();
                void onSave();
              }}
            >
              <h2>Form intent</h2>
              <div className="fields">
                <label className="field">
                  APN
                  <input className="box mono" value={draft.apn} onChange={(event) => update("apn", event.target.value)} />
                </label>
                <label className="field">
                  Label slice contoh
                  <input
                    className="box"
                    value={draft.logicalSlice}
                    onChange={(event) => update("logicalSlice", event.target.value)}
                  />
                </label>
                <label className="field">
                  QCI
                  <input
                    className="box mono"
                    type="number"
                    min={5}
                    max={9}
                    value={draft.qci}
                    onChange={(event) => update("qci", Number(event.target.value))}
                  />
                </label>
                <label className="field">
                  ARP
                  <input
                    className="box mono"
                    type="number"
                    min={1}
                    max={15}
                    value={draft.arpPriority}
                    onChange={(event) => update("arpPriority", Number(event.target.value))}
                  />
                </label>
                <label className="field">
                  AMBR uplink (mbps)
                  <input
                    className="box mono"
                    type="number"
                    min={1}
                    value={draft.ambrUl}
                    onChange={(event) => update("ambrUl", Number(event.target.value))}
                  />
                </label>
                <label className="field">
                  AMBR downlink (mbps)
                  <input
                    className="box mono"
                    type="number"
                    min={1}
                    value={draft.ambrDl}
                    onChange={(event) => update("ambrDl", Number(event.target.value))}
                  />
                </label>
                <label className="field span2">
                  Flow PCC (CIDR)
                  <input
                    className="box mono"
                    value={draft.flowPattern}
                    onChange={(event) => update("flowPattern", event.target.value)}
                  />
                </label>
                <div className="field">
                  <span>Ki / OPc</span>
                  <div className="box ro">tidak ditampilkan</div>
                </div>
              </div>
              {error ? (
                <p className="note" role="alert" data-testid="profile-error">
                  {error}
                </p>
              ) : null}
              {offerReload ? (
                <button className="btn secondary" type="button" onClick={() => void loadWorkspace(assignmentId)}>
                  Muat ulang
                </button>
              ) : null}
              <div className="actions">
                <button className="btn secondary" type="submit" disabled={busy}>
                  Simpan draf
                </button>
                <button className="btn secondary" type="button" disabled={busy || dirty || !profileId} onClick={() => void onValidate()}>
                  Validasi
                </button>
                <button
                  className="btn primary"
                  type="button"
                  disabled={busy || dirty || lifecycle !== "validated"}
                  onClick={() => void onProvision()}
                >
                  Tulis subscriber
                </button>
                <button className="btn secondary" type="button" disabled={busy || version < 2} onClick={() => void onRollback()}>
                  Pulihkan versi sebelumnya
                </button>
                <button className="btn secondary" type="button" disabled data-testid="phase2-apply">
                  Fase 2 (Gate D)
                </button>
              </div>
              <p className="apply-note" data-testid="provision-note">
                {provisionNote ?? "Tulis subscriber tidak mendorong sesi yang sedang hidup."}
              </p>
            </form>
            <section className="panel" aria-label="Subscriber tersimpan" data-testid="subscriber-view">
              <h2>Dokumen subscriber</h2>
              <p className="note">Hanya QCI, ARP, AMBR, dan PCC rule milik dashboard. Field security tidak ditampilkan.</p>
              {sessions.length === 0 ? <p className="note">Belum ada sesi yang bisa dibaca.</p> : null}
              {sessions.map((session) => (
                <div className="state-card" key={session.name ?? "session"}>
                  <h3>{session.name ?? "session"}</h3>
                  <div className="row">
                    <span>QCI</span>
                    <span className="mono">{session.qci ?? "—"}</span>
                  </div>
                  <div className="row">
                    <span>ARP</span>
                    <span className="mono">{session.arp?.priority ?? "—"}</span>
                  </div>
                  <div className="row">
                    <span>AMBR uplink</span>
                    <span className="mono">{bitrateText(session.ambr_ul)}</span>
                  </div>
                  <div className="row">
                    <span>AMBR downlink</span>
                    <span className="mono">{bitrateText(session.ambr_dl)}</span>
                  </div>
                  <ul>
                    {(session.pcc_rules ?? [])
                      .filter((rule) => rule.owned)
                      .map((rule) => (
                        <li key={`${rule.qci}-${rule.flows?.[0]?.description ?? "flow"}`}>
                          <span className="mono">{rule.flows?.map((flow) => flow.description).filter(Boolean).join(", ") || "tanpa flow"}</span>
                        </li>
                      ))}
                  </ul>
                </div>
              ))}
            </section>
          </div>
        </>
      ) : null}
    </Shell>
  );
}
