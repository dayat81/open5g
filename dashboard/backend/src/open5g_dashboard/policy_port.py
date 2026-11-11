"""Immediate Gx apply port.

Stock Open5GS 2.8 does not push a subscriber edit to an active session.
``OPEN5G_ENABLE_GX_RAR=1`` selects the draft admin-RAR adapter, which still
rejects the call: ``lab/patches/pcrf-admin-rar`` is not compiled or tested,
and the lab PCRF runs the stock image.
"""

from __future__ import annotations

from open5g_dashboard.domain import TARGETS, ApplyResult, Operation, TargetState, stock_immediate_apply


def _idle(desired_version: int, error: str) -> list[TargetState]:
    return [
        TargetState(
            target=target,
            state="not_executed",
            desired_version=desired_version,
            applied_version=None,
            observed_version=None,
            error=error,
            evidence={"data_origin": "none", "core_restart": False},
        )
        for target in TARGETS
    ]


class StockPolicyPort:
    name = "stock_reject"
    live = False

    def apply(self, ops: list[Operation], desired_version: int) -> ApplyResult:
        return stock_immediate_apply(ops, desired_version)


class DraftAdminRarPort:
    name = "gx_rar_admin_draft"
    live = False

    def apply(self, ops: list[Operation], desired_version: int) -> ApplyResult:
        reasons = [{"op": op.name, "capability": op.capability, "reason": op.reason} for op in ops]
        reasons.append(
            {
                "op": "gx_rar_admin",
                "capability": "draft_not_available",
                "reason": (
                    "OPEN5G_ENABLE_GX_RAR is on, but the PCRF admin-RAR patch is draft, "
                    "not compiled, and not tested. The stock Open5GS 2.8 image has no such path, "
                    "so this call does not push a live RAR."
                ),
            }
        )
        return ApplyResult(
            status="rejected",
            executed=False,
            core_restart=False,
            data_origin="none",
            reasons=reasons,
            targets=_idle(desired_version, "pcrf_admin_rar_not_available"),
            path="gx_rar_admin_draft",
        )


def build_policy_port(settings) -> StockPolicyPort | DraftAdminRarPort:
    if settings.enable_gx_rar:
        return DraftAdminRarPort()
    return StockPolicyPort()
