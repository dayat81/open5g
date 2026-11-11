"use client";

import { useEffect, useState } from "react";
import { DemoBanner } from "./DemoBanner";
import { Shell } from "./Shell";

export type EmulatorUe = {
  ue_id: string;
  apn: string | null;
  attach_ipv4: string | null;
  screen: "up" | "down" | "disabled";
  control: "free" | "self" | "busy";
  detail?: string;
};

function readCsrf(): string {
  if (typeof document === "undefined") {
    return "";
  }
  const match = document.cookie.match(/(?:^|; )open5g_csrf=([^;]*)/);
  return match ? decodeURIComponent(match[1]) : "";
}

export function EmulatorScreen({
  mode,
  ues,
  selectedId,
  showFrame,
  note,
  onSelect,
  onReconnect,
}: {
  mode: "demo" | "api";
  ues: EmulatorUe[];
  selectedId: string | null;
  showFrame: boolean;
  note: string | null;
  onSelect?: (ueId: string) => void;
  onReconnect?: (ueId: string) => void;
}) {
  const selected = ues.find((ue) => ue.ue_id === selectedId) ?? null;
  const frame =
    mode === "api" &&
    showFrame &&
    selected !== null &&
    selected.screen === "up" &&
    selected.control !== "busy";
  return (
    <Shell active="/emulator" mode={mode}>
      {mode === "demo" ? <DemoBanner /> : null}
      <h1>Emulator</h1>
      <p className="sub">
        Layar UE lewat sesi dashboard. Alamat attach dan APN ditampilkan apa adanya. Perangkat tidak diubah dari halaman ini.
      </p>
      {ues.length > 1 ? (
        <div className="scope" role="tablist" aria-label="UE">
          {ues.map((ue) => (
            <button key={ue.ue_id} type="button" className="box" onClick={() => onSelect?.(ue.ue_id)} aria-pressed={ue.ue_id === selectedId}>
              {ue.ue_id}
            </button>
          ))}
        </div>
      ) : null}
      {selected === null ? (
        <p data-testid="emulator-status">{note ?? "Tidak ada UE pada sesi ini."}</p>
      ) : (
        <section className="panel" aria-label={`Status ${selected.ue_id}`}>
          <h2>
            {selected.ue_id}
            <span className="tag">{selected.screen === "up" ? "layar hidup" : "layar mati"}</span>
          </h2>
          <div className="cards">
            <article className="card">
              <div className="k">Alamat UE</div>
              <div className="v" data-testid="attach-ip">
                {selected.attach_ipv4 ?? "belum tercatat"}
              </div>
            </article>
            <article className="card">
              <div className="k">APN</div>
              <div className="v" data-testid="attach-apn">
                {selected.apn ?? "belum tercatat"}
              </div>
            </article>
          </div>
          <p data-testid="emulator-status">
            {note ??
              (selected.screen !== "up"
                ? "Layar emulator tidak berjalan. Hanya status yang ditampilkan."
                : selected.control === "busy"
                  ? "UE ini sedang dikontrol sesi lain."
                  : "Satu sesi kontrol. Sesi lain ditolak.")}
          </p>
          <button type="button" onClick={() => onReconnect?.(selected.ue_id)}>
            Sambungkan ulang
          </button>
          {frame ? (
            <iframe
              className="emulator-frame"
              title={`Layar ${selected.ue_id}`}
              src={`/emulator/${selected.ue_id}/`}
              data-testid="emulator-frame"
            />
          ) : null}
        </section>
      )}
    </Shell>
  );
}

export function EmulatorPage({ mode, apiBase }: { mode: "demo" | "api"; apiBase: string }) {
  const [ues, setUes] = useState<EmulatorUe[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [showFrame, setShowFrame] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const [generation, setGeneration] = useState(0);
  const root = apiBase.replace(/\/$/, "");

  useEffect(() => {
    if (mode !== "api") {
      return;
    }
    let cancel = false;
    void (async () => {
      const response = await fetch(`${root}/api/emulator`, { credentials: "include" });
      if (cancel) {
        return;
      }
      if (response.status === 401) {
        setNote("Login diperlukan.");
        setUes([]);
        setShowFrame(false);
        return;
      }
      if (!response.ok) {
        setNote("Status emulator tidak dapat dibaca.");
        setShowFrame(false);
        return;
      }
      const body = (await response.json()) as EmulatorUe[];
      if (cancel) {
        return;
      }
      setUes(body);
      setSelectedId((current) => current ?? body[0]?.ue_id ?? null);
    })();
    return () => {
      cancel = true;
    };
  }, [mode, root, generation]);

  useEffect(() => {
    if (mode !== "api" || !selectedId) {
      return;
    }
    const selected = ues.find((ue) => ue.ue_id === selectedId);
    if (!selected || selected.screen !== "up" || selected.control === "busy") {
      setShowFrame(false);
      return;
    }
    let cancel = false;
    void (async () => {
      const response = await fetch(`${root}/api/emulator/${selectedId}/session`, {
        method: "POST",
        credentials: "include",
        headers: { "x-csrf-token": readCsrf() },
      });
      if (cancel) {
        return;
      }
      if (response.status === 409) {
        setShowFrame(false);
        setNote("UE ini sedang dikontrol sesi lain.");
        return;
      }
      if (!response.ok) {
        setShowFrame(false);
        setNote("Layar emulator tidak berjalan. Hanya status yang ditampilkan.");
        return;
      }
      setNote(null);
      setShowFrame(true);
    })();
    return () => {
      cancel = true;
    };
  }, [mode, root, selectedId, ues]);

  if (mode === "demo") {
    return (
      <EmulatorScreen mode="demo" ues={[]} selectedId={null} showFrame={false} note="Mode demo tidak membuka layar." onReconnect={() => undefined} />
    );
  }

  return (
    <EmulatorScreen
      mode="api"
      ues={ues}
      selectedId={selectedId}
      showFrame={showFrame}
      note={note}
      onSelect={(ueId) => {
        setShowFrame(false);
        setNote(null);
        setSelectedId(ueId);
      }}
      onReconnect={() => {
        if (!selectedId) {
          return;
        }
        void fetch(`${root}/api/emulator/${selectedId}/session/close`, {
          method: "POST",
          credentials: "include",
          headers: { "x-csrf-token": readCsrf() },
        }).finally(() => {
          setShowFrame(false);
          setGeneration((value) => value + 1);
        });
      }}
    />
  );
}
