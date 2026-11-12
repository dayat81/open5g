import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { ProfileEditor } from "./ProfileEditor";
import { demoClient } from "@/lib/demo";

describe("ProfileEditor", () => {
  it("rejects immediate apply in demo mode and does not show Active", async () => {
    const user = userEvent.setup();
    render(<ProfileEditor client={demoClient} />);
    expect(screen.getByTestId("demo-banner").textContent).toMatch(/mode demo/i);
    await user.click(screen.getByRole("button", { name: "Validasi draft" }));
    await user.click(screen.getByRole("button", { name: "Apply…" }));
    await user.click(screen.getByRole("button", { name: "Ajukan apply" }));
    const result = screen.getByTestId("apply-result");
    expect(result.textContent).toContain("apn_ambr_rar");
    expect(result.textContent).toContain("rejected");
    expect(result.querySelector(".lifecycle-active")).toBeNull();
    expect(result.textContent).not.toContain("Active");
  });

  it("names the unsupported QCI change when the example applied QCI differs", async () => {
    const user = userEvent.setup();
    render(<ProfileEditor client={demoClient} />);
    const qci = screen.getByRole("spinbutton", { name: "QCI" });
    await user.clear(qci);
    await user.type(qci, "7");
    await user.click(screen.getByRole("button", { name: "Validasi draft" }));
    await user.click(screen.getByRole("button", { name: "Apply…" }));
    await user.click(screen.getByRole("button", { name: "Ajukan apply" }));
    expect(screen.getByTestId("apply-result").textContent).toContain("modify_qci_existing_bearer");
  });

  it("does not write Mongo in demo mode and shows the refusal", async () => {
    const user = userEvent.setup();
    render(<ProfileEditor client={demoClient} />);
    await user.click(screen.getByRole("button", { name: "Tulis subscriber" }));
    expect(screen.getByRole("alert").textContent).toMatch(/tidak menulis ke MongoDB/i);
    expect(screen.getByTestId("provision-result").textContent).not.toMatch(/ditulis untuk attach/);
  });

  it("shows a provision error returned by the API client", async () => {
    const user = userEvent.setup();
    render(
      <ProfileEditor
        client={{
          ...demoClient,
          mode: "api",
          async provision() {
            return { error: "MongoDB timed out", written: false };
          },
        }}
      />,
    );
    await user.click(screen.getByRole("button", { name: "Tulis subscriber" }));
    expect(screen.getByRole("alert").textContent).toContain("MongoDB timed out");
  });
});
