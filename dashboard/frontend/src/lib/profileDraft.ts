export type EditorDraft = {
  apn: string;
  logicalSlice: string;
  qci: number;
  arpPriority: number;
  ambrUl: number;
  ambrDl: number;
  flowPattern: string;
};

const LABEL = /^[a-z0-9][a-z0-9.-]{0,62}$/;
const CIDR = /^\d{1,3}(\.\d{1,3}){3}\/\d{1,2}$/;

export const EMPTY_DRAFT: EditorDraft = {
  apn: "internet",
  logicalSlice: "slice-class-a",
  qci: 6,
  arpPriority: 5,
  ambrUl: 50,
  ambrDl: 100,
  flowPattern: "203.0.113.0/24",
};

export function clientDraftError(draft: EditorDraft): string | null {
  if (!LABEL.test(draft.apn)) {
    return "APN harus label pendek (huruf kecil, angka, titik, atau strip).";
  }
  if (!LABEL.test(draft.logicalSlice)) {
    return "Label slice contoh tidak valid.";
  }
  if (!Number.isInteger(draft.qci) || draft.qci < 5 || draft.qci > 9) {
    return "QCI harus 5–9.";
  }
  if (!Number.isInteger(draft.arpPriority) || draft.arpPriority < 1 || draft.arpPriority > 15) {
    return "ARP harus 1–15.";
  }
  if (!(draft.ambrUl > 0) || !(draft.ambrDl > 0)) {
    return "AMBR harus lebih dari 0.";
  }
  if (draft.flowPattern && !CIDR.test(draft.flowPattern)) {
    return "Flow PCC harus jaringan IP, misalnya 203.0.113.0/24.";
  }
  return null;
}

export function draftToContent(draft: EditorDraft) {
  const rules = draft.flowPattern
    ? [
        {
          match_type: "ip",
          pattern: draft.flowPattern,
          app_id: "flow-1",
          logical_slice: draft.logicalSlice,
          enabled: true,
          precedence: 20,
        },
      ]
    : [];
  return {
    apn: draft.apn,
    logical_slice_template: draft.logicalSlice,
    qci: draft.qci,
    arp: {
      priority: draft.arpPriority,
      preemption_capability: "not_preempt",
      preemption_vulnerability: "not_preemptable",
    },
    ambr_ul: { value: draft.ambrUl, unit: "mbps" },
    ambr_dl: { value: draft.ambrDl, unit: "mbps" },
    mbr_ul: { value: draft.ambrUl, unit: "mbps" },
    mbr_dl: { value: draft.ambrDl, unit: "mbps" },
    gbr_ul: { value: 0, unit: "mbps" },
    gbr_dl: { value: 0, unit: "mbps" },
    app_rules: rules,
  };
}

type StoredBitrate = { value?: number; unit?: string };
type StoredRule = { match_type?: string; pattern?: string; enabled?: boolean };

export function draftFromContent(content: unknown): EditorDraft {
  const record = content && typeof content === "object" ? (content as Record<string, unknown>) : {};
  const arp = record.arp && typeof record.arp === "object" ? (record.arp as { priority?: number }) : {};
  const ul = record.ambr_ul && typeof record.ambr_ul === "object" ? (record.ambr_ul as StoredBitrate) : {};
  const dl = record.ambr_dl && typeof record.ambr_dl === "object" ? (record.ambr_dl as StoredBitrate) : {};
  const rules = Array.isArray(record.app_rules) ? (record.app_rules as StoredRule[]) : [];
  const flow = rules.find((rule) => rule.enabled !== false && rule.match_type === "ip" && rule.pattern);
  return {
    apn: typeof record.apn === "string" ? record.apn : EMPTY_DRAFT.apn,
    logicalSlice: typeof record.logical_slice_template === "string" ? record.logical_slice_template : EMPTY_DRAFT.logicalSlice,
    qci: typeof record.qci === "number" ? record.qci : EMPTY_DRAFT.qci,
    arpPriority: typeof arp.priority === "number" ? arp.priority : EMPTY_DRAFT.arpPriority,
    ambrUl: typeof ul.value === "number" ? ul.value : EMPTY_DRAFT.ambrUl,
    ambrDl: typeof dl.value === "number" ? dl.value : EMPTY_DRAFT.ambrDl,
    flowPattern: flow?.pattern ?? "",
  };
}
