# WSL 专属笔记

> 本仓库的来源机器是一台 **WSL2 上的 Ubuntu 24.04**（宿主 Windows）。
> 正文环境是通用的——这个文件收集 WSL 专属的机制、坑和取舍。
> 迁移到普通 Linux 主机的读者**可以整篇跳过**；迁移到另一台 WSL 的读者建议一读。

## 1. GPU 通路：`/dev/dxg` 不是 `/dev/dri`

WSL2 的 GPU 分两条独立通路，**别因为「没有 `/dev/dri`」就断定没 GPU**：

| 设备节点 | 管线 | 承载 |
|---|---|---|
| `/dev/dxg` | D3D12 半虚拟化 | **CUDA / DirectML（计算栈）** |
| `/dev/dri` | DRM/KMS | Vulkan / VA-API / 合成器（图形栈） |

- 只有 `/dev/dxg` 时：**计算可用、图形加速受限**——nvidia-smi、torch、NVML（nvtop/btop 的 GPU 面板）
  都走计算栈，正常可用
- 配套库在 `/usr/lib/wsl/lib/`（`libcuda.so.1` 是转发到 Windows 驱动的 stub），
  该目录通常已在 PATH → `nvidia-smi` 直接能敲
- RTX 50 系（Blackwell/sm_120）的 CUDA 轮子要求见 [environment.md §2](environment.md#2-gpu-与-cuda-nvidia-用户)

## 2. `/etc/wsl.conf`：刻意切断 Windows PATH

```ini
[interop]
appendWindowsPath=false
```

效果：Windows 的程序目录**不再自动注入 Linux PATH**——PATH 里只剩 Linux 自己的路径，
保持「专用 Linux 工作站」的独立感。

- ⚠️ 这不影响**文件访问**：`/mnt/c`、`/mnt/d` 照常读写；切断的只是「命令查找」
- Windows 命令仍可调用，用完整路径：
  ```bash
  /mnt/c/Windows/System32/clip.exe        # 写 Windows 剪贴板
  /mnt/c/Windows/explorer.exe .           # 用资源管理器打开当前目录
  ```
- 个别还要用的 Windows 工具（如 VS Code 的 `code`）在 `.bashrc` 里**手工**按需加回 PATH
  （本仓库的公开版删掉了这条，因为路径是机器专属的）

## 3. 网络：mirrored 模式与 `127.0.0.1` 语义

宿主 `.wslconfig` 开 `networkingMode=mirrored` 后，WSL 与 Windows 共享网络命名空间 →
**WSL 里的 `127.0.0.1:7890` 就是 Windows 上的代理端口**。配置文件里的
`HTTP_PROXY=http://127.0.0.1:7890` 靠的就是这个语义。

⚠️ 如果哪天切回 NAT 模式，`127.0.0.1` 会指向 WSL 自己，代理立刻失效**且极难排查**
（现象是超时而非拒绝）。判断代理死活一律用 curl 实测，别用 `ss`（见
[environment.md §12.2](environment.md#122-代理故障分层判据)）。

DNS 污染观察：WSL 的 DNS 转发地址会返回**每次不同的假地址**（同一 resolver、答案归属 AS
与服务无关、连上去超时）——判别特征见 environment.md §12.3。

## 4. WSLg 图形栈的两个坑

WSLg（跑 GUI 程序的能力）在独立的 Mariner 容器里。踩过的两个坑：

1. **PulseAudio 状态不可写**：`pactl set-sink-volume` 改完，重启 WSL 就回 100%——
   音量只能写死在调用方。办法是放一个**顶名包装脚本** `~/.local/bin/paplay`
   （内容是一行 `exec /usr/bin/paplay --volume=32768 "$@"`），把「响不响」升级成「响多大声」。
   顶名成立的前提：调用方（如 herdr server）的 PATH 里 `~/.local/bin` 排在 `/usr/bin` 前面。
   ⚠️ 排查「声音行为不对」时先想起有这个文件；要原版走全路径 `/usr/bin/paplay`。
   （公开版仓库未收编它——普通 Linux 上 PulseAudio/PipeWire 的音量是持久的。）
2. **合成器尝试**：装过 sway 做平铺合成器，后来卸掉了（WSLg 的 nested 合成场景问题多，
   收益低）。配置存档保留，教训：WSL 里别跟图形栈较劲，终端才是主场。

## 5. fastfetch 开机图与「幽灵会话」（一个完整的 WSL 排错案例）

`home/.bashrc` 第 5 节的开机图有两道闸（父进程判定 + boot_id 比对）。WSL 专属的坑在
**第二道闸的对手不是活人**：

- 每次 boot 后约 6 秒，WSL 的 `init-systemd` 会为「启动 `systemd --user`」拉一个
  **无窗口引导会话**：`/bin/login -f → bash`，占着没有客户端在读的 pty
  （`loginctl` 里的 session 1、`who` 里那条从没开过的 pts）
- 它的 bash 照样读 `.bashrc` → **永远抢先把「本 boot 已刷」的配额写掉，图打进虚空**
- 修法：跳过名单加 `login`（本版 WSL 里真实客户端走 Relay→bash 直连、不经 `login(1)`，
  不误伤）
- 识别法：`loginctl show-session 1`（Service=login）+ 比对 shell 的
  `/proc/<pid>/environ` 里有没有 `WT_SESSION` / `TERM`

另一个 WSL 排错锚点：**宿主睡眠时 VM 冻结、醒来时钟前推** →
`uptime` 只算「醒着」的时间、`btime`/`ps lstart` 会偏晚一个睡眠时长。
**判断「重启过没有」用 `boot_id`，不要用 uptime**。

## 6. 换机与备份（WSL 特有方式）

- **整机镜像**：`wsl --export <发行版> <路径>.tar` / `wsl --import ...`（在 PowerShell 里跑）。
  ⚠️ 导出的 tar 里**含密钥**（.ssh 私钥、各工具凭据），不可外传；发布仓库前先脱敏
- `ext4.vhdx` **只增不减**：删除文件不会立刻归还给 Windows；盘位规划要留足够余量
- **不要搬的目录**：`~/.vscode-server`（按 VS Code 版本编译的，重连自动重建）、
  `~/.nvm/versions`（重装更快）、`~/.local/share/claude`（重装原生二进制）、
  docker 镜像（`docker compose up -d` 重建）
- Windows 侧另有独立配置（`.wslconfig` 的 mirrored 设置、代理程序本体）——
  这些**不在 Linux 快照里**，换 Windows 机器要手动补

## 7. 没随仓库收编的 WSL 专属配置（存档说明）

以下在来源机器上存在、但在公开版被**刻意剥离**（普通 Linux 用不上或另有做法）：

| 项 | 去向 |
|---|---|
| `paplay` 音量包装脚本 | 见本文 §4（普通 Linux 不需要） |
| `/etc/wsl.conf` 应用脚本 | 见本文 §2 |
| Windows VS Code PATH 追加（`.bashrc`） | 见本文 §2 |
| vault 目录快捷别名（指向 `/mnt/c` 下某目录） | 机器专属，删 |
| sway 合成器配置 | 已弃用（§4） |
