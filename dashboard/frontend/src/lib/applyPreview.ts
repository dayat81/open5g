import type { ApplyReason, ApplyResult, Draft } from "./types";

export function draftError(draft: Draft): string | null {
  if (draft.gbrUl > draft.mbrUl) {
    return "gbr_ul harus lebih kecil atau sama dengan mbr_ul";
  }
  if (draft.gbrDl > draft.mbrDl) {
    return "gbr_dl harus lebih kecil atau sama dengan mbr_dl";
  }
  if (!draft.apn.trim()) {
    return "APN wajib diisi";
  }
  return null;
}

/** UI preview of the stock reject path. The API remains authoritative in api mode. */
export function previewUnsupportedApply(draft: Draft, appliedQci: number | null): ApplyResult {
  const reasons: ApplyReason[] = [
    {
      op: "apn_ambr_rar",
      capability: "unsupported",
      reason: "stock Open5GS 2.8 immediate APN-AMBR RAR is unsupported until a verified patch exists",
    },
  ];
  if (appliedQci !== null && draft.qci !== appliedQci) {
    reasons.push({
      op: "modify_qci_existing_bearer",
      capability: "unsupported",
      reason: "stock Open5GS 2.8 immediate QCI modification of an existing bearer is unsupported",
    });
  }
  reasons.push({
    op: "gx_rar",
    capability: "not_integrated",
    reason: "No Gx RAR adapter is implemented. Immediate apply is rejected instead of reporting pushed or active.",
  });
  return {
    status: "rejected",
    executed: false,
    core_restart: false,
    data_origin: "demo",
    reasons,
  };
}
