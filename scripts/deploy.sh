#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${ROOT_DIR}"

if [[ ! -f data/xray/config.json ]]; then
  "${ROOT_DIR}/scripts/init.sh"
fi

docker compose config --quiet
docker compose up -d --remove-orphans
docker compose ps

printf '\n订阅信息：\n'
sed -n 's/^SUBSCRIPTION_URL=/  /p' data/deployment.env
