import Image from "next/image";
import { CoreStatusPanel } from "./CoreStatusPanel";
import { DemoBanner } from "./DemoBanner";
import { EvidenceBadge } from "./EvidenceBadge";
import { Shell } from "./Shell";

const NODES = [
  ["ue.svg", "UE"],
  ["enb.svg", "eNB"],
  ["sgw.svg", "SGW"],
  ["pgw-c-smf.svg", "SMF / PGW-C"],
  ["upf-pgw-u.svg", "UPF / PGW-U"],
  ["pcrf.svg", "PCRF"],
];

export function OverviewScreen({ mode = "demo", apiBase }: { mode?: "demo" | "api"; apiBase?: string }) {
  return (
    <Shell active="/" mode={mode}>
      {mode === "demo" ? <DemoBanner /> : null}
      <h1>Overview lab + slice / APN</h1>
      <p className="sub">
        Scope contoh: IMSI yang ditugaskan server. Intent, applied, dan measured tetap terpisah. EN-DC Option 3x
        dengan SgNB terpisah adalah target, bukan hasil yang diterima.
      </p>
      <div className="banner">
        <span className="us-tag">PRD v0.6</span>
        Primary apply = Gx RAR per operasi. RAA ACK bukan Active. Adapter stock menolak QCI/ARP pada bearer yang sudah ada dan APN-AMBR.
      </div>
      <div className="cards">
        <div className="card unknown">
          <div className="k">Sesi terukur</div>
          <div className="v">—</div>
          <div className="s">unknown · bukan nol</div>
        </div>
        <div className="card">
          <div className="k">IMSI contoh</div>
          <div className="v" style={{ fontSize: 14 }}>
            001…001
          </div>
          <div className="s">bukan assignment sungguhan</div>
        </div>
        <div className="card unknown">
          <div className="k">Adapter</div>
          <div className="v">reject</div>
          <div className="s">immediate apply tidak terintegrasi</div>
        </div>
        <div className="card unknown">
          <div className="k">EN-DC</div>
          <div className="v" style={{ fontSize: 14 }}>
            WIP
          </div>
          <div className="s">Gate B integrated cell tidak diterima</div>
        </div>
      </div>
      <section className="panel" aria-label="Topologi EPC">
        <h2>Topologi contoh</h2>
        <div className="legend-row">
          {NODES.map(([file, label]) => (
            <div className="legend-item" key={file}>
              <Image className="node-icon" src={`/icons/${file}`} alt="" width={24} height={24} />
              <span>{label}</span>
            </div>
          ))}
        </div>
        <p className="note">S1-U menuju SGW-U, S5/S8-U menuju PGW-U, SGi keluar. N3/N6/N4 dan PCF bukan jalur ini.</p>
      </section>
      <CoreStatusPanel mode={mode} apiBase={apiBase} />
      <section className="panel" aria-label="Kelas status">
        <h2>Kelas status</h2>
        <EvidenceBadge state="saved" />
        <EvidenceBadge state="pushed" />
        <span className="note">Active tidak dirender di sini karena tidak ada bukti sesi.</span>
        <EvidenceBadge state="unknown" />
        <EvidenceBadge state="rejected" />
      </section>
    </Shell>
  );
}
