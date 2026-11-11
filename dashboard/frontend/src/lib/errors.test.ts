import { describe, expect, it } from "vitest";
import { messageForApiError } from "./errors";

describe("messageForApiError", () => {
  it("maps 401 to a login prompt", () => {
    expect(messageForApiError({ status: 401, code: "unauthenticated" }).text).toMatch(/sesi/i);
    expect(messageForApiError({ status: 401, code: "invalid_login" }).text).toMatch(/kata sandi/i);
  });

  it("maps 403 admin and cross-group denials", () => {
    expect(messageForApiError({ status: 403, code: "admin_profile_control_forbidden" }).text).toMatch(/admin tidak boleh/i);
    expect(messageForApiError({ status: 403, code: "cross_group_forbidden" }).text).toMatch(/luar grup/i);
    expect(messageForApiError({ status: 403, code: "cross_group_forbidden" }).offerReload).toBe(false);
  });

  it("maps 409 etag, subscriber, and stale generation to a reload", () => {
    for (const code of ["version_conflict", "subscriber_conflict", "stale_generation"]) {
      const mapped = messageForApiError({ status: 409, code });
      expect(mapped.offerReload).toBe(true);
      expect(mapped.text).toMatch(/muat ulang/i);
    }
  });

  it("maps a missing subscriber store without echoing the environment name", () => {
    const mapped = messageForApiError({
      status: 503,
      code: "subscriber_store_not_configured",
      message: "OPEN5G_MONGO_URI is empty",
    });
    expect(mapped.text).toMatch(/belum dikonfigurasi/i);
    expect(mapped.text).not.toMatch(/MONGO_URI/);
  });

  it("maps an unseeded subscriber without offering a reload", () => {
    const mapped = messageForApiError({ status: 422, code: "subscriber_not_seeded" });
    expect(mapped.text).toMatch(/belum ada di mongo/i);
    expect(mapped.offerReload).toBe(false);
  });
});
