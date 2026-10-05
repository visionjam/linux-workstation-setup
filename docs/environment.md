# 环境说明书

> 这份文档讲「为什么」：每一个不明显的配置选择背后的问题、机制和坑。
> 配置文件本体在 [`home/`](../home/)，重建步骤在 [`migration.md`](migration.md)，
> 来源机器的 WSL2 专属内容在 [`wsl-notes.md`](wsl-notes.md)。
>
> **文档约定：描述「当前状态」的数字必须带测量日期**（版本号、耗时、空间这类）。
> 不带日期的状态数字视为可能已腐烂——先重测再引用。历史性数字（如「安装时占 17.7MB」）不受此限。

## 0. 设计原则

1. **显式优于隐式**：不依赖发行版默认值碰巧正确；每个不明显的选择都留注释说明原因。
2. **幂等**：所有脚本和 `.bashrc` 片段都写成「重复执行结果不变」——PATH 追加用 `case` 判断、
   配置部署逐文件比对、二进制安装先查版本。
3. **先备份再动手**：部署脚本覆盖任何文件前先存 `.before-install` 副本，且已有的备份绝不被静默覆盖。
4. **不轻信下载**：所有从 GitHub 拉的文件都带 SHA256 校验 + 断点续传（原因见 §5.4）。
5. **文档记录「为什么」**：坑踩过一次就该进文档，而不是留在某次终端滚屏里。

## 1. 系统概览

- 基础：**Ubuntu 24.04 LTS / x86_64**（Debian 系同理；命令细节按 24.04 写）
- 用户级优先：能不装系统级的都装用户级（`~/.local/bin`、`~/.local/opt`、`~/.config`），
  少用 sudo、少碰 `/usr`
- 程序入口集中在 **`~/.local/bin`**（PATH 里前置），`.bashrc` 第 1 节负责加 PATH（幂等写法）
- `EDITOR`/`VISUAL` 设为 `code --wait`——`--wait` 是关键，不加的话 VS Code 一启动命令就返回、
  文件还是空的（git commit、`crontab -e` 场景）

`home/.bashrc` 的结构：前半是 Ubuntu 原版模板，后半是自制分节（PATH / 编辑器 / nvm / 代理白名单 /
fastfetch 开机图 / 现代 CLI 接线）。每一节都写了为什么。

## 2. GPU 与 CUDA（NVIDIA 用户）

实测平台：RTX 5060 Laptop（Blackwell 架构）——以下结论对 RTX 50 系通用：

- **RTX 50 系 = Blackwell = `sm_120`**，装 PyTorch 必须用 **cu128 及以上**的轮子：
  ```bash
  pip install torch --index-url https://download.pytorch.org/whl/cu128
  ```
- 装成 cu121/cu124 会报 `CUDA error: no kernel image is available for execution on the device`。
  **这句报错长得像「驱动没装」，实际是架构不匹配**——git blame 一下自己的安装命令，别去重装驱动。
- torch ≥ 2.7 / triton ≥ 3.3 才带 sm_120 支持。
- WSL 特有的 GPU 通路（`/dev/dxg`、`/usr/lib/wsl/lib`）见 [wsl-notes.md](wsl-notes.md)。

## 3. Python：uv 优先，不用系统 pip

Ubuntu 24.04 的系统 Python **没有 pip**（Debian 系刻意拆的），且 PEP 668 会拦全局安装
（`externally-managed-environment`）。所以：

- **装任何 Python 包之前先想到 uv**（[astral.sh/uv](https://astral.sh/uv)，装在 `~/.local/bin`）：
  ```bash
  uv venv            # 建 .venv（自带 pip）
  uv pip install X   # pip 兼容接口
  uv add X           # 项目模式：写 pyproject.toml + 锁文件
  uv run X           # 在项目环境里跑，自动同步依赖
  uv python install  # 装别的 Python 版本（不动系统的）
  ```
- `python3-venv` 和 `python3-dev` 用 apt 装过：前者补回 `ensurepip`（`python3 -m venv` 可用），
  后者提供 `Python.h`（写 C 扩展 / pybind11 / 编译扩展时必需）。
- **镜像配置是两份独立的文件**（重要陷阱）：`~/.config/uv/uv.toml` 管 uv、
  `~/.config/pip/pip.conf` 管 venv 里的 pip。**uv 刻意不读 pip.conf**（Astral 的设计决定），
  两份要各自维护，改一个不影响另一个。
- 镜像换成国内源是可选优化；不在国内的网络环境删掉这两个文件即可（恢复官方源）。
  临时绕开：`uv pip install --default-index https://pypi.org/simple <包名>`。

## 4. C / C++ 工具链

- `build-essential` 是**元包**（自身不含任何可执行文件，只有文档和包清单）。它的直接依赖里
  没有 `libstdc++-13-dev`——那是 `g++` 自己依赖带进来的。缺 `libc6-dev` 的典型症状是
  **能编译但链接失败**（`undefined reference to main`）。
- **gcc 13 默认标准是 C++17**：用 C++20 特性（`std::ranges`、`std::views`）必须显式
  `-std=c++20`，否则报 `has not been declared`。CMake 里写 `set(CMAKE_CXX_STANDARD 20)`。
- 验证工具链别只看 `--version`，要真跑：
  ```bash
  g++ -std=c++20 -Wall -Wextra -o t t.cpp && ./t
  cmake -S . -B build && cmake --build build
  gdb -batch -ex "break main" -ex "run" ./t
  ```

## 5. CLI 工具链

### 5.1 apt 装的（精选，完整清单在 `scripts/packages/apt-packages.txt`）

按用途分：诊断（strace/ltrace/valgrind/pv/hyperfine/tldr）、网络（dig/nmap/tcpdump/mtr/httpie）、
归档（unzip/zstd/lz4/7zip）、数据（sqlite3/sd/gron/miller/qalc）、监控（btop/duf/glances/s-tui）、
Git（gh/tig/git-lfs）、媒体（ffmpeg/imagemagick/chafa/asciinema）、交互（eza/zoxide/direnv）等。

三个改名陷阱：

| 上游文档里叫 | Ubuntu 实际命令 | 处理 |
|---|---|---|
| `fd` | `fdfind` | `install.sh` 在 `~/.local/bin` 建 `fd` 软链 |
| `bat` | `batcat` | 同上 |
| `iotop` | alternatives 指向 `iotop-py` | 直接敲 `iotop` 即可，排查时知道真名 |

`imagemagick` 在 24.04 是 IM6：命令叫 `convert`，**不是** `magick`。

### 5.2 手动装的单文件二进制

`scripts/packages/binaries.tsv` 维护了 starship / atuin / lazygit / yq / duckdb / glow /
yazi(+ya) / neovim / herdr / fastfetch 十个的**固定版本 + 下载 URL + SHA256**，
`install-binaries.sh` 按表安装（幂等：先 `--version` 比对）。

两个特例：

- **fastfetch 是 .deb**（不在任何 apt 源里），走 `sudo apt-get install ./x.deb` 以解析依赖。
  ⚠️ 别选 `-polyfilled` 变体（那是给 glibc 2.17 老发行版的）。
- **neovim 是目录**（解到 `~/.local/opt/`，`~/.local/bin/nvim` 是相对软链——相对链接才能
  跟 `$HOME` 一起搬家）。

### 5.3 为什么是 fastfetch 不是 neofetch

实测：fastfetch **23ms/次**，neofetch 是纯 bash 脚本要几百毫秒——差一个数量级。
`home/.bashrc` 第 5 节用它打印「每次开机只刷一次」的欢迎图（实现细节见注释：
父进程判定 + boot_id 比对两道闸）。

### 5.4 GitHub 下载截断是本环境的常态（重要）

本仓库来源环境实测：**从 GitHub 拉大文件会静默中途截断**（`curl: (18) Transferred a partial file`），
一天内复现多次；7.2MB 的文件曾只下来 442KB。防范手段（`install-binaries.sh` 已内置）：

```bash
curl -fSL --retry 3 --retry-all-errors -C - -o file URL   # -C - = 断点续传
sha256sum -c 校验                                          # 唯一能发现截断的手段
```

校验和来源：GitHub Release API 的 `assets[].digest` 字段（`sha256:...`）或官方 `.sha256` 文件。

## 6. 现代 CLI 接线（`.bashrc` 最后一节）

| 工具 | 给的能力 |
|---|---|
| `fzf` | Ctrl-T 选文件路径 / Alt-C 跳目录 |
| `atuin` | **Ctrl-R = 全量历史**（SQLite，绕开 HISTSIZE=1000 的限制） |
| `starship` | 提示符（个性化在 `~/.config/starship.toml`） |
| `zoxide` | `z 关键词` 按 frecency 跳目录；`zi` 交互版 |
| `direnv` | 目录级 `.envrc` 自动加载/卸载 |

**加载顺序有讲究，别重排**：fzf 的 key-bindings 也想占 Ctrl-R，atuin 必须放最后才能把它
收回来（atuin 的 bind 是先 unbind 再覆盖）。最终 Ctrl-R 归 atuin、Ctrl-T/Alt-C 归 fzf。

两个细节：

- atuin 的 `--disable-up-arrow`（保住「↑ = 上一条命令」原生习惯）和 `--disable-ai`
  （不给「?」键弹没配 key 的 AI 搜索）。
- direnv 的 `.envrc` **首次必须 `direnv allow`**——这是防「clone 个仓库就被执行任意代码」
  的安全设计，不是坏了。

## 7. Node.js：nvm + nvm-link

- 用 **nvm 装的 Linux 原生 Node**，装在 `~/.nvm`。不要用任何「往 Linux 目录装 Windows 二进制」
  的方案（nvm4w 之类，会 `Exec format error`）。
- 国内下载 node 走镜像：`export NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node`。
- **`nvm-link` 补一个真实存在的缺口**（`home/.local/bin/nvm-link`）：
  nvm 只在 `.bashrc` 里加载，而 `.bashrc` 有「非交互就 return」的守卫 →
  **登录但非交互的 shell**（桌面启动器、ssh 远程命令、IDE 任务运行器、`bash -l -c`）
  有 `~/.local/bin` 在 PATH 里却拿不到 node。`nvm-link` 把当前 default 版本的
  `node/npm/npx/corepack` 软链进 `~/.local/bin`，正好落在这个缺口上。
- ⚠️ **`nvm install` 或 `nvm alias default <新版本>` 之后必须重跑 `nvm-link`**——
  软链指向具体版本目录，不会自动跟随。`node --version` 和 `nvm current` 对不上就是该跑了。
- 为什么不做成动态 wrapper：wrapper 每次要 source 一遍 `nvm.sh`（实测约 80ms），
  而 node 会被构建工具链嵌套调用几十次，固定开销不可接受；符号链接零开销。

## 8. herdr（终端 agent 复用器）

不是窗口管理器——它管不了顶层窗口，只活在终端里，是 tmux 的同类替代。
层级：`session → workspace → tab → pane`。后台 server 持有真实 PTY，client 只是渲染层，
**detach 或关终端都不影响运行**（真正停止是 `herdr server stop`，会连带杀掉 pane 里的进程）。

配置与运维要点：

- 配置在 `~/.config/herdr/config.toml`（本仓库只写与默认值的**差异**，所以文件很小）
- 改完**必须** `herdr server reload-config`（手改文件不会自动重读），TUI 里也可 `prefix+shift+r`
- **改完先 `herdr config check`**：TOML 解析错会让**整份配置回落默认值**、语义错（如 interval=0）
  只隐藏那一条。`HERDR_CONFIG_PATH=/tmp/x.toml` 可在临时文件上试，不碰真配置
- 权威 schema：`herdr --help` 底部给的线上 `config-reference.json`（每个键带 type/default/description），
  别靠 `strings` 考古二进制
- 顶栏探针脚本放 `~/.config/herdr/status.d/`（本仓库带 4 个：代理三级/负载/内存/GPU）。
  探针机制：`/bin/sh -lc` 执行、**只取输出最后一行**、按 interval 跑、超时清空该条目。
  路径建议用 `$HOME` 写法（sh 会展开；server 派生进程的 PATH 未必继承你终端那套）
- 键位：前缀默认 `ctrl+b`；`prefix+c` 新 tab、`prefix+minus` 上下分屏、`prefix+h/j/k/l` 移动焦点、
  `prefix+q` detach、`prefix+?` 是实时键位总表

## 9. Neovim

- 官方 **0.12.5** 装在 `~/.local/opt/nvim-linux-x86_64/`，`~/.local/bin/nvim` 是相对软链
  （apt 的旧版可留作备用）。升级 = 删旧目录、解新包，软链不动。
- 配置：`~/.config/nvim/init.lua` 单文件（只写「有意选择」的项，Neovim 默认值够好的不重复写）
  + `lazy-lock.json` 锁插件版本（插件本体不入 git，装好 nvim 后开一次 `:Lazy restore` 按锁文件复刻）。
- 路线是纯键盘：关鼠标、相对行号（练 `5j`/`d3k` 计数的可视反馈）、`:Lazy` 管理插件、
  `:checkhealth` 全身体验。
- 剪贴板：`clipboard = "unnamedplus"`，Linux 上需要 `xclip` 或 `wl-clipboard` 之一。
- 无 Nerd Font 环境：不装图标依赖、neo-tree 图标显式关（防豆腐块）；装了字体再打开即可。

## 10. Claude Code

- 配置走 **`~/.claude/settings.json` 的 `env` 块**（官方推荐做法，不是 shell 环境变量），
  CLI 自己解析后注入到自己的进程树。
- 本仓库只带 **`settings.json.example` 模板**（真实文件含 API token，永不入库）。
  模板演示了两件事：
  - 用第三方 **Anthropic 兼容端点**（如 DeepSeek 的 `/anthropic`）时的 env 写法
    （`ANTHROPIC_BASE_URL` + 各档模型映射）；
  - `skipWebFetchPreflight: true`——某些受限网络下 WebFetch 的预检会全域名失败，
    这个官方开关跳过预检（拿不准就别开）。
- Hooks 两个（`home/.claude/hooks/`）：`check-claude-md.sh`（会话开始提示 CLAUDE.md 已加载）、
  `auto-snapshot.sh`（距上次快照超 24h 才自动打一份，依赖你自己的快照脚本，缺失时静默跳过）。
- **原生安装的自动更新陷阱**（值得单独记）：`.claude.json` 里的 `autoUpdates: false`
  对原生安装**无效**——原生安装器会同时写入三个字段把它豁免掉。真正的开关是环境变量
  **`DISABLE_AUTOUPDATER=1`**（配置层的键会被保护绕过，环境变量不会）。
  另外 `.last-update-result.json` 的 `install_failed` 在「无新版本可装」时也会写，
  判断更新是否正常要对照 `versions/` 目录和 daemon 日志。

## 11. 中文字体（GUI 程序乱码的三层修复）

症状：终端正常、GUI 程序（Electron/GTK）中文显示成方块。根因是**三件事叠加**，缺一不可：

1. 系统可能只有拉丁字体（`fc-list :lang=zh | wc -l` 为 0 就是它）
2. `LANG=C.UTF-8` 没告诉 fontconfig「用户看中文」→ 汉字被匹配到 DejaVu
3. 装完字体**必须** `fc-cache -f` 重建缓存，且**重启 GUI 程序**（缓存没建好时启动的程序
   会一直用坏字体表）

修复：`sudo apt install fonts-noto-cjk` + `fc-cache -f` + 用户级 fontconfig 弱回退配置
（即 `home/.config/fontconfig/fonts.conf`，把 Noto CJK 追加到所有字体请求后面）。

排查命令：`fc-match 中`（返回 DejaVu 就是没配好）、`FC_LANG=zh-cn fc-match sans-serif`、
`fc-match -s 中 | head -5`（看回退链排位）。**不要**为了中文改 `LANG`——那会让 apt/git
的输出变中文，反而更难搜报错。

## 12. 网络与代理

### 12.1 环境变量名区分大小写（血泪教训）

`no_proxy` 和 `NO_PROXY` 是**两个独立变量**，不是同一个的两种写法。而 curl / python-requests /
undici 查这两个时**小写优先**——只改大写等于没改，而且**不报任何错**。

```bash
# 验证流量到底走没走代理：
curl -sv https://example.com 2>&1 | grep -E 'Uses proxy|Trying'
# Trying 127.0.0.1:7890 → 走了代理；Trying <真实IP> → 直连
```

`home/.bashrc` 第 4 节用 `case` 幂等追加的方式补齐白名单（同时补大小写两份）。
需要直连的域名按同样格式加。

### 12.2 代理故障分层判据

代理「活着但上游死了」时的三档现象，一层层排除：

| 现象 | 含义 |
|---|---|
| 端口连不上 | 代理进程没跑 |
| `CONNECT` 返非 200 | 代理拒绝转发（规则 / 认证） |
| `CONNECT` 返 200，但随即 `SSL_ERROR_SYSCALL` | 代理收下了请求，但它自己出不去 |
| **明文 HTTP 返 `502 Bad Gateway`** | 同上——**502 是代理自己生成的**，最一锤定音 |

⚠️ 别用 `ss -ltn | grep 7890` 判断代理死活——网络命名空间共享的场景下（容器/WSL）
监听端可能不在本命名空间的 socket 表里，会误判成「代理已挂」。判断死活一律用 curl 实测。

### 12.3 DNS 污染的自判特征

同一 resolver 对同一域名**每次返回不同答案** + 答案的归属 AS 与服务无关 + 连上去是超时
（不是拒绝）——三条凑齐就是 DNS 污染。真实地址不会这样。这类问题在代理/DNS 层解决，
应用层改什么都没用。

## 13. 备份与同步体系

三层，各解决一个问题：

1. **本仓库（配置的版本化）**：`install.sh` 正向部署（带 `.before-install` 备份）、
   `export.sh` 反向把本机改动按清单同步回仓库。清单（`export-manifest.tsv`）是唯一事实来源——
   本机新增文件不会被自动收编，得人工加一行，这是刻意的「禁自动猜」闸门。
2. **密钥防线**：`check-secrets.sh` 三模式（`--staged` 提交钩子 / `--all` 工作树 /
   `--history` 全历史）。规则是数据文件（`check-secrets.patterns`），BLOCK/WARN 两级，
   命中输出自动打码。
3. **整机快照（未随仓库发布）**：来源环境另有一套 `snapshot.sh`→tar.gz→`restore.sh`
   的本地快照体系（含保留策略：最近 10 份 + 每个日期留当天最后一份）。
   思路可借鉴：快照是「状态产物」、仓库是「源码」，两者不要混。

## 14. 文档与数字的约定

**描述「当前状态」的数字必须带测量日期**（磁盘占用、版本号、耗时、内存）。
不带日期的状态数字视为可能已腐烂——先重测再更新，不要沿用。
历史性数字（「安装时占 17.7MB」这类注释）不受此限。
这条规则来自一次真实教训：文档里「E 盘剩 24GB」三天后就变成了 17GB。
