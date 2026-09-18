# learn_Xray

基于 Docker Compose 的 Xray 一键部署示例，自动生成服务端配置和 Mihomo（Clash.Meta）订阅。默认同时提供：

- `learn-xray-ss2022`：Shadowsocks 2022，兼容性高，作为默认节点；
- `learn-xray-reality`：VLESS + TCP + XTLS Vision + REALITY，用于支持该握手的网络和客户端。

> 仅在当地法律与网络服务条款允许的范围内使用。禁止用于未授权访问、攻击或其他违法活动。

## 整体链路

```text
Clash Verge / Mihomo
  ├─ SS 2022 ── TCP/UDP 8443 ─┐
  └─ VLESS REALITY ─ TCP 443 ─┤→ Docker → Xray → 目标网站
                               │
  获取订阅 ─────── TCP 8080 ───┘→ Nginx → 随机令牌.yaml
```

Xray 容器内部固定监听 `443`（REALITY）和 `8388`（SS 2022），Compose 将 `.env` 中的宿主机端口映射进去。Nginx 只提供随机路径的静态订阅。

## 服务器要求

- 具有公网 IP 或域名的 Linux 服务器；
- Docker Engine 与 Docker Compose 插件；
- `openssl`；
- 云安全组/防火墙放行下列入站端口。

| 协议 | 默认端口 | 用途 |
|---|---:|---|
| TCP、UDP | `8443` | Shadowsocks 2022；只用 TCP 时可不放行 UDP |
| TCP | `443` | VLESS REALITY（可选） |
| TCP | `8080` | Mihomo 订阅 |

安全组通常有状态，出站保持默认允许全部即可。订阅稳定后，可把 `8080` 的来源限制为自己的公网 IP。

## 一键部署

```bash
git clone https://github.com/oublie6/learn_Xray.git
cd learn_Xray
cp .env.example .env
```

编辑 `.env`，至少修改 `SERVER_ADDRESS`：

```dotenv
SERVER_ADDRESS=你的公网IP或域名
REALITY_PORT=443
SS_PORT=8443
SUBSCRIPTION_PORT=8080
REALITY_SERVER_NAME=www.microsoft.com
REALITY_TARGET=www.microsoft.com:443
```

执行：

```bash
./scripts/deploy.sh
```

首次运行会拉取镜像，并生成 UUID、REALITY 密钥、Short ID、SS 2022 密钥和随机订阅令牌。终端将输出订阅地址。

## Clash Verge / Mihomo

1. 把脚本输出的订阅 URL 添加到客户端；
2. 更新订阅并重启 Mihomo 内核；
3. 优先选择 `learn-xray-ss2022`；
4. 网络和客户端确认支持 REALITY 后，可测试 `learn-xray-reality`。

旧版 Clash Premium 不支持 VLESS REALITY，请使用 Mihomo 内核。查看订阅地址：

```bash
sed -n 's/^SUBSCRIPTION_URL=//p' data/deployment.env
```

### 默认分流规则

订阅默认使用 `rule` 模式，按顺序执行：

1. `.lan`、`.local` 和 IPv4/IPv6 私有地址直连；
2. 中国大陆域名直连；
3. 中国大陆 IP 地址直连；
4. 其余流量交给 `PROXY` 策略组。

国内域名和 IP 使用 MetaCubeX `meta-rules-dat` 的压缩 `.mrs` 规则集，由 Mihomo 每 24 小时更新，无需在仓库中维护大量 IP。首次加载订阅时，客户端需要能够访问 GitHub Raw 下载两个规则文件。规则按从上到下顺序匹配，可在 Clash Verge 中切换全局、规则或直连模式。

## 校验与排障

```bash
docker compose ps
docker compose exec xray xray run -test -c /etc/xray/config.json
docker compose logs --tail=100 xray
curl --fail "$(sed -n 's/^SUBSCRIPTION_URL=//p' data/deployment.env)"
ss -lntup | grep -E ':443|:8443|:8080'
```

推荐按以下顺序定位：

1. 订阅无法更新：检查 `8080/TCP`、订阅 URL 和 Nginx 日志；
2. 两个节点都超时：检查公网地址、安全组、主机防火墙和 NAT 端口转发；
3. SS 2022 可用但 REALITY 超时：基础链路正常，重点检查 Mihomo/Xray 兼容性、客户端时间、SNI，或网络对 REALITY 握手的干扰；
4. 修改 `.env` 端口后，需要重新初始化以更新订阅，随后执行 `docker compose up -d --force-recreate`。重新初始化会轮换全部凭据。

本项目固定 Xray `26.6.27`。Mihomo 文档指出 Xray `26.7.11+` 的 REALITY 行为可能不兼容，升级前请先备份并进行客户端实测。

## 迁移到另一台服务器

推荐在新服务器重新生成凭据：克隆仓库、配置 `.env`，然后运行 `./scripts/deploy.sh`。如果必须保持原订阅和密钥，可安全复制未提交的 `.env` 与整个 `data/` 目录，再执行：

```bash
docker compose up -d
```

迁移后若公网地址变化，需重新初始化生成订阅，或手动同步修改订阅中的 `server`。不要把 `data/` 提交到 Git。

## 更新、轮换与卸载

```bash
# 查看状态与日志
docker compose ps
docker compose logs -f

# 应用仓库更新
git pull --ff-only
docker compose pull
docker compose up -d

# 停止服务（保留配置）
docker compose down
```

轮换全部凭据前先备份 `data/`，然后执行 `./scripts/init.sh` 和 `docker compose up -d --force-recreate`。旧订阅会立即失效。

## 安全说明

- `.env`、`data/` 包含地址、私钥、UUID、SS 密钥和订阅，已被 Git 忽略；
- 订阅默认是带高熵随机路径的 HTTP，内容仍为明文。生产环境建议使用域名和 HTTPS 反向代理；
- REALITY 伪装目标应支持 TLS 1.3、可从服务器访问，且尽量不要使用 CDN 后端；
- 不要把 Xray 版本直接升级到未经 Mihomo 验证的新版本；
- 泄露订阅 URL 后应立即轮换全部凭据。

## 仓库结构

```text
compose.yaml          Xray 与 Nginx 编排
nginx/default.conf    静态订阅服务器
scripts/init.sh       生成密钥、服务端配置和订阅
scripts/deploy.sh     校验并启动服务
.env.example          非敏感参数模板
AGENTS.md             自动化维护约定
```

参考：[Xray REALITY 官方文档](https://xtls.github.io/en/config/transports/reality.html)、[Mihomo VLESS 文档](https://wiki.metacubex.one/config/proxies/vless/)、[Mihomo Shadowsocks 文档](https://wiki.metacubex.one/config/proxies/ss/)。
