import type { ReactNode } from "react";

const LINKS = [
  { href: "/", label: "Eksperimen", hint: "Overview / intended vs observed" },
  { href: "/profil", label: "Profil PCRF", hint: "Editor intent + apply" },
  { href: "/emulator", label: "Emulator", hint: "Layar UE, bukan kontrol core" },
  { href: "/audit", label: "Audit", hint: "Status apply, bukan bukti sesi" },
];

export function Shell({
  active,
  mode,
  account,
  children,
}: {
  active: string;
  mode: "demo" | "api";
  account?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="page">
      <a className="skip" href="#isi">
        Loncat ke isi
      </a>
      <header className="topbar">
        <div className="brand">Dashboard lab 5G · Open5GS EPC CUPS</div>
        <div className="meta">
          <span className="role-badge">Mode: {mode === "demo" ? "Demo" : "API"}</span>
          {account ?? <span className="pill warn">{mode === "demo" ? "Bukan sesi" : "Sesi mengikuti cookie API"}</span>}
        </div>
      </header>
      <nav className="nav" aria-label="Navigasi utama">
        <div className="section-label">Utama</div>
        {LINKS.map((link) => (
          <span key={link.href}>
            <a className={link.href === active ? "active" : undefined} href={link.href} aria-current={link.href === active ? "page" : undefined}>
              {link.label}
            </a>
            <div className="hint">{link.hint}</div>
          </span>
        ))}
        <div className="section-label">Lainnya</div>
        <span className="nav-disabled" aria-disabled="true">
          Admin
        </span>
        <div className="hint">Kontrol core global tidak tersedia di scaffold ini</div>
      </nav>
      <main className="main" id="isi">
        {children}
      </main>
    </div>
  );
}
