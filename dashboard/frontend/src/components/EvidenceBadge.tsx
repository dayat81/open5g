export function EvidenceBadge({
  state,
}: {
  state: "saved" | "validated" | "pushed" | "active" | "rejected" | "unknown";
}) {
  if (state === "active") {
    return <span className="badge lifecycle-active">Active</span>;
  }
  if (state === "pushed") {
    return <span className="badge applied">pushed</span>;
  }
  if (state === "saved" || state === "validated") {
    return <span className="badge intent">{state}</span>;
  }
  if (state === "rejected") {
    return <span className="badge fail">rejected</span>;
  }
  return <span className="badge unknown">{state}</span>;
}

export function AppliedVersion({ version }: { version: string }) {
  return (
    <span className="state-card applied" data-testid="applied-version">
      applied {version}
    </span>
  );
}
