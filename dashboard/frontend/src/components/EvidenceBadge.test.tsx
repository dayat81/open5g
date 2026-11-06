import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { AppliedVersion, EvidenceBadge } from "./EvidenceBadge";

describe("EvidenceBadge", () => {
  it("uses lifecycle-active for session-proven active and applied only for pushed", () => {
    const active = render(<EvidenceBadge state="active" />);
    const activeBadge = active.container.querySelector(".badge");
    expect(activeBadge?.classList.contains("lifecycle-active")).toBe(true);
    expect(activeBadge?.classList.contains("applied")).toBe(false);

    const pushed = render(<EvidenceBadge state="pushed" />);
    const pushedBadge = pushed.container.querySelector(".badge");
    expect(pushedBadge?.classList.contains("applied")).toBe(true);
    expect(pushedBadge?.classList.contains("lifecycle-active")).toBe(false);
  });

  it("keeps the applied version on the applied surface", () => {
    const view = render(<AppliedVersion version="v2" />);
    const node = view.getByTestId("applied-version");
    expect(node.classList.contains("applied")).toBe(true);
    expect(node.textContent).toContain("applied v2");
  });
});
