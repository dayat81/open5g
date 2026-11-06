# Sanitized script reference

#!/bin/bash
set -euo pipefail
cd /home/lab/lab5g-dev
if [ -d open5gs-src/.git ]; then
  echo "open5gs-src already present"; git -C open5gs-src status -sb; exit 0
fi
# Prefer local tarball if provided
if [ -f /home/lab/images/open5gs-v2.8.0.tar.gz ]; then
  mkdir -p open5gs-src
  tar xzf /home/lab/images/open5gs-v2.8.0.tar.gz -C open5gs-src --strip-components=1
  git -C open5gs-src init
  git -C open5gs-src checkout -b dev-smf-upf
else
  git clone --depth 1 --branch v2.8.0 https://github.com/open5gs/open5gs.git open5gs-src
  git -C open5gs-src checkout -b dev-smf-upf
fi
echo "Source ready on branch $(git -C open5gs-src rev-parse --abbrev-ref HEAD)"
