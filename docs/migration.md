# 新机器迁移手册

目标：在一台**全新的 Ubuntu / Debian x86_64 主机**上，从零恢复到与本仓库一致的环境。
每一步都可以单独重跑（幂等），中途失败不会把系统搞死。

> 迁往的是另一台 WSL？前面的步骤通用，另读 [wsl-notes.md](wsl-notes.md) 补齐宿主侧配置。

## 前置条件

- Ubuntu 24.04 / Debian 12+（x86_64），有一个能 `sudo` 的普通账号
- 能访问 GitHub（国内网络先准备好代理或镜像，见步骤 2 的提示）
- 大约 3–5GB 磁盘空间（不含 Docker 镜像）

## 步骤 1：拿仓库

```bash
git clone git@github.com:visionjam/linux-workstation-setup.git
cd linux-workstation-setup
git config --local core.hooksPath .githooks   # 启用提交前密钥扫描钩子（克隆后只需做一次）
```

（没有 SSH key 就先用 `https://` 克隆；生成 SSH key 并加到 GitHub 的事可以之后做。）

## 步骤 2：系统软件包

```bash
bash scripts/packages/install-apt.sh            # 先看计划可加 --dry-run
```

- 内部就是 `apt-get update` + 按 `scripts/packages/apt-packages.txt` 逐个装
- 个别包来自 universe 仓库，未启用会失败——`sudo add-apt-repository universe` 后重跑即可
- **Docker 那几行默认注释着**：需要 Docker 就先按官方文档添加 apt 源，再取消注释、重跑
- 为什么最先装它：后面几步依赖 `curl` / `unzip` 之类

## 步骤 3：单文件二进制

```bash
bash scripts/packages/install-binaries.sh --list        # 先看清单（10 项）
bash scripts/packages/install-binaries.sh               # 安装/升级/跳过 自动判断
```

- 每项都带**固定版本 + SHA256**（`scripts/packages/binaries.tsv`），下载走断点续传 + 校验重试，
  截断会被发现并自动续传（这段防护的由来见 [environment.md §5.4](environment.md#54-github-下载截断是本环境的常态重要)）
- 国内直连 GitHub 慢/断的话：
  ```bash
  export HTTPS_PROXY=http://127.0.0.1:7890   # 换成你自己的代理地址
  bash scripts/packages/install-binaries.sh
  ```
- fastfetch 一项会走 `sudo apt`（本地 .deb），会提示输密码

## 步骤 4：部署配置文件

```bash
bash scripts/install.sh                     # 先看计划可加 --dry-run
```

- 把仓库 `home/` 树铺到 `$HOME`：覆盖前逐文件备份为 `*.before-install`
  （已有的 `.before-install` 永不静默覆盖，内容再漂移会存时间戳副本）
- 收尾自动做：`~/.local/bin/{fd,bat}` 兼容软链、hooks/探针执行位、`~/.ssh` 权限收紧
- **不会**碰你的 `~/.claude/settings.json`（仓库只装 `settings.json.example`）

## 步骤 5：几件必须手动的事

`install.sh` 结尾会再列一遍清单，这里给上下文：

1. **填 API token**：以 `~/.claude/settings.json.example` 为模板，填好
   `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` 后另存为 `~/.claude/settings.json`。
   不用 Claude Code 可跳过。
2. **git 身份**（`~/.gitconfig` 里是「待填写」占位符）：
   ```bash
   git config --global user.name  '你的名字'
   git config --global user.email '你的邮箱'   # 公开项目建议用 GitHub 的 noreply 邮箱
   ```
3. **nvm + Node**（官方安装脚本，会写 `~/.nvm`）：
   ```bash
   export NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node   # 国内加速
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash   # 版本号按官方 README 取最新
   # 重开 shell 后：
   nvm install --lts
   ~/.local/bin/nvm-link       # 把 default 版链接进 ~/.local/bin（换版本后要重跑）
   ```
4. **uv**（Python 工具链）：
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```
5. **Claude Code**：按官方文档（docs.claude.com 的 Claude Code 安装页）装 native 二进制版。
   受限网络注意：更新链路走的域名可能被墙，需在 `settings.json` 的 `env` 里配好代理。
6. **中文字体生效**：apt 已装 `fonts-noto-cjk`，确认一下缓存重建与匹配：
   ```bash
   fc-cache -f
   fc-match 中        # 返回 Noto 才对，返回 DejaVu 就是没配好
   ```
   （已装字体但 GUI 程序仍乱码 → 重启那个程序，它启动时冻结了旧字体表。）

## 步骤 6：验证清单

```bash
# 新开一个终端（或 source ~/.bashrc）后逐条过：

# 1. 提示符变成 starship 样式，且出现一次 fastfetch 开机图
# 2. 兼容命令就位
fd --version && bat --version

# 3. 二进制全家福（应列出 10 个版本）
for b in starship atuin lazygit yq duckdb glow yazi herdr; do
  printf '%-10s %s\n' "$b" "$("$HOME/.local/bin/$b" --version 2>&1 | head -1)"
done
nvim --version | head -1
fastfetch --version | head -1

# 4. 代理变量（如果用了代理）
curl -sv https://example.com 2>&1 | grep -E 'Uses proxy|Trying|Connected' | head -3

# 5. Neovim 插件按锁文件复刻
#    打开 nvim → :Lazy restore（首次会自动 clone 全部插件）
#    :checkhealth 看总体

# 6. 仓库自身的防线仍然干净
bash scripts/check-secrets.sh --all         # 期望：BLOCK 0
```

## 步骤 7：之后的日常维护

```bash
# 本机改了配置 → 同步回仓库：
bash scripts/export.sh              # 清单驱动的反向导出（manual 模式的文件需人工合并）
git diff                            # 逐文件复核
bash scripts/check-secrets.sh       # 扫描通过再 commit（pre-commit 钩子会再拦一道）

# 升级某个二进制：
#   改 scripts/packages/binaries.tsv 对应行的 version / url / sha256
#   （sha256 从 GitHub Release API 的 assets[].digest 拿）
bash scripts/packages/install-binaries.sh

# 重装/换机演练（不碰真实 $HOME 的完整测试）：
T=$(mktemp -d)
HOME="$T" bash scripts/install.sh --yes
```

## 排错速查

| 症状 | 先看 |
|---|---|
| 二进制下载反复失败/截断 | environment.md §5.4（代理 + 断点续传） |
| 命令「装了却找不到」 | 新开终端；确认 `~/.local/bin` 在 PATH（`.bashrc` 第 1 节） |
| 代理行为异常 / 时灵时不灵 | environment.md §12.1（`no_proxy` 大小写双份） |
| GUI 中文乱码 | environment.md §11（三层修复 + 重启程序） |
| node 在某些场景找不到 | environment.md §7（`nvm-link` 补的正是那个缺口） |
| herdr 配置改了不生效 | environment.md §8（`config check` 后再 `reload-config`） |
