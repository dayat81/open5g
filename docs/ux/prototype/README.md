# Prototype UX interaktif · Dashboard lab 5G

**Client-side only.** Prototype demo, **bukan** aplikasi produksi Next.js/FastAPI, **bukan** implementasi Soft Arch, dan **tidak terhubung ke PCRF/Open5GS**. Bahasa UI: Indonesia; target demo: 1280px.

## Buka offline

1. Buka **`index.html`** langsung di Chrome/Firefox/Edge dengan double-click. Tidak perlu server, `npm install`, build, atau internet.
2. Pertahankan seluruh folder bersama-sama; semua referensi CSS, JavaScript, dan ikon bersifat relatif.
3. Data mock disimpan di `localStorage` dengan key `hidayat-5g-lab-ux-prototype-v1`. Data terpisah per browser/origin (membuka salinan path berbeda dapat dianggap origin berbeda oleh browser).
4. Gunakan **Reset demo** untuk kembali ke draft v3, Applied v2, dan kondisi awal.

Jika kebijakan browser membatasi `localStorage` pada `file://`, UI tetap mencoba bekerja di memori, tetapi data tidak dijamin bertahan setelah reload/pindah halaman. Pada Chrome yang diuji, alur offline dengan dua file lokal berfungsi.

## File

- `../prototype/index.html` — Overview interaktif, KPI, tabel RAR, PCC dan usage provenance.
- `../prototype/editor.html` — form Intent, app_rules editor, Save draft dan dialog Apply.
- `../prototype/app.js` — state localStorage, render bersama, validasi, save/apply/fallback, toast, dialog & audit.
- `../prototype/proto.css` — affordance interaktif dan modal saja.
- `../prototype/tokens.css`, `components.css`, `icons/` — **salinan** aset FINAL hi-fi agar self-contained.
- `../prototype/overview-demo.png` — tangkapan layar Overview pada 1280px (kondisi awal).
- `../prototype/README.md` — dokumen ini.

Sumber `../hifi/` dan `../wireframes/` hanya dibaca, tidak diubah.

## Demo 5 langkah (sukses + reject + akses)

1. **Tambah rule & simpan.** Buka `index.html`, pilih **Edit profil IMSI**. Klik **+ Tambah rule** (default baru: IP `192.0.2.0/24`, `app_id=lab-stream`). Ubah pola/app_id bila diperlukan, lalu **Save draft**. Desired v3 menjadi v4, `version_etag` berubah. Pindah Overview lalu kembali: draft tetap ada.
2. **Apply Gx RAR simulasi.** Klik **Apply…**, baca diff dan konfirmasi **Apply via Gx RAR**. Status menjadi `queued`, lalu `pushed` setelah RAA ACK simulasi. Toast menegaskan **RAA ACK ≠ Active**; tidak ada core restart.
3. **Bukti sesi.** Buka **Eksperimen / Overview**. Tombol **Simulasikan bukti sesi** aktif. Klik tombol: baru kini status `active`, Applied/Measured bergerak ke versi job dan KPI/PCC menunjukkan bukti contoh. Active tidak otomatis berdasarkan ACK.
4. **Reject & fallback.** Kembali ke Editor; ubah **QCI** dari 6 menjadi 7 (ubah `ambr_ul/ambr_dl` untuk contoh APN-AMBR), Save draft, lalu Apply + konfirmasi. Modal **Immediate Apply ditolak** menampilkan capability reason. Centang konfirmasi untuk mengaktifkan **Confirm re-attach fallback**, klik, lalu berikan bukti sesi di Overview. Reattach bukan primary path.
5. **Instructor 403 & status jujur.** Di Overview klik **Kelas / Lihat demo HTTP 403**, pilih **kelas-5g-b · out-of-group**: lihat `HTTP 403 cross_group_forbidden` dan audit actor/owner/reason. Role switcher Student/Instructor tersedia untuk demo. Tutup dengan **Escape**, lalu coba **Simulasikan data stale** (bukan failed) dan **Reset demo**.

Rule SNI/hostname dapat ditambah/diubah/dihapus. Tetap ditampilkan sebagai klasifikasi eBPF/unknown; tidak disulap menjadi enforcement PCC native.

## Yang berfungsi

- Navigasi dua halaman, Admin disabled, Kelas demo, role switcher Student/Instructor, reset dialog.
- Intent editable: APN, logical_slice, QCI, seluruh field ARP, AMBR/MBR/GBR, app_rules add/edit/delete (`IP`, `hostname`, `SNI`), priority dan enabled, serta usage threshold.
- Validasi field wajib/numerik browser, GBR≤MBR per arah, pola rule/app_id tidak kosong, `app_id` wajib dan aktif hanya saat usage `scope=app`.
- Save draft ber-versi: desired_version dan random mock `version_etag` bertambah, lifecycle `saved`, draft persisten.
- Modal A: rule baru → queued → pushed → manual simulated session evidence → active.
- Modal B: modify QCI/ARP existing bearer dan APN-AMBR → reject-with-reason → konfirmasi reattach opsional → bukti sesi tetap wajib.
- Overview dan Editor merender state yang sama. KPI, PCC, lifecycle, audit lokal, applied_version dan observed_version mengikuti Apply yang telah diberi evidence.
- Empty/missing/unknown/stale/fail/fallback tidak disamarkan sebagai sukses; role badge/kontrol dan seluruh dialog dapat dipakai keyboard; modal memakai `role=dialog`, `aria-modal`, Escape, focus trap dan restore focus, serta mengunci interaksi latar.
- Tidak ada network request dari prototype.

## Simulasi vs bukan simulasi

| Bagian | Prototype ini | Bukan / tidak tersedia |
|---|---|---|
| State & versi | localStorage, transisi deterministik di JS | API/backend production, database |
| Save & Apply | Diff lokal dan penundaan `setTimeout` untuk RAR/RAA | Delivery RAR ke PCRF/PCEF |
| Active | Tombol bukti sesi memberikan event simulasi | Verifikasi UE session nyata |
| Reject/fallback | Contoh capability stock Open5GS 2.8 | Capability discovery adapter aktual |
| Sesi/KPI/PCC | Angka dan provenance mock dapat diperbarui | Telemetri PFCP/eBPF/Gx |
| Instructor | Pilihan grup, tampilan HTTP 403 dan audit mock | Authorization server / immutable audit backend |
| Retry/error browser | Toast storage error jika browser memblokir | Retry job adapter, partial/RAR timeout backend |

## Kontrak produk terjaga

- **Intent ≠ Applied ≠ Measured** dan **RAA ACK ≠ Active**.
- Apply tidak mengandung langkah Restart core atau auto-restart.
- Warna: Intent biru; Applied/pushed oranye; Active setelah bukti memakai `lifecycle-active` hijau; Measured hijau; unknown/stale/fail eksplisit.
- EPC CUPS: S1-U/S5-U/SGi/Gx/Sx. S-NSSAI ditandai n/a, kredensial subscriber tidak ditampilkan.
- usage `scope=app` menggunakan `app_id`. Gx Usage-Monitoring stock tidak diklaim.
- Semua mock ditandai sebagai contoh/unverified. Tidak ada klaim keberhasilan adapter/lab.

## Catatan untuk Soft Arch

Prototype ini untuk **ux walkthrough & validasi alur**, bukan kode yang perlu dibawa mentah ke production app. Gunakan FINAL hi-fi sebagai kontrak visual. `app.js` adalah model interaksi lokal satu-profil; bukan API contract, authorization model, job orchestration, atau message flow final. Production perlu verifikasi capability per operasi, evidence per operasi, backend group-bound audit, concurrency/etag enforcement dan error transport nyata.

### QA lokal (6 Nov 2026, Asia/Bangkok)

Chrome headless, `file://`, viewport 1280×950: navigasi offline, tambah rule, Save v4 + refresh persistence, Apply queued/pushed, evidence Active, QCI reject+fallback, HTTP 403, Escape, reset — **PASS**, tanpa error `pageerror`/console. Timeline sengaja manual pada evidence agar perbedaan ACK dan Active jelas, tanpa auto-activation tersembunyi.
