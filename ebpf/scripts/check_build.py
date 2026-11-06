"""Compile the classifier skeleton when the toolchain exists.

Exit 0: object built under the temp directory.
Exit 2: clang or libbpf headers are missing; status is untested.
The script does not load or attach the object.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "classifier" / "app_classifier.bpf.c"
HEADER = Path("/usr/include/bpf/bpf_helpers.h")


def main() -> int:
    clang = shutil.which("clang")
    if clang is None or not HEADER.is_file() or not SOURCE.is_file():
        print("UNTESTED: clang or /usr/include/bpf/bpf_helpers.h is missing; BPF object was not built")
        return 2
    with tempfile.TemporaryDirectory(prefix="open5g-bpf-") as tmp:
        output = Path(tmp) / "app_classifier.bpf.o"
        command = [
            clang,
            "-O2",
            "-g",
            "-Wall",
            "-Werror",
            "-target",
            "bpf",
            "-D__TARGET_ARCH_x86",
            "-I/usr/include/x86_64-linux-gnu",
            "-c",
            str(SOURCE),
            "-o",
            str(output),
        ]
        completed = subprocess.run(command, check=False, text=True, capture_output=True)
        if completed.returncode != 0:
            sys.stderr.write(completed.stderr)
            print("BUILD_FAILED")
            return 1
        if not output.is_file() or output.stat().st_size == 0:
            print("BUILD_FAILED: empty object")
            return 1
        print(f"BUILT {output.name} bytes={output.stat().st_size} loaded=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
