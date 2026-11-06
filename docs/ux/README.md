# UX deliverables — Dashboard lab 5G

Paket desain/prototype dari **UX Designer**. Disetujui Hidayat (6 Nov 2026, Asia/Bangkok).  
**Tidak ada secret, Ki, OPc, password, atau credential.** Semua data = contoh / mock.

Soft Arch: salin ketiga folder di bawah ke repo `open5g` (mis. `docs/ux/`). Jangan commit path absolut `/workspace/…` dari mesin agent — folder ini sudah relatif.

## Source of truth

| Folder | Status | Dipakai untuk |
|--------|--------|----------------|
| **`hifi/`** | **FINAL — source of truth implementasi UI** | Design tokens, komponen CSS, ikon node, mockup hi-fi Overview + editor IMSI. Soft Arch mapping/implementasi frontend berangkat dari sini. |
| **`prototype/`** | Demo interaktif (client-side) | Klikable HTML/JS + localStorage. Bukan app produksi Next.js/FastAPI; bukan koneksi PCRF/Open5GS. |
| **`wireframes/`** | Archive lo-fi (disetujui) | Wireframe grayscale sebelum hi-fi. Jangan dipakai sebagai kontrak visual terbaru. |

Prioritas jika konflik: **`hifi/` > `prototype/` visual tokens > `wireframes/`**.

## Isi singkat

### hifi/
- `tokens.css`, `components.css`
- `01-overview-hifi.html`, `02-imsi-profile-editor-hifi.html`, `design-system.html`
- `icons/` (ue, enb, sgw, pgw-c-smf, upf-pgw-u, pcrf)
- `README.md`, `CHANGELOG.md`

Evidence colors: Intent `#2563eb` · Applied `#c2410c` · Measured `#16803c` · Fail `#dc2626` · Unknown `#71717a` · Stale `#a16207`.  
Active (bukti sesi) = class `lifecycle-active` (bukan `applied`). `applied` = pushed/installed saja.

### prototype/
- Entry: `index.html` → `editor.html`
- `app.js`, `proto.css`, salinan tokens/components/icons
- Demo: Save draft, Apply Gx RAR (`pushed` lalu Active setelah bukti sesi), reject QCI/AMBR + re-attach, HTTP 403 `cross_group_forbidden`

### wireframes/
- `01-overview-lofi.html`, `02-imsi-profile-editor-lofi.html`
- Aligned PRD v0.4 + Soft Arch closing (archive)

## Aturan produk (ringkas)

- Intent ≠ Applied ≠ Measured · RAA ACK ≠ Active
- Apply primary = Gx RAR; tidak auto-restart core
- Capability per operasi (Open5GS 2.8 stock: new PCC OK contoh; modify QCI/ARP existing + APN-AMBR = reject)
- Instructor edit/apply IMSI student in-group saja; out-of-group = 403 `cross_group_forbidden`
- Label EPC: S1-U / S5-U / SGi / Gx / Sx — jangan N3/N4/N6
- Mock spec only / bukan bukti adapter

## Sanitasi

- Tidak ada Ki/OPc di UI (tersembunyi / out of scope)
- IMSI contoh disensor (`510…789`)
- Tidak ada API key, password, private key, atau endpoint lab rahasia

## Pemilik

- Desain / prototype: UX Designer
- Implementasi frontend app: Software Architect
- PRD: Product Manager
