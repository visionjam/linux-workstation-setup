# linux-workstation-setup

一台 Linux 工作站（Ubuntu 24.04）的**完整环境配置 + 重建素材 + 设计说明**。
从一台 WSL2 工作站整理并脱敏而来，目标是：**克隆到任何一台普通 Ubuntu / Debian x86_64 主机，按步骤恢复出同样的工作环境**。

这个仓库不只给「配置文件」，还给「为什么」——每一处不明显的配置都带了注释或文档说明，
包括踩过的坑（这些坑大多和发行版、工具版本、网络环境有关，换台机器一样会踩）。

## 快速开始（新机器）

```bash
git clone git@github.com:visionjam/linux-workstation-setup.git
cd linux-workstation-setup

bash scripts/packages/install-apt.sh        # 1. 系统软件包（apt，自动 sudo）
bash scripts/packages/install-binaries.sh   # 2. 单文件二进制（固定版本 + SHA256 校验）
bash scripts/install.sh                     # 3. 部署配置到 $HOME（覆盖前自动备份）
```

然后按 `install.sh` 结尾打印的提示做几件手动事（填 API token、配 git 身份、装 nvm/uv 等）。
完整的分步说明、验证清单见 **[docs/migration.md](docs/migration.md)**。

## 仓库结构

| 路径 | 内容 |
|---|---|
| `home/` | 与 `$HOME` 同构的配置文件树（install.sh 会原样铺到 `$HOME`） |
| `scripts/install.sh` | 正向部署：`home/` → `$HOME`（幂等、带备份、支持 `--dry-run`） |
| `scripts/export.sh` | 反向同步：本机改了配置 → 按清单导出回仓库（`--check` 可查漂移） |
| `scripts/check-secrets.sh` | 提交前密钥扫描（pre-commit 钩子 + 推送前 `--history` 全历史扫描） |
| `scripts/packages/` | apt 包清单、单文件二进制清单（含 URL/SHA256）与安装器 |
| `docs/environment.md` | **环境说明书**：每个配置为什么这么写、踩过哪些坑 |
| `docs/wsl-notes.md` | 来源机器的 WSL 专属笔记（普通 Linux 可跳过） |
| `docs/migration.md` | 新机器迁移手册（含验证清单） |

各脚本的头部注释就是完整用法（`-h` 可看）。

## 安全声明

本仓库**不含任何密钥**：

- token / API key / cookie 只以占位符形式出现在 `*.example` 模板里（如 `home/.claude/settings.json.example`）；
- `.gitignore` 与 `scripts/check-secrets.sh` 双重拦截（提交前钩子自动跑，推送前还有全历史扫描）；
- 个人标识（用户名、主机名、私人路径、个人常用域名）在整理时已全部泛化。

## 日常维护

```bash
# 本机改了配置，想同步回仓库：
scripts/export.sh            # 按清单把 raw 模式的文件导出（manual 的需人工合并）
git diff                     # 人工复核
scripts/check-secrets.sh     # 扫描通过再提交

# 升级某个单文件二进制：
# 改 scripts/packages/binaries.tsv 对应行的 version/url/sha256
# （sha256 从 GitHub Release API 的 assets[].digest 拿），重跑 install-binaries.sh
```

## License

[MIT](LICENSE)
