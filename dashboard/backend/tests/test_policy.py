"""Gx RAR flag. On still means rejected."""

from open5g_dashboard.domain import Operation
from open5g_dashboard.policy_port import DraftAdminRarPort, StockPolicyPort


def test_stock_port_rejects_without_claiming_a_push():
    result = StockPolicyPort().apply([Operation("apn_ambr_rar", "unsupported", "stock")], 1)
    assert result.status == "rejected"
    assert result.executed is False
    assert result.path == "gx_rar_immediate"
    assert any(reason["op"] == "gx_rar" and reason["capability"] == "not_integrated" for reason in result.reasons)
    assert StockPolicyPort().live is False


def test_draft_flag_does_not_report_pushed_or_active():
    result = DraftAdminRarPort().apply([Operation("new_pcc_rule_rar", "unverified", "no adapter")], 3)
    assert result.status == "rejected"
    assert result.executed is False
    assert result.core_restart is False
    assert result.path == "gx_rar_admin_draft"
    assert result.status not in {"pushed", "active"}
    assert any(reason["capability"] == "draft_not_available" for reason in result.reasons)
    assert DraftAdminRarPort().live is False
