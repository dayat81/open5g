#!/bin/bash
# Render Open5GS config from lab/config/magen templates. No literal lab addresses.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

env_file=""
out=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      shift
      env_file=$1
      ;;
    --out)
      shift
      out=$1
      ;;
    *)
      echo "usage: render-magen-config.sh --env-file FILE --out DIR" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$env_file" ] || [ ! -f "$env_file" ] || [ -z "$out" ]; then
  echo "usage: render-magen-config.sh --env-file FILE --out DIR" >&2
  exit 2
fi

root=$(magen_root)
mkdir -p -- "$out/fd"
set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

python3 - "$root/lab/config/magen" "$out" <<'PY'
import os, pathlib, sys
src = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
for path in sorted(src.glob("*.tpl")):
    text = path.read_text(encoding="utf-8")
    for key, value in os.environ.items():
        text = text.replace("@" + key + "@", value)
    if "@" in text or "REPLACE_" in text or "10.99." in text:
        sys.stderr.write("magen: %s still has a placeholder or a lab address\n" % path.name)
        sys.exit(1)
    target = dest / "fd" / path.name.replace(".tpl", "") if path.name.endswith(".conf.tpl") else dest / path.name.replace(".tpl", "")
    target.write_text(text, encoding="utf-8")
PY
echo "magen: rendered ${out}"
echo "changed=1"
