#!/usr/bin/env bash
# ============================================================
# install.sh —— 把仓库 home/ 树部署到 $HOME
#
# 用法：scripts/install.sh [选项]
#   --dry-run        只打印将要发生的动作，零写入
#   --yes, -y        跳过确认（默认交互确认，输入 yes）
#   --only <前缀>    只处理仓库相对路径以此开头的文件（如 --only .bashrc）
#   --no-fixups      跳过收尾动作（fd/bat 软链、执行位、~/.ssh 权限）
#   --fail-fast      遇错立即中止（默认：继续，最后汇总）
#   -h, --help       显示本帮助
#
# 退出码：0 成功（含全部跳过）｜1 有文件失败｜2 前置条件不满足｜3 参数错误
#
# 设计要点：
#   · 每个文件三态：新装 / 跳过（字节相同则完全不碰，幂等）/ 覆盖（先备份）
#   · 备份规则：<目标>.before-install 永久保留「第一次安装前」的原状；
#     之后内容再漂移则另存带时间戳副本；已有备份绝不静默覆盖。
#   · 不含密钥的文件照常部署；~/.claude/settings.json 永不被本脚本创建/覆盖
#     （仓库里只有 settings.json.example，装成 .example 供参考）。
# ============================================================
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$REPO_ROOT/home"

dry=0; yes_flag=0; only=""; fail_fast=0; fixups=1

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)    dry=1 ;;
        --yes|-y)     yes_flag=1 ;;
        --no-fixups)  fixups=0 ;;
        --fail-fast)  fail_fast=1 ;;
        --only)       shift; only="${1:-}"; [ -n "$only" ] || { echo "--only 需要参数" >&2; exit 3; } ;;
        --only=*)     only="${1#--only=}" ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "未知参数：$1（-h 看帮助）" >&2; exit 3 ;;
    esac
    shift
done

# ---------- 前置检查 ----------
[ -d "$SRC" ] || { echo "找不到 $SRC —— 请从仓库根运行 scripts/install.sh" >&2; exit 2; }
: "${HOME:?HOME 环境变量未设置}"
[ -d "$HOME" ] || { echo "HOME 不存在：$HOME" >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo "不要用 root/sudo 运行：会把配置装进 /root。请用你的普通账号。" >&2; exit 2; }

# ---------- 枚举待部署文件 ----------
mapfile -t FILES < <(cd "$SRC" && find . -type f | sed 's|^\./||' | sort)
[ "${#FILES[@]}" -gt 0 ] || { echo "home/ 是空的？" >&2; exit 2; }

# ---------- 第一遍：分类（不写任何东西）----------
declare -A CLASS=()       # SKIP / OVERWRITE / NEW / FAIL
declare -a ORDER=() FAILS=()
n_new=0; n_over=0; n_skip=0; n_fail=0

for rel in "${FILES[@]}"; do
    if [ -n "$only" ]; then
        case "$rel" in "$only"*) ;; *) continue ;; esac
    fi
    ORDER+=("$rel")
    src="$SRC/$rel"; dst="$HOME/$rel"
    if [ -L "$dst" ] && [ -d "$dst" ]; then
        CLASS[$rel]=FAIL; FAILS+=("$rel（目标是目录链接，人工处理）"); n_fail=$((n_fail+1)); continue
    fi
    if [ -d "$dst" ] && [ ! -L "$dst" ]; then
        CLASS[$rel]=FAIL; FAILS+=("$rel（目标是目录，人工处理）"); n_fail=$((n_fail+1)); continue
    fi
    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
        CLASS[$rel]=NEW; n_new=$((n_new+1))
    elif cmp -s "$src" "$dst" 2>/dev/null; then
        CLASS[$rel]=SKIP; n_skip=$((n_skip+1))
    else
        CLASS[$rel]=OVERWRITE; n_over=$((n_over+1))
    fi
done

echo "============================================"
echo "部署源： $SRC"
echo "目标：   $HOME"
echo "分类：   新装 $n_new ｜ 覆盖 $n_over ｜ 跳过 $n_skip ｜ 无法处理 $n_fail"
echo "============================================"

if [ "$n_fail" -gt 0 ]; then
    for f in "${FAILS[@]}"; do echo "  [无法处理] $f"; done
fi

if [ "$dry" = 1 ]; then
    for rel in "${ORDER[@]}"; do
        case "${CLASS[$rel]}" in
            NEW)       echo "  [dry-run] 新装：$rel" ;;
            OVERWRITE) echo "  [dry-run] 覆盖：$rel（将备份为 $rel.before-install）" ;;
            SKIP)      echo "  [dry-run] 跳过：$rel（内容相同）" ;;
        esac
    done
    [ "$fixups" = 1 ] && echo "  [dry-run] 收尾：fd/bat 软链检查、执行位、~/.ssh 权限"
    echo "（dry-run：未写入任何文件）"
    exit 0
fi

if [ "$yes_flag" != 1 ] && { [ "$n_new" -gt 0 ] || [ "$n_over" -gt 0 ]; }; then
    read -r -p "继续部署？输入 yes 回车： " ans
    [ "$ans" = "yes" ] || { echo "已取消。"; exit 0; }
fi

# ---------- 第二遍：执行 ----------
INSTALLED=(); BACKUPS=(); WRITE_FAILS=()

backup_existing() {  # $1=dst $2=rel
    local dst="$1" rel="$2" bak="$dst.before-install" tb
    { [ -e "$dst" ] || [ -L "$dst" ]; } || return 0
    if [ ! -e "$bak" ] && [ ! -L "$bak" ]; then
        cp -pP "$dst" "$bak" && BACKUPS+=("$rel → ${bak/#$HOME/~}")    # 首次：保留原状
    elif cmp -s "$bak" "$dst" 2>/dev/null; then
        :                                                              # 内容相同：不重复备份
    else
        tb="$bak.$(date +%Y%m%d-%H%M%S)"                                # 内容漂移：时间戳副本
        cp -pP "$dst" "$tb" && BACKUPS+=("$rel → ${tb/#$HOME/~}")
    fi
}

for rel in "${ORDER[@]}"; do
    case "${CLASS[$rel]}" in SKIP|FAIL) continue ;; esac
    src="$SRC/$rel"; dst="$HOME/$rel"
    backup_existing "$dst" "$rel"
    if ! mkdir -p "$(dirname "$dst")"; then
        echo "  [失败] 建目录失败：$(dirname "$dst")" >&2; WRITE_FAILS+=("$rel"); continue
    fi
    [ -L "$dst" ] && rm -f "$dst"        # 原目标是符号链接 → 换成真实文件（备份里保存了链接）
    if cp -p "$src" "$dst"; then
        INSTALLED+=("$rel")
    else
        echo "  [失败] 复制失败：$rel" >&2
        WRITE_FAILS+=("$rel")
        [ "$fail_fast" = 1 ] && break
    fi
done

# ---------- 收尾 ----------
create_compat_link() {  # $1=链接名 $2=/usr/bin 下的真实命令
    local name="$1" target="$2"
    local p="$HOME/.local/bin/$name"
    if [ ! -x "$target" ]; then
        echo "  [跳过] $target 不存在（apt install fd-find bat 之后重跑）"
        return 0
    fi
    if [ -L "$p" ] && [ "$(readlink "$p")" = "$target" ]; then
        return 0
    fi
    if [ -e "$p" ] && [ ! -L "$p" ]; then
        cp -p "$p" "$p.before-install"      # 顶掉的真实文件先备份
    fi
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$target" "$p"                   # -n：目标是软链时不跟进去
    echo "  [软链] ~/.local/bin/$name → $target"
}

if [ "$fixups" = 1 ]; then
    echo "---- 收尾 ----"
    create_compat_link fd  /usr/bin/fdfind   # Ubuntu 包改了命令名
    create_compat_link bat /usr/bin/batcat
    chmod +x "$HOME/.claude/hooks/"*.sh           2>/dev/null || true
    chmod +x "$HOME/.config/herdr/status.d/"*.sh  2>/dev/null || true
    chmod +x "$HOME/.local/bin/nvm-link"          2>/dev/null || true
    [ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh"
fi

# ---------- 摘要 ----------
echo
echo "============================================"
echo "完成：新装 $n_new ｜ 覆盖 $n_over ｜ 跳过 $n_skip ｜ 失败 $((n_fail + ${#WRITE_FAILS[@]}))"
if [ "${#BACKUPS[@]}" -gt 0 ]; then
    echo "备份（原文件已保留）："
    for b in "${BACKUPS[@]}"; do echo "  $b"; done
fi
echo "--------------------------------------------"
echo "还需手动做的事："
echo "  1. 填 ~/.claude/settings.json —— 以 ~/.claude/settings.json.example 为模板，"
echo "     填入你的 API token / 供应商地址后另存为 settings.json（含密钥，仓库不含）。"
echo "  2. 配 git 提交身份（~/.gitconfig 里是占位符）："
echo "     git config --global user.name  '你的名字'"
echo "     git config --global user.email '你的邮箱'"
echo "  3. 装软件：scripts/packages/install-apt.sh && scripts/packages/install-binaries.sh"
echo "  4. 重开终端（或 source ~/.bashrc）让 PATH 与提示符生效。"
echo "============================================"

if [ "$((n_fail + ${#WRITE_FAILS[@]}))" -gt 0 ]; then
    exit 1
fi
exit 0
