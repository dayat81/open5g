# WORK IN PROGRESS snapshot 2026-11-06 20:16:41 +07
# Sanitized example — not a deployable mirror of the live lab.

#!/bin/bash
cd "$(dirname "$0")"
sudo docker compose -f docker-compose-ran.yml down || true
sudo cp -a docker-compose-ran.yml.bak-endc docker-compose-ran.yml
sudo cp -a ran.env.bak-endc ran.env
sudo cp -a lab-up.sh.bak-endc lab-up.sh
sudo cp -a README.md.bak-endc README.md
sudo bash lab-up.sh
