import { render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { CoreStatusPanel } from "./CoreStatusPanel";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("CoreStatusPanel", () => {
  it("shows the unconfigured inventory in demo mode", () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    render(<CoreStatusPanel mode="demo" />);
    expect(screen.getByTestId("core-status").textContent).toContain("not_configured");
    expect(screen.getByTestId("nf-upf-a").textContent).toContain("not_configured");
    expect(screen.getByTestId("nf-upf-b").textContent).toContain("not_configured");
    expect(screen.getByTestId("nf-smf").textContent).toContain("not_configured");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("keeps a down SMF and the other UPF on screen", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => ({
          status: "partial",
          configured: true,
          gx_rar_enabled: false,
          gx_rar_effective: false,
          note: "One down NF does not drop the other targets.",
          targets: [
            { name: "smf", status: "down", error: "ConnectError" },
            { name: "upf-a", status: "reachable", error: null },
            { name: "upf-b", status: "down", error: "TimeoutException" },
          ],
        }),
      }),
    );
    render(<CoreStatusPanel mode="api" apiBase="http://dashboard.local" />);
    expect((await screen.findByTestId("nf-smf")).textContent).toContain("down");
    expect(screen.getByTestId("nf-upf-a").textContent).toContain("reachable");
    expect(screen.getByTestId("nf-upf-b").textContent).toContain("down");
    expect(screen.getByTestId("core-status").textContent).toContain("partial");
  });
});
