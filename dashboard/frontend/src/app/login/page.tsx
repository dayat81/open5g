"use client";

import { LoginForm } from "@/components/LoginForm";
import { Shell } from "@/components/Shell";

export default function LoginPage() {
  const apiBase = process.env.NEXT_PUBLIC_API_BASE;
  return (
    <Shell active="/login" mode={apiBase ? "api" : "demo"}>
      {apiBase ? (
        <LoginForm apiBase={apiBase} onSuccess={() => window.location.assign("/profil")} />
      ) : (
        <p className="note">Mode demo tidak punya sesi. Isi NEXT_PUBLIC_API_BASE untuk masuk lewat API.</p>
      )}
    </Shell>
  );
}
