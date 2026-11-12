"use client";

import { LiveProfileEditor } from "@/components/LiveProfileEditor";
import { ProfileEditor } from "@/components/ProfileEditor";

export default function ProfilPage() {
  const apiBase = process.env.NEXT_PUBLIC_API_BASE;
  if (!apiBase) {
    return <ProfileEditor />;
  }
  return <LiveProfileEditor apiBase={apiBase} />;
}
