#!/bin/bash
# The Android image binds socat to eth0. This UE has two networks, so eth0
# may be l5gd-screen. Rewrite that bind to the uu address before the image starts.
set -euo pipefail

addr_rejected() {
  case "$1" in
    ""|0.0.0.0|eth0|127.*|0.*) return 0 ;;
  esac
  if ! printf '%s\n' "$1" | awk -F. 'NF != 4 { exit 1 } { for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i + 0 > 255) exit 1 }'; then
    return 0
  fi
  return 1
}

render_socat() {
  local addr=$1
  local port
  for port in 5554 5555; do
    printf 'socat TCP-LISTEN:%s,bind=%s,fork,reuseaddr TCP:127.0.0.1:%s\n' "$port" "$addr" "$port"
  done
}

if [ "${1:-}" = "--print" ]; then
  addr=${ANDROID_UE_UU:?ANDROID_UE_UU}
  if addr_rejected "$addr"; then
    echo "android-ue-adb-bind: refusing ${addr}" >&2
    exit 1
  fi
  render_socat "$addr"
  exit 0
fi

addr=${ANDROID_UE_UU:?ANDROID_UE_UU}
if addr_rejected "$addr"; then
  echo "android-ue-adb-bind: refusing uu address ${addr}" >&2
  exit 1
fi

wrap=$(mktemp -d)
cat >"${wrap}/socat" <<EOF
#!/bin/bash
set -euo pipefail
uu='${addr}'
args=()
for arg in "\$@"; do
  case "\$arg" in
    *bind=*)
      arg=\$(printf '%s\n' "\$arg" | sed "s/bind=[^,]*/bind=\${uu}/")
      ;;
  esac
  args+=("\$arg")
done
exec /usr/bin/socat "\${args[@]}"
EOF
chmod 755 "${wrap}/socat"
export PATH="${wrap}:${PATH}"
cd /opt
exec /opt/start-emulator.sh
