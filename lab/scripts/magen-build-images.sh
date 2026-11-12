#!/bin/bash
# Build the magen images from PR #13 at one SHA, including the web image.
# Lab Ops runs this. CI only checks the SHA guard. Do not push to a registry.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=magen-lib.sh
. "$script_dir/magen-lib.sh"

expected=a680f8b469d51e4c1d95d433f4b97c84d153a622
tag=a680f8b
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
  a680f8b|a680f8b469d51e4c1d95d433f4b97c84d153a622) ;;
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

ANDROID_UE_ANDROID_IMAGE="o5g-emulator:${tag}" bash "$work/lab/images/android-emulator/build.sh"
# The helper container reuses this image. iptables-legacy is for the 3.10 host.
docker build -t "o5g-emulator:${tag}" -f - "$work" <<EOF
FROM o5g-emulator:${tag}
USER root
RUN apt-get update \\
    && apt-get install -y --no-install-recommends iptables iproute2 procps \\
    && rm -rf /var/lib/apt/lists/*
EOF
android_id=$(docker image inspect -f '{{.Id}}' "o5g-emulator:${tag}")

docker build -t "o5g-screen:${tag}" -f "$work/lab/images/ws-scrcpy/Dockerfile" "$work/lab/images/ws-scrcpy"
docker build -t "o5g-screen:${tag}" -f - "$work" <<EOF
FROM o5g-screen:${tag}
COPY lab/scripts/android-ue-screen.sh /opt/android-ue/android-ue-screen.sh
ENTRYPOINT ["/bin/sh", "/opt/android-ue/android-ue-screen.sh"]
EOF
screen_id=$(docker image inspect -f '{{.Id}}' "o5g-screen:${tag}")

docker build -t "o5g-dashboard:${tag}" -f "$work/dashboard/backend/Dockerfile" "$work/dashboard/backend"
dashboard_id=$(docker image inspect -f '{{.Id}}' "o5g-dashboard:${tag}")
docker build -t "o5g-dashboard-web:${tag}" -f "$work/dashboard/frontend/Dockerfile" "$work/dashboard/frontend"
web_id=$(docker image inspect -f '{{.Id}}' "o5g-dashboard-web:${tag}")
docker pull postgres:16
# postgres:16 is the upstream tag. It is not built from the #13 SHA.
postgres_ref=$(docker image inspect --format '{{index .RepoDigests 0}}' postgres:16)
case "$postgres_ref" in
  postgres@sha256:*) ;;
  *)
    echo "magen: postgres:16 has no registry digest. Pull it outside magen before pinning." >&2
    exit 1
    ;;
esac

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
O5G_DASHBOARD_WEB_IMAGE=$(pin "$web_id")
O5G_POSTGRES_IMAGE=${postgres_ref}
EOF
chmod 0600 "$out"
echo "magen: pinned image ids in ${out}"

if [ -n "$save_dir" ]; then
  mkdir -p -- "$save_dir"
  docker save "o5g-emulator:${tag}" "o5g-screen:${tag}" "o5g-dashboard:${tag}" "o5g-dashboard-web:${tag}" | gzip > "${save_dir}/o5g-images-${tag}.tar.gz"
  echo "magen: saved ${save_dir}/o5g-images-${tag}.tar.gz"
  # Separate archive so the four-image tar Lab Ops already built stays valid.
  docker save postgres:16 | gzip > "${save_dir}/o5g-postgres.tar.gz"
  echo "magen: saved ${save_dir}/o5g-postgres.tar.gz"
fi
