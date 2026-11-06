# WORK IN PROGRESS snapshot 2026-11-06 20:16:41 +07
# Sanitized example — not a deployable mirror of the live lab.

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
sudo docker compose up -d
sudo bash lab-routes.sh
sudo docker compose -f docker-compose-ran.yml up -d ue
sleep 8
sudo docker compose -f docker-compose-ran.yml up -d enb
sleep 35
sudo bash lab-routes.sh
sudo docker logs l5gd-ue 2>&1 | grep -E 'Network attach successful|RRC NR reconfiguration successful' | tail -2 || true
sudo docker exec l5gd-ue ping -c 5 -W 2 10.99.9.20
