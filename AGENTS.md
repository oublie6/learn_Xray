# AGENTS.md

## 项目目标

本仓库提供可重复的一键 Xray 部署和 Mihomo 订阅生成。默认可用路径是 Shadowsocks 2022，VLESS REALITY 为并行可选路径。所有改动应优先保证新服务器首次部署简单、现有部署升级可预测。

## 维护约定

- 配置模板只放非敏感默认值；禁止提交 `.env`、`data/`、UUID、私钥、SS 密钥或真实订阅令牌。
- Xray 镜像版本必须在 `compose.yaml` 与 `scripts/init.sh` 中保持一致。
- 修改端口时同步检查 `.env.example`、`compose.yaml`、`scripts/init.sh`、生成的订阅模板和 `README.md`。
- 多节点部署必须使用不同 `NODE_NAME`；节点名只允许安全的 ASCII 字符，避免未经转义的值破坏 YAML。
- 保持脚本可重复执行，并使用 `set -euo pipefail`。
- 服务容器继续以最小权限运行；不要无理由移除 `no-new-privileges` 或增加 Linux capabilities。
- 默认订阅必须能被当前稳定版 Mihomo 解析；REALITY 的版本升级需先核对 Mihomo 兼容性。
- 默认分流规则顺序保持为私有网络直连、国内域名直连、国内 IP 直连、最终代理；远程规则集固定使用可信来源并设置更新周期。
- 不要自动提交运行时生成的配置。需要测试轮换时使用临时目录，或先备份本机 `data/`。

## 修改后的最低验证

```bash
bash -n scripts/*.sh
docker compose --env-file .env.example config --quiet
git diff --check
```

涉及生成逻辑时，还应在隔离环境执行全新初始化，验证 Xray 配置、容器健康状态和订阅响应。提交前运行 `git status --short` 和暂存区敏感信息扫描，确认 `.env`、`data/` 未被跟踪。
