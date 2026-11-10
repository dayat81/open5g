import { AuditScreen } from "@/components/AuditScreen";
import { createClient } from "@/lib/api";

export default function AuditPage() {
  const client = createClient(process.env.NEXT_PUBLIC_API_BASE);
  return <AuditScreen mode={client.mode} apiBase={process.env.NEXT_PUBLIC_API_BASE} />;
}
