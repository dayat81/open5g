#!/bin/bash
# Static checks for the magen profile. No connection to the magen host.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"
fix="$root/lab/scripts/fixtures/magen"
env_file="$fix/env"
pass="$fix/pass"

echo "shellcheck"
shellcheck -x -P SCRIPTDIR \
  lab/scripts/gen-magen.sh \
  lab/scripts/magen-android-wait.sh \
  lab/scripts/magen-build-images.sh \
  lab/scripts/magen-lib.sh \
  lab/scripts/magen-preflight.sh \
  lab/scripts/magen-screen-chain.sh \
  lab/scripts/magen-ipv6.sh \
  lab/scripts/magen-socks.sh \
  lab/scripts/magen-backup.sh \
  lab/scripts/magen-restore.sh \
  lab/scripts/magen-down.sh \
  lab/scripts/magen-up.sh \
  lab/scripts/magen-smoke.sh \
  lab/scripts/render-magen-config.sh \
  lab/scripts/check-magen.sh

echo "generator"
lab/scripts/gen-android-ue.sh --check
lab/scripts/gen-android-ue.sh --target magen --check
if lab/scripts/gen-android-ue.sh --target magen --count 3 --stdout >/dev/null 2>&1; then
  echo "magen generator accepted a count above the cap" >&2
  exit 1
fi

echo "compose shape"
python3 - <<'PY'
from pathlib import Path
text = Path("lab/compose/compose.magen.yml").read_text(encoding="utf-8")
if "name: open5g" not in text:
    raise SystemExit("project name is not open5g")
if "ANDROID_UE_UU" in text:
    raise SystemExit("compose still requires ANDROID_UE_UU")
if "ANDROID_UE_ADB_MODE: standalone" not in text:
    raise SystemExit("o5g android is missing ANDROID_UE_ADB_MODE=standalone")
if "ANDROID_UE_IPV6_MODE" in Path("lab/scripts/gen-android-ue.sh").read_text(encoding="utf-8").split("return 0", 1)[0]:
    raise SystemExit("IPV6_MODE leaked into the lab emit branch")
for raw in text.splitlines():
    if "network_mode:" in raw and "container:o5g-android" not in raw:
        raise SystemExit("unexpected network_mode: %s" % raw.strip())
if "privileged:" in text:
    raise SystemExit("compose uses privileged")
if 'net.ipv6.conf.eth1.disable_ipv6: "1"' not in text:
    raise SystemExit("android is missing eth1 disable_ipv6")
if "b0-agen-emu" in text.split("services:", 1)[-1].split("networks:", 1)[0]:
    raise SystemExit("compose names the manual emulator")
if 'net.ipv6.conf.all.disable_ipv6: "1"' in text:
    raise SystemExit("compose sets all.disable_ipv6 to 1")
if 'net.ipv6.conf.default.disable_ipv6: "1"' not in text:
    raise SystemExit("compose does not set default.disable_ipv6")
ports = []
in_ports = False
in_android = False
android_cap = False
screen_members = []
service = ""
for raw in text.splitlines():
    if raw.startswith("  ") and raw.endswith(":") and not raw.startswith("   "):
        service = raw.strip().rstrip(":")
        in_android = service.startswith("android")
        in_ports = False
    if in_android and "cap_add:" in raw:
        android_cap = True
    if raw.startswith("    ports:"):
        in_ports = True
        continue
    if in_ports and raw.startswith("      - "):
        ports.append(raw.split("-", 1)[1].strip().strip('"'))
        continue
    if in_ports and raw and not raw.startswith("      "):
        in_ports = False
    if raw.startswith("      screen:") and service:
        screen_members.append(service)
blocked = ("5432", "5555", "5900", "3000", "0.0.0.0", "8000")
for entry in ports:
    if not entry.startswith("127.0.0.1:"):
        raise SystemExit("port is not loopback: %s" % entry)
    for token in blocked:
        if token in entry:
            raise SystemExit("published port contains %s" % token)
if ports != ["127.0.0.1:3300:3300", "127.0.0.1:3301:3301"]:
    raise SystemExit("unexpected published ports: %s" % ports)
if android_cap:
    raise SystemExit("android service has NET_ADMIN or another cap")
if sorted(screen_members) != ["android1", "android2", "dashboard-listener"]:
    raise SystemExit("o5g-screen members are %s" % screen_members)
if "name: o5g-screen" not in text or "internal: true" not in text:
    raise SystemExit("o5g-screen is missing")
if "ogstun" not in text or "gtp5g" in text.split("does not load", 1)[-1]:
    pass
if "ip tuntap add name ogstun" not in text:
    raise SystemExit("UPF does not create ogstun")
in_upf = False
for raw in text.splitlines():
    if raw.startswith("  upf:"):
        in_upf = True
        continue
    if in_upf and raw.startswith("  ") and not raw.startswith("   "):
        break
    if in_upf and raw.strip() == "egress:":
        raise SystemExit("default UPF joins egress")
print("compose shape ok")
PY

echo "preflight pass"
lab/scripts/magen-preflight.sh --env-file "$env_file" --fixture-root "$pass" > /tmp/magen-pass.out
grep -q "host IPv6 is off" /tmp/magen-pass.out

expect_fail() {
  local name=$1
  shift
  if "$@" >"/tmp/magen-${name}.out" 2>"/tmp/magen-${name}.err"; then
    echo "${name} was accepted" >&2
    exit 1
  fi
}

work=$(mktemp -d)
cp -a "$pass" "$work/no-sctp"
printf 'ip_tables 0 - Live 0x0\n' > "$work/no-sctp/modules"
expect_fail sctp lab/scripts/magen-preflight.sh --env-file "$env_file" --fixture-root "$work/no-sctp"
grep -q 'sudo modprobe sctp' "/tmp/magen-sctp.err"
grep -q 'does not load kernel modules' "/tmp/magen-sctp.err"

cp -a "$pass" "$work/busy"
printf 'LISTEN 0 128 127.0.0.1:3300 0.0.0.0:*\n' > "$work/busy/ss.txt"
expect_fail busy lab/scripts/magen-preflight.sh --env-file "$env_file" --fixture-root "$work/busy"

cp -a "$pass" "$work/disk"
printf '1000\n' > "$work/disk/df-avail"
expect_fail disk lab/scripts/magen-preflight.sh --env-file "$env_file" --fixture-root "$work/disk"

cp -a "$pass" "$work/ct"
printf '9\n' > "$work/ct/conntrack-count"
printf '10\n' > "$work/ct/conntrack-max"
expect_fail conntrack lab/scripts/magen-preflight.sh --env-file "$env_file" --fixture-root "$work/ct"

cp -a "$pass" "$work/group"
printf 'ubuntu\n' > "$work/group/id-groups"
expect_fail group lab/scripts/magen-preflight.sh --env-file "$env_file" --fixture-root "$work/group"

cp -a "$pass" "$work/tun"
rm -f "$work/tun/tun-ok"
expect_fail tun lab/scripts/magen-preflight.sh --env-file "$env_file" --fixture-root "$work/tun"

cp -a "$pass" "$work/v6"
printf 'on\n' > "$work/v6/host-ipv6"
printf '1\n' > "$work/v6/unshare-result"
expect_fail v6 lab/scripts/magen-preflight.sh --env-file "$env_file" --fixture-root "$work/v6"

expect_fail dash lab/scripts/magen-preflight.sh --env-file "$env_file" --fixture-root "$pass" --with-dashboard
grep -q 'dashboard profile is closed' "/tmp/magen-dash.err"

echo "screen chain"
rules=$(lab/scripts/magen-screen-chain.sh --render 192.0.2.36)
printf '%s\n' "$rules" | grep -q -- '-s 192.0.2.36'
printf '%s\n' "$rules" | grep -q -- '--dport 8000 -j DROP'
if lab/scripts/magen-screen-chain.sh --render 192.0.2.36 | grep -q '0.0.0.0/0 -j ACCEPT'; then
  echo "screen chain accepts every source" >&2
  exit 1
fi
# shellcheck source=magen-screen-chain.sh
. lab/scripts/magen-screen-chain.sh
magen_screen_source_allowed 192.0.2.36 192.0.2.36
if magen_screen_source_allowed 192.0.2.36 192.0.2.34; then
  echo "emulator address was allowed onto port 8000" >&2
  exit 1
fi

echo "ipv6 tree"
tree=$(mktemp -d)
for name in all default lo eth0 eth1; do
  mkdir -p "$tree/$name"
  printf '0\n' > "$tree/$name/disable_ipv6"
done
lab/scripts/magen-ipv6.sh --apply-tree "$tree"
test "$(cat "$tree/all/disable_ipv6")" = 0
test "$(cat "$tree/lo/disable_ipv6")" = 0
test "$(cat "$tree/default/disable_ipv6")" = 1
test "$(cat "$tree/eth0/disable_ipv6")" = 1
test "$(cat "$tree/eth1/disable_ipv6")" = 1

echo "socks"
socks=$(lab/scripts/magen-socks.sh --render lab/compose/compose.magen.yml)
printf '%s\n' "$socks" | grep -q 'container_name: o5g-cgnat'
if printf '%s\n' "$socks" | awk '
  $0 == "  upf:" { s = 1 }
  s && $0 ~ /^  [^ ]/ && $0 != "  upf:" { s = 0 }
  s && $1 == "egress:" { found = 1 }
  END { exit(found ? 0 : 1) }
'; then
  echo "socks render left the UPF on egress" >&2
  exit 1
fi
if printf '%s\n' "$socks" | grep -q 'ip rule'; then
  echo "socks render uses policy routing" >&2
  exit 1
fi

echo "down"
lab/scripts/magen-down.sh --env-file "$env_file" --dry-run | grep -q 'changed=0'
printf 'o5g-mongo\n' > "$work/ok-names"
lab/scripts/magen-down.sh --names-file "$work/ok-names"
printf 'b0-agen-emu\n' > "$work/bad-names"
expect_fail down lab/scripts/magen-down.sh --names-file "$work/bad-names"
grep -q 'b0-agen-emu' "/tmp/magen-down.err"

echo "sgi flag and image sha"
sgi=$(lab/scripts/magen-socks.sh --sgi-render lab/compose/compose.magen.yml 2>/tmp/magen-sgi.err)
grep -q 'needs Netdrive approval: egress via host' /tmp/magen-sgi.err
printf '%s\n' "$sgi" | awk '
  $0 == "  upf:" { s = 1 }
  s && $0 ~ /^  [^ ]/ && $0 != "  upf:" { s = 0 }
  s && $1 == "egress:" { found = 1 }
  END { exit(found ? 0 : 1) }
'
lab/scripts/magen-build-images.sh --check-sha 7fe7e85
expect_fail sha lab/scripts/magen-build-images.sh --check-sha 3a6498c3b89ce990222d1b284e20caaee2372339
grep -q 'refusing SHA' /tmp/magen-sha.err
: > "$work/empty-images.env"
expect_fail images lab/scripts/magen-up.sh --env-file "$env_file" --images-env "$work/empty-images.env" --with-dashboard --dry-run
# shellcheck source=magen-lib.sh
. lab/scripts/magen-lib.sh
if magen_pid_matches o5g-android1 10 10 && magen_pid_matches b0-agen-emu 10 10; then
  echo "pid guard accepted b0-agen-emu" >&2
  exit 1
fi
printf 'Container o5g-mongo Running\n' > "$work/compose-same.log"
test "$(magen_compose_changed "$work/compose-same.log")" = 0
printf 'Container o5g-mongo Started\n' > "$work/compose-new.log"
test "$(magen_compose_changed "$work/compose-new.log")" = 1

echo "radio fail stays a report"
bad=$(mktemp -d)
printf '1\n' > "$bad/boot"
printf 'ABSENT\n' > "$bad/sim"
printf 'E ModemSimulator: failed\n' > "$bad/logcat"
expect_fail radio env MAGEN_RADIO_DIR="$bad" lab/scripts/magen-smoke.sh --env-file "$env_file" --fixture
grep -q 'no automatic fallback' /tmp/magen-radio.err
grep -q 'dummy0 ULA' /tmp/magen-radio.err
grep -q 'ModemSimulator' /tmp/magen-radio.err

echo "backup and restore"
src=$(mktemp -d)
printf 'archive-bytes\n' | gzip -c > "$src/mongo.archive.gz"
printf 'PGDMP\n' > "$src/postgres.dump"
export O5G_STATE_DIR="$work/state"
out=$(lab/scripts/magen-backup.sh --from-dir "$src")
printf '%s\n' "$out" | grep -q 'changed=1'
if printf '%s\n' "$out" | grep -q 'archive-bytes'; then
  echo "backup printed dump contents" >&2
  exit 1
fi
found=$(find "$work/state/backup" -name 'mongo.archive.gz.sha256' | head -n 1)
[ -n "$found" ]
mode=$(stat -c %a "$(dirname "$found")")
[ "$mode" = "700" ]
mongo=$(mktemp)
pg=$(mktemp)
printf 'x\n' > "$mongo"
printf 'y\n' > "$pg"
expect_fail restore lab/scripts/magen-restore.sh --mongo-dump "$mongo" --pg-dump "$pg" --mongo-count 1 --pg-count 0
lab/scripts/magen-restore.sh --mongo-dump "$mongo" --pg-dump "$pg" --mongo-count 0 --pg-count 0 --force-nonempty >/dev/null

echo "render and smoke"
rm -rf /tmp/o5g-magen-fixture
lab/scripts/render-magen-config.sh --env-file "$env_file" --out /tmp/o5g-magen-fixture/conf
test -f /tmp/o5g-magen-fixture/conf/mme.yaml
grep -q '198.51.100.2' /tmp/o5g-magen-fixture/conf/mme.yaml
if grep -q '10.99.' /tmp/o5g-magen-fixture/conf/mme.yaml; then
  echo "rendered config has a lab address" >&2
  exit 1
fi
lab/scripts/magen-smoke.sh --env-file "$env_file" --fixture
python3 - <<'PY'
import json
body = json.load(open("/tmp/o5g-magen-fixture/smoke.json", encoding="utf-8"))
assert body["listener_bind"] == "127.0.0.1:3301"
assert body["ue_chains"] == "N/A"
assert body["sgi_curl"] == "SKIPPED"
assert body["core_up"] == "skipped"
assert "8000" in body["screen_port_8000"]
PY

echo "up dry-run"
lab/scripts/magen-up.sh --env-file "$env_file" --dry-run | grep -q 'changed=0'
printf '\nANDROID_UE_UU=192.0.2.50\n' >> "$work/with-uu.env"
cat "$env_file" > "$work/with-uu.env"
printf '\nANDROID_UE_UU=192.0.2.50\n' >> "$work/with-uu.env"
expect_fail uu lab/scripts/magen-up.sh --env-file "$work/with-uu.env" --dry-run

echo "example placeholders"
for key in O5G_ANDROID_IMAGE UE1_IMSI UE1_KI UE1_OPC UE1_IMEI O5G_SESSION_PEPPER; do
  value=$(awk -F= -v k="$key" '$1 == k { print substr($0, index($0, "=") + 1); exit }' lab/compose/env.example.magen)
  case "$value" in
    REPLACE_*) ;;
    *)
      echo "example ${key} is not a placeholder" >&2
      exit 1
      ;;
  esac
done
if grep -Eq '10\.99\.|10\.45\.' lab/compose/env.example.magen lab/compose/compose.magen.yml docs/deploy/magen.md; then
  echo "magen files contain a lab prefix" >&2
  exit 1
fi

echo "magen checks passed"
