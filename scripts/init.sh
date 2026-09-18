#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE="${ROOT_DIR}/.env"
DATA_DIR="${ROOT_DIR}/data"
XRAY_IMAGE="ghcr.io/xtls/xray-core:26.6.27"

fail() { printf '错误：%s\n' "$*" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || fail "找不到 docker"
docker compose version >/dev/null 2>&1 || fail "找不到 docker compose 插件"

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ROOT_DIR}/.env.example" "${ENV_FILE}"
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

SERVER_ADDRESS=${SERVER_ADDRESS:-}
XRAY_PORT=${XRAY_PORT:-443}
SUBSCRIPTION_PORT=${SUBSCRIPTION_PORT:-8080}
REALITY_SERVER_NAME=${REALITY_SERVER_NAME:-www.microsoft.com}
REALITY_TARGET=${REALITY_TARGET:-${REALITY_SERVER_NAME}:443}

[[ -n "${SERVER_ADDRESS}" && "${SERVER_ADDRESS}" != "203.0.113.10" ]] || \
  fail "请先在 .env 中把 SERVER_ADDRESS 改成服务器公网 IP 或域名"
[[ "${XRAY_PORT}" =~ ^[0-9]+$ && "${XRAY_PORT}" -ge 1 && "${XRAY_PORT}" -le 65535 ]] || fail "XRAY_PORT 无效"
[[ "${SUBSCRIPTION_PORT}" =~ ^[0-9]+$ && "${SUBSCRIPTION_PORT}" -ge 1 && "${SUBSCRIPTION_PORT}" -le 65535 ]] || fail "SUBSCRIPTION_PORT 无效"

umask 077
mkdir -p "${DATA_DIR}/xray" "${DATA_DIR}/subscription"
chmod 755 "${DATA_DIR}/subscription"

UUID=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(openssl rand -hex 8)
SUB_TOKEN=$(openssl rand -hex 24)
KEY_PAIR=$(docker run --rm "${XRAY_IMAGE}" x25519)
PRIVATE_KEY=$(printf '%s\n' "${KEY_PAIR}" | sed -n 's/^Private key: //p')
PUBLIC_KEY=$(printf '%s\n' "${KEY_PAIR}" | sed -n 's/^Public key: //p')
[[ -n "${PRIVATE_KEY}" && -n "${PUBLIC_KEY}" ]] || fail "无法生成 REALITY 密钥"

cat >"${DATA_DIR}/xray/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${UUID}", "flow": "xtls-rprx-vision", "email": "clash" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "target": "${REALITY_TARGET}",
        "serverNames": ["${REALITY_SERVER_NAME}"],
        "privateKey": "${PRIVATE_KEY}",
        "shortIds": ["${SHORT_ID}"]
      }
    },
    "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true }
  }],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ]
}
EOF

cat >"${DATA_DIR}/subscription/${SUB_TOKEN}.yaml" <<EOF
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: true
unified-delay: true
tcp-concurrent: true
dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - https://1.1.1.1/dns-query
    - https://dns.google/dns-query
proxies:
  - name: learn-xray-reality
    type: vless
    server: ${SERVER_ADDRESS}
    port: ${XRAY_PORT}
    uuid: ${UUID}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: ${REALITY_SERVER_NAME}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - learn-xray-reality
      - DIRECT
rules:
  - MATCH,PROXY
EOF

cat >"${DATA_DIR}/deployment.env" <<EOF
UUID=${UUID}
PUBLIC_KEY=${PUBLIC_KEY}
SHORT_ID=${SHORT_ID}
SUBSCRIPTION_URL=http://${SERVER_ADDRESS}:${SUBSCRIPTION_PORT}/${SUB_TOKEN}.yaml
EOF
# 容器以非 root 用户运行，绑定挂载的文件需要可读；父目录仍为 0700，
# 因而宿主机上的其他普通用户无法穿越目录读取这些文件。
chmod 600 "${DATA_DIR}/deployment.env"
chmod 644 "${DATA_DIR}/xray/config.json" "${DATA_DIR}/subscription/${SUB_TOKEN}.yaml"

printf '\n配置已生成。启动命令：docker compose up -d\n'
printf 'Clash/Mihomo 订阅地址：http://%s:%s/%s.yaml\n' "${SERVER_ADDRESS}" "${SUBSCRIPTION_PORT}" "${SUB_TOKEN}"
printf '凭据保存在：%s（已被 git 忽略）\n' "${DATA_DIR}/deployment.env"
