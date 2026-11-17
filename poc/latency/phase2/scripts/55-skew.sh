#!/bin/bash
# poc-phase2: ukur offset jam (read-only, TIDAK mengubah jam) relatif magen, metode bracket lewat 1 sesi persisten (coproc):
#   offset = t_remote - (t_kirim + t_terima)/2 ; dipilih sampel RTT terkecil dari N. VM = jam probe Zeek; EMU = jam Android (t_ue).
cd ~/poc-latency/phase2 && . scripts/common-p2.sh
N=${N:-25}
meas(){ # $1 nama, sisanya = perintah sesi
  local name=$1; shift
  coproc C { "$@" 2>/dev/null; }
  sleep 2; echo 'date +%s.%N' >&${C[1]}; read -t 10 -r _ <&${C[0]}   # pemanasan
  local res=""
  for i in $(seq $N); do
    a=$(date +%s.%N); echo 'date +%s.%N' >&${C[1]}; read -t 10 -r r <&${C[0]}; b=$(date +%s.%N)
    res="$res$a $r $b"$'\n'
  done
  echo 'exit' >&${C[1]} 2>/dev/null; kill $C_PID 2>/dev/null; wait $C_PID 2>/dev/null
  printf "%s" "$res" | awk -v n=$name '{r=$2+0; if(r==0) next; rtt=($3-$1)*1000; off=$2-($1+$3)/2; if(min==""||rtt<min){min=rtt;bo=off}; s+=off; k++}
    END{printf "%s offset_s=%.4f best_rtt_ms=%.2f mean_offset_s=%.4f n=%d\n", n, bo, min, s/k, k}'
}
date -Is
meas VM_minus_magen $V 'while read l; do [ "$l" = exit ] && exit; date +%s.%N; done'
meas EMU_minus_magen $D exec -i $EMU adb -s emulator-5554 shell
