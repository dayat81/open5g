import { EmulatorPage } from "@/components/EmulatorScreen";
import { createClient } from "@/lib/api";

export default function EmulatorRoute() {
  const client = createClient(process.env.NEXT_PUBLIC_API_BASE);
  return <EmulatorPage mode={client.mode} apiBase={process.env.NEXT_PUBLIC_API_BASE ?? ""} />;
}
