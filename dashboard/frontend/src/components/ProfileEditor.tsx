"use client";

import { useState } from "react";
import { DemoBanner } from "./DemoBanner";
import { AppliedVersion, EvidenceBadge } from "./EvidenceBadge";
import { Shell } from "./Shell";
import { DEMO_APPLIED_QCI, DEMO_DRAFT, demoClient } from "@/lib/demo";
import type { ApplyResult, DashboardClient, Draft } from "@/lib/types";

export function ProfileEditor({ client = demoClient }: { client?: DashboardClient }) {
  const [draft, setDraft] = useState<Draft>(DEMO_DRAFT);
  const [error, setError] = useState<string | null>(null);
  const [provisionNote, setProvisionNote] = useState<string | null>(null);
  const [result, setResult] = useState<ApplyResult | null>(null);
  const [confirming, setConfirming] = useState(false);

  function update<K extends keyof Draft>(key: K, value: Draft[K]) {
    setDraft((current) => ({ ...current, [key]: value, lifecycle: "saved" }));
    setResult(null);
  }

  async function onValidate() {
    const response = await client.validate(draft);
    setError(response.error);
    if (!response.error) {
      setDraft(response.draft);
    }
  }

  async function onProvision() {
    const response = await client.provision();
    setProvisionNote(response.written ? "Dokumen subscriber ditulis untuk attach berikutnya. Bukan sesi aktif." : null);
    setError(response.error);
  }

  async function onApply() {
    const response = await client.apply(draft, client.mode === "demo" ? DEMO_APPLIED_QCI : null);
    setResult(response);
    setDraft((current) => ({ ...current, lifecycle: "rejected" }));
    setConfirming(false);
  }

  return (
    <Shell active="/profil" mode={client.mode}>
      {client.mode === "demo" ? <DemoBanner /> : null}
      <h1>Editor profil PCRF · IMSI assigned</h1>
      <p className="sub">
        Form ini adalah intent. Apply segera lewat Gx RAR ditolak oleh adapter stock selama patch belum terverifikasi.
        Active tidak ditampilkan tanpa bukti sesi.
      </p>
      <div className="profile-header">
        <div className="ph-block">
          <div className="k">imsi (contoh, read-only)</div>
          <div className="v mono">001…001</div>
        </div>
        <div className="ph-block">
          <div className="k">lifecycle</div>
          <EvidenceBadge state={draft.lifecycle} />
        </div>
        <div className="ph-block">
          <div className="k">applied_version</div>
          <AppliedVersion version="v2 · contoh" />
        </div>
      </div>
      <div className="split">
        <form
          className="panel"
          onSubmit={(event) => {
            event.preventDefault();
            void onValidate();
          }}
        >
          <h2>
            <span className="dot intent" /> Form Intent
          </h2>
          <div className="fields">
            <label className="field">
              APN (EPC)
              <input className="box mono" value={draft.apn} onChange={(event) => update("apn", event.target.value)} />
            </label>
            <label className="field">
              logical slice
              <input className="box" value={draft.logicalSlice} onChange={(event) => update("logicalSlice", event.target.value)} />
            </label>
            <label className="field">
              QCI
              <input
                className="box mono"
                type="number"
                min={1}
                max={9}
                value={draft.qci}
                onChange={(event) => update("qci", Number(event.target.value))}
              />
            </label>
            <label className="field">
              arp.priority
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
              gbr_dl ({draft.unit})
              <input
                className="box mono"
                type="number"
                min={0}
                value={draft.gbrDl}
                onChange={(event) => update("gbrDl", Number(event.target.value))}
              />
            </label>
            <label className="field">
              mbr_dl ({draft.unit})
              <input
                className="box mono"
                type="number"
                min={0}
                value={draft.mbrDl}
                onChange={(event) => update("mbrDl", Number(event.target.value))}
              />
            </label>
            <div className="field">
              <span>S-NSSAI</span>
              <div className="box ro">n/a — EPC, bukan sinonim APN</div>
            </div>
            <div className="field">
              <span>Ki / OPc</span>
              <div className="box ro">tidak ditampilkan</div>
            </div>
          </div>
          {error ? (
            <p className="note" role="alert">
              {error}
            </p>
          ) : null}
          <div className="actions">
            <button className="btn secondary" type="submit">
              Validasi draft
            </button>
            <button className="btn primary" type="button" onClick={() => setConfirming(true)}>
              Apply…
            </button>
            <p className="apply-note">
              Simpan draft tidak menulis Mongo dan tidak membuat status active. Apply tetap menolak Gx RAR.
            </p>
            <button className="btn secondary" type="button" onClick={() => void onProvision()}>
              Tulis subscriber
            </button>
            <p className="apply-note" data-testid="provision-result">
              {provisionNote ?? "Tombol tulis subscriber memanggil POST /provision. Mode demo tidak menulis Mongo."}
            </p>
          </div>
        </form>
        <section className="panel" aria-label="Status apply">
          <h2>Status</h2>
          <p className="note">Intent, applied, dan measured tidak digabung menjadi satu status OK.</p>
          <div className="state-card intent">
            <h3>
              <span className="dot intent" /> Intent
            </h3>
            <div className="row">
              <span>QCI</span>
              <span className="mono">{draft.qci}</span>
            </div>
            <EvidenceBadge state={draft.lifecycle === "rejected" ? "saved" : draft.lifecycle} />
          </div>
          <div data-testid="apply-result">
            {result ? (
              <div className="state-card">
                <h3>Hasil apply</h3>
                <EvidenceBadge state="rejected" />
                <ul>
                  {result.reasons.map((reason) => (
                    <li key={reason.op}>
                      <span className="mono">{reason.op}</span> · {reason.capability}
                      <div className="note">{reason.reason}</div>
                    </li>
                  ))}
                </ul>
                <p className="note">executed={String(result.executed)} · core_restart={String(result.core_restart)} · {result.data_origin}</p>
              </div>
            ) : (
              <p className="note">Belum ada apply pada tampilan ini.</p>
            )}
          </div>
          <p className="note">Measured tetap unknown. Tidak ada bukti sesi di scaffold ini.</p>
          <span className="badge unknown">unknown</span>
        </section>
      </div>
      {confirming ? (
        <div className="modal-area" role="dialog" aria-modal="true" aria-labelledby="apply-title">
          <h3 id="apply-title">Apply ditolak jika operasi tidak didukung</h3>
          <div className="warn-box">
            Immediate apply tidak dijalankan sebagai pushed atau active. Re-attach dan restart core tidak dijalankan.
          </div>
          <div className="modal-actions">
            <button className="btn secondary" type="button" onClick={() => setConfirming(false)}>
              Batal
            </button>
            <button className="btn primary" type="button" onClick={() => void onApply()}>
              Ajukan apply
            </button>
          </div>
        </div>
      ) : null}
    </Shell>
  );
}
