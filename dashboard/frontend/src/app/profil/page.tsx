"use client";

import { ProfileEditor } from "@/components/ProfileEditor";
import { createClient } from "@/lib/api";

export default function ProfilPage() {
  const client = createClient(process.env.NEXT_PUBLIC_API_BASE);
  return <ProfileEditor client={client} />;
}
