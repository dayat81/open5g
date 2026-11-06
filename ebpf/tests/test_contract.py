import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from exporter.contract import LabelError, render_prometheus, stub_series


def test_stub_series_is_labeled_and_rejects_imsi():
    text = render_prometheus(stub_series())
    assert 'data_origin="stub"' in text
    assert "open5g_app_bytes_total" in text
    try:
        render_prometheus([
            {
                "name": "open5g_app_bytes_total",
                "value": 1,
                "labels": {"imsi": "001010000000001", "data_origin": "stub"},
            }
        ])
    except LabelError as exc:
        assert "imsi" in exc.rejected
    else:
        raise AssertionError("imsi label was accepted")


def test_classifier_build_check_does_not_claim_attach():
    completed = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "check_build.py")],
        check=False,
        text=True,
        capture_output=True,
    )
    assert completed.returncode in {0, 2}
    if completed.returncode == 0:
        assert "loaded=false" in completed.stdout
    else:
        assert "UNTESTED" in completed.stdout
