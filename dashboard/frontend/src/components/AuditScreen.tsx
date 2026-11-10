import { DemoBanner } from "./DemoBanner";
import { SessionFrame } from "./SessionFrame";

export function AuditScreen({ mode = "demo", apiBase }: { mode?: "demo" | "api"; apiBase?: string }) {
  return (
    <SessionFrame active="/audit" mode={mode} apiBase={apiBase}>
      {mode === "demo" ? <DemoBanner /> : null}
      <h1>Audit dan status apply</h1>
      <p className="sub">Baris di bawah adalah contoh struktur, bukan jejak dari core.</p>
      <table className="wf">
        <thead>
          <tr>
            <th>actor</th>
            <th>owner</th>
            <th>hasil</th>
            <th>alasan</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td className="mono">contoh-instructor</td>
            <td className="mono">contoh-student</td>
            <td>
              <span className="badge fail">403</span>
            </td>
            <td className="mono">cross_group_forbidden</td>
          </tr>
          <tr>
            <td className="mono">contoh-student</td>
            <td className="mono">contoh-student</td>
            <td>
              <span className="badge fail">rejected</span>
            </td>
            <td className="mono">gx_rar not_integrated</td>
          </tr>
        </tbody>
      </table>
      <p className="note">Jejak sungguhan dibaca dari API setelah sesi ada. Layar ini tidak menulis audit.</p>
    </SessionFrame>
  );
}
