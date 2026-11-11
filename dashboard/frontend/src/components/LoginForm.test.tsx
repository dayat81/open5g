import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { LoginForm } from "./LoginForm";
import { readCsrf } from "@/lib/session";

afterEach(() => {
  vi.unstubAllGlobals();
  sessionStorage.clear();
});

describe("LoginForm", () => {
  it("posts email and password and stores the CSRF token", async () => {
    const user = userEvent.setup();
    const onSuccess = vi.fn();
    const fetchMock = vi.fn().mockResolvedValue({
      status: 200,
      text: async () =>
        JSON.stringify({
          csrf_token: "csrf-from-login",
          user: { id: "u1", email: "student@example.test", display_name: "Student", role: "student", group_id: "g1" },
        }),
    });
    vi.stubGlobal("fetch", fetchMock);
    render(<LoginForm apiBase="http://dashboard.local" onSuccess={onSuccess} />);
    await user.type(screen.getByRole("textbox", { name: "Email" }), "student@example.test");
    await user.type(screen.getByLabelText("Kata sandi"), "placeholder-password");
    await user.click(screen.getByRole("button", { name: "Masuk" }));
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("http://dashboard.local/api/auth/login");
    expect(init.method).toBe("POST");
    expect(init.credentials).toBe("include");
    expect(JSON.parse(String(init.body))).toEqual({ email: "student@example.test", password: "placeholder-password" });
    expect(readCsrf()).toBe("csrf-from-login");
    expect(onSuccess).toHaveBeenCalledWith(expect.objectContaining({ role: "student" }));
  });

  it("maps a 401 login failure to an Indonesian message", async () => {
    const user = userEvent.setup();
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        status: 401,
        text: async () => JSON.stringify({ error: { code: "invalid_login", message: "Email or password is wrong" } }),
      }),
    );
    render(<LoginForm apiBase="http://dashboard.local" onSuccess={vi.fn()} />);
    await user.type(screen.getByRole("textbox", { name: "Email" }), "student@example.test");
    await user.type(screen.getByLabelText("Kata sandi"), "wrong-password");
    await user.click(screen.getByRole("button", { name: "Masuk" }));
    expect(screen.getByTestId("login-error").textContent).toMatch(/kata sandi salah/i);
  });
});
