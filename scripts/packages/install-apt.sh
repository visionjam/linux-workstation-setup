#!/usr/bin/env bash
# ============================================================
# install-apt.sh —— 按 apt-packages.txt 安装软件包
#
# 用法：scripts/packages/install-apt.sh [--dry-run]
#   （首次在新机器上跑：先确保 apt 能出网）
#
# 说明：
#   · 内部用 sudo apt-get（apt 面向人的输出不承诺稳定性，脚本一律用 apt-get）
#   · --dry-run 走 apt-get install -s（模拟，不写盘）
#   · 文件里 Docker 那几行默认注释着 —— 需要 Docker 就先按官方文档加好 apt 源
# ============================================================
set -u

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LIST="$REPO_ROOT/scripts/packages/apt-packages.txt"
[ -f "$LIST" ] || { echo "找不到 $LIST" >&2; exit 2; }

dry=0
case "${1:-}" in
    --dry-run) dry=1 ;;
    "" ) ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
esac

# 发行版软检查（Debian 系之外只是提醒，不硬拦）
. /etc/os-release 2>/dev/null || true
case "${ID:-}" in
    ubuntu|debian|linuxmint|pop|zorin) ;;
    *) echo "⚠ 当前发行版是 '${ID:-未知}'，本清单按 Ubuntu/Debian 系写 —— 包名可能有出入。" ;;
esac

# 取包名：去行内注释 → 去空白 → 去空行
mapfile -t pkgs < <(sed -E 's/[[:space:]]*#.*$//' "$LIST" | tr -d ' \t' | grep -v '^$')
echo "共 ${#pkgs[@]} 个包（Docker 部分默认未启用；如需要，见文件末尾注释）"

if [ "$dry" = 1 ]; then
    echo "---- dry-run：apt-get update（真实执行）+ install -s（模拟）----"
    sudo apt-get update
    sudo apt-get install -s "${pkgs[@]}" | tail -5
    echo "（dry-run 不做任何实际安装）"
    exit 0
fi

sudo apt-get update || { echo "apt-get update 失败 —— 先确认网络/镜像源" >&2; exit 1; }
sudo apt-get install -y "${pkgs[@]}"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "安装过程有失败项（退出码 $rc）。重跑一次通常能补齐（幂等）。" >&2
    exit 1
fi
echo "完成。个别包若来自 universe 仓库未启用而失败，装 universe 后重跑即可。"
