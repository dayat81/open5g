#!/bin/bash
# Rollback semua perubahan PoC (host lab). Pakai: bash ~/poc-latency/lab-down-poc.sh [--inet-only]
# Urutan: poc-inet -> UDP echo -> keepalive -> jalur emulator fase 0. RAN/core TIDAK di-restart.
# Catatan: setelah keepalive berhenti UE akan masuk RRC IDLE (lihat kegagalan 14:02); lab-up-poc.sh memulihkannya.
set -u
ROOT=~/poc-latency
RB=$ROOT/phase0/29-rollback-vm.sh; [ -f "$RB" ] || RB=$ROOT/phase0/scripts/29-rollback-vm.sh
echo "=== poc-inet"; bash $ROOT/inet/49-inet-rollback.sh
[ "${1:-}" = "--inet-only" ] && exit 0
echo "=== UDP echo"; bash $ROOT/phase1/scripts/38-udp-echo-stop.sh
echo "=== keepalive"; bash $ROOT/phase1/scripts/35-keepalive.sh stop
echo "=== jalur emulator fase 0"; bash "$RB"
echo "SELESAI $(date -Is). Tunnel laptop: di WSL bash ~/poc-inet/poc-inet-laptop.sh stop"
