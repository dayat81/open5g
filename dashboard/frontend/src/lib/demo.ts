import { draftError, previewUnsupportedApply } from "./applyPreview";
import type { DashboardClient, Draft } from "./types";

export const DEMO_DRAFT: Draft = {
  apn: "internet",
  logicalSlice: "slice-class-a",
  qci: 6,
  arpPriority: 5,
  preemptionCapability: "not_preempt",
  preemptionVulnerability: "not_preemptable",
  ambrUl: 50,
  ambrDl: 100,
  mbrUl: 20,
  mbrDl: 40,
  gbrUl: 5,
  gbrDl: 10,
  unit: "mbps",
  rulePattern: "meet.example",
  ruleAppId: "video-conf",
  lifecycle: "saved",
};

/** Sample applied snapshot. It is not session evidence. */
export const DEMO_APPLIED_QCI = 6;

export const demoClient: DashboardClient = {
  mode: "demo",
  async validate(draft) {
    const error = draftError(draft);
    if (error) {
      return { draft, error };
    }
    return { draft: { ...draft, lifecycle: "validated" }, error: null };
  },
  async apply(draft, appliedQci) {
    const error = draftError(draft);
    if (error || draft.lifecycle !== "validated") {
      return {
        status: "rejected",
        executed: false,
        core_restart: false,
        data_origin: "demo",
        reasons: [
          {
            op: "not_validated",
            capability: "rejected",
            reason: error ?? "Validate the draft before immediate apply",
          },
        ],
      };
    }
    return previewUnsupportedApply(draft, appliedQci);
  },
  async provision() {
    return {
      error: "Mode demo tidak menulis ke MongoDB. Tulis subscriber hanya lewat sesi API yang sudah ada.",
      written: false,
    };
  },
};
