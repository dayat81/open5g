#!/bin/bash
# Boot the androidN service from gen-android-ue.sh without phase B.
# The service body lives in lab/compose/android-ue-android.fragment.yml.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
exec bash "$script_dir/android-ue-up.sh" --boot-only "$@"
