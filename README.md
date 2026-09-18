# learn_Xray

用于学习和自建 Xray 的最小部署项目：服务端使用 **VLESS + TCP + XTLS Vision + REALITY**，并通过静态 HTTP 地址向 **Mihomo（Clash.Meta）** 提供订阅。

> 仅在当地法律和网络服务条款允许的范围内使用。请勿用于未授权访问、攻击或其他违法活动。

## 架构与端口

- `xray`：REALITY 入口，默认监听宿主机 TCP `443`。
- `subscription`：Nginx 静态订阅，默认监听宿主机 TCP `8080`。
- `data/`：初始化后生成的私钥、UUID 和订阅，已由 `.gitignore` 排除，禁止提交。

本项目固定 Xray `25.6.8`。Mihomo 文档说明 Xray `26.7.11+` 的 REALITY 变更可能不兼容，升级前务必完成客户端实测。

## 前置条件

一台具有公网 IP 的 Linux 服务器，并安装 Docker Engine 与 Docker Compose 插件。云安全组和主机防火墙需放行：

- TCP `443`：代理入口；
- TCP `8080`：订阅入口（建议进一步用防火墙限制来源，或参照下文启用 HTTPS）。

如果服务器已有程序占用这些端口，可在 `.env` 修改宿主机端口。

## 部署

```bash
git clone https://github.com/oublie6/learn_Xray.git
cd learn_Xray
cp .env.example .env
```

编辑 `.env`，至少将 `SERVER_ADDRESS` 改为服务器公网 IP 或解析到它的域名，然后执行：

```bash
./scripts/deploy.sh
```

脚本会生成 UUID、REALITY X25519 密钥、Short ID 和随机订阅令牌，然后启动服务。订阅 URL 会显示在终端，也可随时查看：

```bash
sed -n 's/^SUBSCRIPTION_URL=//p' data/deployment.env
docker compose ps
docker compose logs --tail=100 xray
```

初始化会覆盖本机现有凭据与订阅。需要轮换全部凭据时，先备份 `data/`，再运行 `./scripts/init.sh` 和 `docker compose up -d`。

## Clash / Mihomo 使用

需要使用支持 VLESS REALITY 的 Mihomo 内核客户端；旧版 Clash Premium 不支持。将脚本输出的 URL 粘贴到客户端的“订阅/配置”处并更新，然后选择 `PROXY` 策略组。

服务端自检：

```bash
docker compose exec xray xray run -test -c /etc/xray/config.json
curl --fail "$(sed -n 's/^SUBSCRIPTION_URL=//p' data/deployment.env)"
```

若无法连接，依次检查公网 IP/域名、云安全组、系统防火墙、端口占用和容器日志。NAT 后的机器还需配置端口转发。

## 安全与运维

- `.env` 和 `data/` 含部署信息或密钥，绝不能提交 Git；仓库只保存模板。
- 默认订阅 URL 使用高熵随机路径，但 HTTP 内容仍是明文。生产环境建议为订阅域名单独配置 HTTPS 反向代理，并只开放 HTTPS 端口。
- REALITY 的伪装目标应支持 TLS 1.3、与服务器网络连通，且尽量不要选择 CDN 后端；可在 `.env` 同时修改 `REALITY_SERVER_NAME` 和 `REALITY_TARGET`。
- 定期执行 `docker compose pull`，但升级 Xray 大版本前先核对 Mihomo 兼容性并备份 `data/`。
- 停止服务：`docker compose down`。此命令不会删除 `data/`。

## 文件说明

```text
compose.yaml          Docker Compose 编排
nginx/default.conf    订阅静态服务器配置
scripts/init.sh       生成服务端配置、密钥和 Clash 订阅
scripts/deploy.sh     校验并启动服务
.env.example          非敏感部署参数模板
```

参考：[Xray REALITY 官方文档](https://xtls.github.io/en/config/transports/reality.html)、[Mihomo VLESS 配置](https://wiki.metacubex.one/config/proxies/vless/)。
