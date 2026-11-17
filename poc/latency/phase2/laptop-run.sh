#!/bin/bash
# poc-phase2 helper di WSL: laptop-run.sh <file> [args] -> salin ke host lab ~/poc-latency/phase2/scripts lalu jalankan
# Tujuan SSH: MAGEN_USER@MAGEN_HOST, atau alias SSH "magen". Direktori sumber: POC_PHASE2_DIR (default ~/poc-phase2).
S=(ssh -T -o BatchMode=yes -o ClearAllForwardings=yes -o LogLevel=ERROR)
L="${POC_PHASE2_DIR:-$HOME/poc-phase2}"
if [ -n "${MAGEN_HOST:-}" ]; then
  DEST="${MAGEN_USER:-${LAB_USER:?set MAGEN_USER or LAB_USER}}@${MAGEN_HOST}"
  [ -n "${MAGEN_SSH_KEY:-}" ] && S+=(-i "$MAGEN_SSH_KEY")
else
  DEST=magen
fi
f=$1; shift
"${S[@]}" "$DEST" 'mkdir -p ~/poc-latency/phase2/scripts ~/poc-latency/phase2/results ~/poc-latency/phase2/app ~/poc-latency/phase2/zeek'
case "$f" in
  *.sh) { [ ! -f $L/$f ] || scp -q -o BatchMode=yes -o LogLevel=ERROR $L/$f "$DEST:poc-latency/phase2/scripts/"; } && "${S[@]}" "$DEST" "bash ~/poc-latency/phase2/scripts/$f $*" ;;
  *.tgz) scp -q -o BatchMode=yes -o LogLevel=ERROR $L/$f "$DEST:poc-latency/phase2/" && "${S[@]}" "$DEST" "cd ~/poc-latency/phase2 && tar xzf $f && echo extracted $f" ;;
  *) scp -q -o BatchMode=yes -o LogLevel=ERROR $L/$f "$DEST:poc-latency/phase2/" && echo "copied $f" ;;
esac
