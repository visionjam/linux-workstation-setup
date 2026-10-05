#!/usr/bin/env bash
# ============================================================
# install-binaries.sh —— 安装「不走 apt」的单文件二进制
#
# 覆盖：starship / atuin / lazygit / yq / duckdb / glow / yazi(+ya+补全)
#       / herdr → ~/.local/bin
#       neovim → ~/.local/opt（+ ~/.local/bin/nvim 相对软链）
#       fastfetch → /usr/bin（.deb，经 sudo apt 安装以自动解析依赖）
#
# 用法：scripts/packages/install-binaries.sh [选项]
#   （无参数）        安装缺失项、升级版本不符项；版本相同则跳过
#   --dry-run         只打印计划，零下载零写盘
#   --only 名[,名]    只处理指定条目（名字见 --list）
#   --force           版本相同也重装
#   --list            列出清单表后退出
#
# 退出码：0 全部安装或跳过 ｜ 1 有失败 ｜ 2 缺依赖或用法错
#
# 下载策略（重要）：curl -fSL --retry 3 --retry-all-errors -C - + SHA256 校验，
# 校验失败就续传重试（最多 3 轮，最后一轮放弃续传全新下载）。
# —— 实测 GitHub 大文件传输会中途静默截断（curl: (18)），SHA256 是唯一能
#    发现它的手段；缓存里校验通过的文件重跑时不重复下载。
# ============================================================
set -u

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TSV="$REPO_ROOT/scripts/packages/binaries.tsv"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/linux-workstation-setup/downloads"

dry=0; force=0; list=0; only=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) dry=1 ;;
        --force)   force=1 ;;
        --list)    list=1 ;;
        --only)    shift; only="${1:-}"; [ -n "$only" ] || { echo "--only 需要参数" >&2; exit 2; } ;;
        --only=*)  only="${1#--only=}" ;;
        -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)         echo "未知参数：$1" >&2; exit 2 ;;
    esac
    shift
done

[ -f "$TSV" ] || { echo "找不到 $TSV" >&2; exit 2; }

if [ "$list" = 1 ]; then
    printf '%-10s %-8s %-8s %s\n' NAME VERSION METHOD DEST
    while IFS=$'\t' read -r name version url sha method dest; do
        case "${name:-}" in ''|\#*) continue ;; esac
        printf '%-10s %-8s %-8s %s\n' "$name" "$version" "$method" "${dest/#\~/\$HOME}"
    done < "$TSV"
    exit 0
fi

# ---------- 依赖检查 ----------
missing_deps=()
for c in curl tar sha256sum gzip; do
    command -v "$c" >/dev/null 2>&1 || missing_deps+=("$c")
done
if ! command -v unzip >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    missing_deps+=("unzip 或 python3")
fi
if [ "${#missing_deps[@]}" -gt 0 ]; then
    echo "缺少依赖：${missing_deps[*]}" >&2
    echo "先装：sudo apt-get install -y curl tar coreutils unzip" >&2
    exit 2
fi

# ---------- 工具函数 ----------

# 取目标二进制的已装版本（对已存在的 dest 用绝对路径调用，不依赖 PATH）。
# 实测本清单 10 个二进制的 --version 输出，首个 x.y.z 数字都是版本号。
get_version() {
    local dest="$1"
    [ -x "$dest" ] || return 1
    "$dest" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# 下载 + 校验；成功后把文件路径写进全局 LAST_FILE
LAST_FILE=""
fetch_verified() {  # $1=url $2=sha256
    local url="$1" sha="$2" f try
    f="$CACHE/$(basename "${url%%\?*}")"
    mkdir -p "$CACHE"
    for try in 1 2 3; do
        # 缓存里已有且校验通过 → 直接复用（重跑/升级其它项时不重复下载）
        if [ -f "$f" ] && printf '%s  %s\n' "$sha" "$f" | sha256sum -c - >/dev/null 2>&1; then
            LAST_FILE="$f"; return 0
        fi
        [ "$try" = 3 ] && rm -f "$f"    # 最后一轮：放弃续传，全新下载（防 416/半截污染）
        if ! curl -fSL --retry 3 --retry-all-errors --retry-delay 2 \
                    --connect-timeout 15 -C - -o "$f" "$url" 2>&1; then
            echo "    [重试 $try/3] 传输中断，3 秒后续传…"
            sleep 3; continue
        fi
        if printf '%s  %s\n' "$sha" "$f" | sha256sum -c - >/dev/null 2>&1; then
            LAST_FILE="$f"; return 0
        fi
        echo "    [重试 $try/3] SHA256 不符（当前 $(stat -c%s "$f" 2>/dev/null || echo '?') 字节），可能被截断，续传中…"
        sleep 3
    done
    rm -f "$f"
    echo "    [失败] 三轮都未通过校验。若在国内直连 GitHub，可先 export HTTPS_PROXY=http://127.0.0.1:7890 再重跑。" >&2
    return 1
}

# 按 method 落盘
install_artifact() {  # $1=name $2=method $3=dest $4=file
    local name="$1" method="$2" dest="$3" file="$4" tmp f d
    case "$method" in
        raw)
            install -m755 "$file" "$dest" ;;
        gz)
            gzip -dc "$file" > "$dest" && chmod 755 "$dest" ;;
        tar.gz)
            tmp=$(mktemp -d)
            if ! tar xzf "$file" -C "$tmp"; then rm -rf "$tmp"; return 1; fi
            f=$(find "$tmp" -maxdepth 2 -type f -name "$name" | head -1)
            if [ -z "$f" ]; then echo "    [失败] tar 里找不到名为 $name 的文件" >&2; rm -rf "$tmp"; return 1; fi
            install -m755 "$f" "$dest"; rm -rf "$tmp" ;;
        tar-dir)
            # neovim 专用：整目录替换 + 相对软链（相对链接才能跟 $HOME 一起搬家）
            mkdir -p "$(dirname "$dest")"
            rm -rf "$dest"
            tar xzf "$file" -C "$(dirname "$dest")" || return 1
            ln -sfn "../opt/$(basename "$dest")/bin/nvim" "$HOME/.local/bin/nvim" ;;
        zip)
            # yazi 专用：包内布局 yazi-<triple>/{yazi,ya,completions/}
            tmp=$(mktemp -d)
            if command -v unzip >/dev/null 2>&1; then
                unzip -q -o "$file" -d "$tmp" || { rm -rf "$tmp"; return 1; }
            else
                python3 -m zipfile -e "$file" "$tmp" || { rm -rf "$tmp"; return 1; }
            fi
            d=$(find "$tmp" -maxdepth 1 -type d -name 'yazi-*' | head -1)
            if [ -z "$d" ]; then echo "    [失败] zip 里找不到 yazi-* 目录" >&2; rm -rf "$tmp"; return 1; fi
            install -m755 "$d/yazi" "$HOME/.local/bin/yazi"
            install -m755 "$d/ya"   "$HOME/.local/bin/ya"
            mkdir -p "$HOME/.local/share/bash-completion/completions"
            [ -f "$d/completions/yazi.bash" ] && \
                install -m644 "$d/completions/yazi.bash" "$HOME/.local/share/bash-completion/completions/yazi"
            [ -f "$d/completions/ya.bash" ] && \
                install -m644 "$d/completions/ya.bash" "$HOME/.local/share/bash-completion/completions/ya"
            rm -rf "$tmp" ;;
        deb)
            # fastfetch 专用：sudo apt 安装本地 deb（会解析依赖；比 dpkg -i 稳）
            # ⚠️ 别用 -polyfilled 变体（那是给 glibc 2.17 老发行版的）
            sudo apt-get install -y "$file" ;;
        *)
            echo "    [失败] 未知 method：$method" >&2; return 1 ;;
    esac
}

# ---------- 主循环 ----------
mkdir -p "$HOME/.local/bin"
n_ok=0; n_skip=0; n_fail=0; n_dry=0
herdr_updated=0

while IFS=$'\t' read -r name version url sha method dest; do
    case "${name:-}" in ''|\#*) continue ;; esac
    if [ -n "$only" ]; then
        case ",$only," in *",$name,"*) ;; *) continue ;; esac
    fi
    dest="${dest/#\~/$HOME}"

    # tar-dir 方法（neovim）：本体是目录，版本检测入口是 ~/.local/bin/nvim 软链
    checkp="$dest"
    [ "$method" = tar-dir ] && checkp="$HOME/.local/bin/nvim"
    cur=$(get_version "$checkp" 2>/dev/null) || cur=""
    # yazi 特例：必须 yazi + ya 双全才算已装
    if [ "$name" = yazi ] && [ "$cur" = "$version" ] && [ ! -x "$HOME/.local/bin/ya" ]; then
        cur=""
    fi

    if [ "$force" != 1 ] && [ "$cur" = "$version" ]; then
        echo "  [跳过] $name $version（已装）"
        n_skip=$((n_skip+1)); continue
    fi

    if [ -n "$cur" ]; then
        echo "  [升级] $name $cur → $version"
    else
        echo "  [安装] $name $version（$method → ${dest/#$HOME/~}）"
    fi

    if [ "$dry" = 1 ]; then
        n_dry=$((n_dry+1)); continue
    fi

    if ! fetch_verified "$url" "$sha"; then
        n_fail=$((n_fail+1)); continue
    fi
    if install_artifact "$name" "$method" "$dest" "$LAST_FILE"; then
        n_ok=$((n_ok+1))
        [ "$name" = herdr ] && herdr_updated=1
    else
        echo "    [失败] $name 落盘失败" >&2
        n_fail=$((n_fail+1))
    fi
done < "$TSV"

# ---------- 摘要 ----------
echo
if [ "$dry" = 1 ]; then
    echo "dry-run 完成：将安装/升级 $n_dry 项，跳过 $n_skip 项（未下载、未写盘）"
    exit 0
fi
echo "完成：新装/升级 $n_ok ｜ 跳过 $n_skip ｜ 失败 $n_fail"
if [ "$herdr_updated" = 1 ] && pgrep -f 'herdr server' >/dev/null 2>&1; then
    echo "提示：herdr server 正在运行，仍在用旧二进制的常驻进程；"
    echo "      `herdr server restart`（或 herdr update --handoff）后生效。"
fi
echo "重开终端（或 source ~/.bashrc）让 ~/.local/bin 的新命令生效。"
[ "$n_fail" -gt 0 ] && exit 1
exit 0
