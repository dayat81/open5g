import { OverviewScreen } from "@/components/OverviewScreen";
import { createClient } from "@/lib/api";

export default function Page() {
  const client = createClient(process.env.NEXT_PUBLIC_API_BASE);
  return <OverviewScreen mode={client.mode} apiBase={process.env.NEXT_PUBLIC_API_BASE} />;
}
