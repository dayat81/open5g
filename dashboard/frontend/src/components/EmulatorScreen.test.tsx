import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { EmulatorScreen, type EmulatorUe } from "./EmulatorScreen";

const ue: EmulatorUe = {
  ue_id: "ue1",
  apn: "internet",
  attach_ipv4: "192.0.2.10",
  screen: "up",
  control: "self",
};

describe("EmulatorScreen", () => {
  it("shows attach status and a screen when the emulator is up", () => {
    render(
      <EmulatorScreen
        mode="api"
        ues={[ue]}
        selectedId="ue1"
        showFrame
        frameSrc="http://127.0.0.1:3301/emulator/ue1/"
        note={null}
      />,
    );
    expect(screen.getByTestId("attach-ip").textContent).toBe("192.0.2.10");
    expect(screen.getByTestId("attach-apn").textContent).toBe("internet");
    expect(screen.getByTestId("emulator-frame").getAttribute("src")).toBe("http://127.0.0.1:3301/emulator/ue1/");
    expect(screen.getByRole("button", { name: "Sambungkan ulang" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: /reset|wipe|hapus|factory/i })).toBeNull();
  });

  it("shows status only when the screen is down or busy", async () => {
    const user = userEvent.setup();
    const onReconnect = vi.fn();
    const { rerender } = render(
      <EmulatorScreen
        mode="api"
        ues={[{ ...ue, screen: "down", control: "free" }]}
        selectedId="ue1"
        showFrame
        note={null}
        onReconnect={onReconnect}
      />,
    );
    expect(screen.queryByTestId("emulator-frame")).toBeNull();
    expect(screen.getByTestId("emulator-status").textContent).toMatch(/tidak berjalan/i);
    expect(screen.getByTestId("attach-ip").textContent).toBe("192.0.2.10");
    await user.click(screen.getByRole("button", { name: "Sambungkan ulang" }));
    expect(onReconnect).toHaveBeenCalledWith("ue1");
    rerender(
      <EmulatorScreen mode="api" ues={[{ ...ue, control: "busy" }]} selectedId="ue1" showFrame note={null} />,
    );
    expect(screen.queryByTestId("emulator-frame")).toBeNull();
    expect(screen.getByTestId("emulator-status").textContent).toMatch(/dikontrol sesi lain/i);
  });

  it("does not open a screen in demo mode", () => {
    render(<EmulatorScreen mode="demo" ues={[]} selectedId={null} showFrame note="Mode demo tidak membuka layar." />);
    expect(screen.getByTestId("demo-banner")).toBeTruthy();
    expect(screen.queryByTestId("emulator-frame")).toBeNull();
    expect(screen.getByTestId("emulator-status").textContent).toMatch(/demo/i);
    expect(screen.queryByRole("button", { name: /reset|wipe|hapus|factory/i })).toBeNull();
  });
});
