# UX pack siap commit (untuk Soft Arch)

Hidayat: simpan hasil ke repo + push GitHub. **UX Designer tidak push.** Soft Arch commit dari pack ini.

## Pack siap salin

**Root pack:** `/workspace/ux/`

```
ux/
  README.md          ← source-of-truth map (baca dulu)
  hifi/              ← FINAL UI implementation source
  prototype/         ← interactive client-side demo
  wireframes/        ← approved lo-fi archive
```

Disarankan path di `github.com/dayat81/open5g`: `docs/ux/` (atau `ux/`).

## Alternatif path asli di box (sama isinya)

- `/workspace/ux-hifi/`
- `/workspace/ux-prototype/`
- `/workspace/ux-wireframes/`

Pack `/workspace/ux/` = salinan self-contained + path relatif (lebih aman untuk repo).

## Cek sanitasi

- Tidak ada Ki/OPc/secret/password/API key
- IMSI contoh tersensor
- Mock data only

## Setelah commit

Konfirmasi ke UX Designer / PM branch+PR bila perlu. Frontend app Next.js tetap Soft Arch.
