export type ApiFailure = {
  status: number;
  code?: string;
  message?: string;
};

export type MappedError = {
  text: string;
  offerReload: boolean;
};

const VALIDATION: Record<string, string> = {
  default_bearer_qci_forbidden: "QCI default bearer harus 5–9.",
  invalid_arp: "ARP harus 1–15.",
  ambr_not_positive: "AMBR harus lebih dari 0.",
  bitrate_unit_unsupported: "Satuan bitrate tidak dikenal.",
  bitrate_not_representable: "Nilai bitrate tidak bisa disimpan.",
  invalid_profile: "Isi profil tidak lolos validasi.",
  invalid_apn: "APN harus label pendek.",
  gbr_on_non_gbr_qci: "Default bearer non-GBR tidak boleh membawa GBR.",
  subscriber_not_seeded: "IMSI uji belum ada di Mongo. Dashboard tidak membuat subscriber baru.",
};

export function messageForApiError(failure: ApiFailure): MappedError {
  const code = failure.code ?? "";
  if (code === "subscriber_not_seeded") {
    return { text: VALIDATION.subscriber_not_seeded, offerReload: false };
  }
  if (code === "subscriber_store_not_configured") {
    return { text: "Penyimpanan subscriber belum dikonfigurasi. Tulisan Mongo tidak dijalankan.", offerReload: false };
  }
  if (code === "subscriber_store_unavailable") {
    return { text: "Penyimpanan subscriber tidak menjawab. Dokumen tidak ditulis.", offerReload: false };
  }
  if (code === "invalid_login") {
    return { text: "Email atau kata sandi salah.", offerReload: false };
  }
  if (failure.status === 401 || code === "unauthenticated") {
    return { text: "Sesi tidak ada atau sudah habis. Masuk lagi.", offerReload: false };
  }
  if (failure.status === 403 || code === "admin_profile_control_forbidden" || code === "cross_group_forbidden") {
    if (code === "admin_profile_control_forbidden") {
      return { text: "Admin tidak boleh mengubah profil PCRF.", offerReload: false };
    }
    if (code === "cross_group_forbidden") {
      return { text: "Akses ditolak. Assignment ini di luar grup Anda.", offerReload: false };
    }
    if (code === "csrf_required") {
      return { text: "Token CSRF tidak ada. Muat ulang halaman, lalu masuk lagi.", offerReload: true };
    }
    if (code === "not_owner") {
      return { text: "IMSI ini bukan milik akun yang sedang masuk.", offerReload: false };
    }
    return { text: "Akses ditolak.", offerReload: false };
  }
  if (failure.status === 409) {
    if (code === "not_validated") {
      return { text: "Validasi draf dulu sebelum menulis subscriber.", offerReload: false };
    }
    if (code === "version_conflict" || code === "subscriber_conflict" || code === "stale_generation") {
      return {
        text: "Data berubah sebelum disimpan (etag, subscriber, atau generation). Muat ulang, lalu coba lagi.",
        offerReload: true,
      };
    }
    return { text: "Konflik data. Muat ulang, lalu coba lagi.", offerReload: true };
  }
  if (failure.status === 422 || code in VALIDATION) {
    return { text: VALIDATION[code] ?? "Isi profil tidak lolos validasi.", offerReload: false };
  }
  return {
    text: failure.message ? `Permintaan ditolak: ${failure.message}` : "Permintaan ditolak.",
    offerReload: false,
  };
}
