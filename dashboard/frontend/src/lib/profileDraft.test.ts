import { describe, expect, it } from "vitest";
import { clientDraftError, draftToContent, EMPTY_DRAFT } from "./profileDraft";

describe("clientDraftError", () => {
  it("accepts a draft inside the editor caps", () => {
    expect(clientDraftError(EMPTY_DRAFT)).toBeNull();
  });

  it("rejects QCI, ARP, and AMBR outside the editor range", () => {
    expect(clientDraftError({ ...EMPTY_DRAFT, qci: 4 })).toMatch(/QCI harus 5–9/);
    expect(clientDraftError({ ...EMPTY_DRAFT, qci: 10 })).toMatch(/QCI harus 5–9/);
    expect(clientDraftError({ ...EMPTY_DRAFT, arpPriority: 0 })).toMatch(/ARP harus 1–15/);
    expect(clientDraftError({ ...EMPTY_DRAFT, arpPriority: 16 })).toMatch(/ARP harus 1–15/);
    expect(clientDraftError({ ...EMPTY_DRAFT, ambrUl: 0, ambrDl: 10 })).toMatch(/AMBR harus lebih dari 0/);
    expect(clientDraftError({ ...EMPTY_DRAFT, ambrDl: -1 })).toMatch(/AMBR harus lebih dari 0/);
  });
});

describe("draftToContent", () => {
  it("sends non-GBR bitrate and one IP flow", () => {
    const content = draftToContent(EMPTY_DRAFT);
    expect(content.qci).toBe(6);
    expect(content.gbr_ul).toEqual({ value: 0, unit: "mbps" });
    expect(content.ambr_dl.unit).toBe("mbps");
    expect(content.app_rules[0]?.pattern).toBe("203.0.113.0/24");
    expect(JSON.stringify(content)).not.toMatch(/security|opc|ki/i);
  });
});
