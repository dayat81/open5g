#!/bin/bash
# Build the three magen images from PR #13 at one SHA.
# Lab Ops runs this. CI only checks the SHA guard. Do not push to a registry.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

expected=7fe7e85cdae36f0615b115627e36c73412a4644c
sha=$expected
do_build=1
save_dir=""
out=""

usage() {
  echo "usage: magen-build-images.sh [--sha SHA] [--check-sha SHA] [--save DIR] [--out FILE]" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sha)
      shift
      sha=$1
      ;;
    --check-sha)
      shift
      sha=$1
      do_build=0
      ;;
    --save)
      shift
      save_dir=$1
      ;;
    --out)
      shift
      out=$1
      ;;
    *) usage ;;
  esac
  shift
done

root=$(magen_root)
if [ -z "$out" ]; then
  out="$root/lab/compose/magen.images.env"
fi

case "$sha" in
  7fe7e85|7fe7e85cdae36f0615b115627e36c73412a4644c) ;;
  *)
    echo "magen: refusing SHA ${sha}. Images must be built from ${expected} (PR #13). B0/B2 images from #12 are rejected." >&2
    exit 1
    ;;
esac
if git -C "$root" cat-file -e "${expected}^{commit}" 2>/dev/null; then
  resolved=$(git -C "$root" rev-parse --verify "${sha}^{commit}")
  if [ "$resolved" != "$expected" ]; then
    echo "magen: refusing SHA ${sha}. Images must be built from ${expected} (PR #13). B0/B2 images from #12 are rejected." >&2
    exit 1
  fi
fi

if [ "$do_build" -eq 0 ]; then
  echo "magen: SHA ${expected} is the only accepted image source"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "magen: docker is missing. CI does not build these images." >&2
  exit 1
fi

work=$(mktemp -d)
cleanup() { git -C "$root" worktree remove --force "$work" >/dev/null 2>&1 || rm -rf "$work"; }
trap cleanup EXIT
git -C "$root" worktree add --detach "$work" "$expected" >/dev/null

ANDROID_UE_ANDROID_IMAGE=o5g-emulator:7fe7e85 bash "$work/lab/images/android-emulator/build.sh"
android_id=$(docker image inspect -f '{{.Id}}' o5g-emulator:7fe7e85)

docker build -t o5g-screen:7fe7e85 -f "$work/lab/images/ws-scrcpy/Dockerfile" "$work/lab/images/ws-scrcpy"
docker build -t o5g-screen:7fe7e85 -f - "$work" <<'EOF'
FROM o5g-screen:7fe7e85
COPY lab/scripts/android-ue-screen.sh /opt/android-ue/android-ue-screen.sh
ENTRYPOINT ["/bin/sh", "/opt/android-ue/android-ue-screen.sh"]
EOF
screen_id=$(docker image inspect -f '{{.Id}}' o5g-screen:7fe7e85)

docker build -t o5g-dashboard:7fe7e85 -f "$work/dashboard/backend/Dockerfile" "$work/dashboard/backend"
dashboard_id=$(docker image inspect -f '{{.Id}}' o5g-dashboard:7fe7e85)

pin() {
  local id=$1
  id=${id#sha256:}
  printf 'sha256:%s\n' "$id"
}

umask 077
cat >"$out" <<EOF
O5G_ANDROID_IMAGE=$(pin "$android_id")
O5G_SCREEN_IMAGE=$(pin "$screen_id")
O5G_DASHBOARD_API_IMAGE=$(pin "$dashboard_id")
EOF
chmod 0600 "$out"
echo "magen: pinned image ids in ${out}"

if [ -n "$save_dir" ]; then
  mkdir -p -- "$save_dir"
  docker save o5g-emulator:7fe7e85 o5g-screen:7fe7e85 o5g-dashboard:7fe7e85 | gzip > "${save_dir}/o5g-images-7fe7e85.tar.gz"
  echo "magen: saved ${save_dir}/o5g-images-7fe7e85.tar.gz"
fi
