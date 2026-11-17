#!/bin/bash
# poc-inet guard (lab5g-vm): jalankan apply.sh tiap 10 s (tahan restart l5g-server/l5g-upf/l5g-ue). Stop: remove.sh
while true; do /home/lab/poc-inet/apply.sh; sleep 10; done
