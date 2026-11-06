export type Lifecycle = "saved" | "validated" | "rejected" | "unknown";

export type Draft = {
  apn: string;
  logicalSlice: string;
  qci: number;
  arpPriority: number;
  preemptionCapability: "may_preempt" | "not_preempt";
  preemptionVulnerability: "preemptable" | "not_preemptable";
  ambrUl: number;
  ambrDl: number;
  mbrUl: number;
  mbrDl: number;
  gbrUl: number;
  gbrDl: number;
  unit: "mbps";
  rulePattern: string;
  ruleAppId: string;
  lifecycle: Lifecycle;
};

export type ApplyReason = {
  op: string;
  capability: string;
  reason: string;
};

export type ApplyResult = {
  status: "rejected";
  executed: false;
  core_restart: false;
  data_origin: "demo" | "api";
  reasons: ApplyReason[];
};

export type DashboardClient = {
  mode: "demo" | "api";
  validate(draft: Draft): Promise<{ draft: Draft; error: string | null }>;
  apply(draft: Draft, appliedQci: number | null): Promise<ApplyResult>;
};
