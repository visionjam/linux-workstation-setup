#!/usr/bin/env bash
# ============================================================
# export.sh —— 反向导出：把本机（$HOME）的当前配置同步回仓库
#
# 用法：scripts/export.sh [选项]
#   （无参数）   按 export-manifest.tsv 把 raw 模式的文件从 $HOME 覆盖到仓库工作树，
#                结束后提示人工复核（本脚本**不会**提交）
#   --check      不写任何文件：逐文件比对，有漂移则报告并以 1 退出
#                （用于发现「本机改了配置但没同步回仓库」）
#   --dry-run    只打印将要写的文件，零写入
#   --only <前缀> 只处理仓库相对路径以此开头的条目
#
# 设计约定（和 install.sh 的「禁自动猜」原则一致）：
#   · 清单是唯一事实来源 —— 本机新增了文件不会被自动收编，要人工加一行
#   · manual 模式的文件脚本绝不碰（仓库版是人工脱敏的移植版）
#   · 导出后必须人工 git diff + 跑 check-secrets.sh，再决定是否提交
#
# 退出码：0 成功/无漂移 ｜ 1 有失败/有漂移 ｜ 2 环境或用法错
# ============================================================
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
MANIFEST="$REPO_ROOT/scripts/export-manifest.tsv"

check=0; dry=0; only=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   check=1 ;;
        --dry-run) dry=1 ;;
        --only)    shift; only="${1:-}"; [ -n "$only" ] || { echo "--only 需要参数" >&2; exit 2; } ;;
        --only=*)  only="${1#--only=}" ;;
        -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)         echo "未知参数：$1" >&2; exit 2 ;;
    esac
    shift
done

[ -f "$MANIFEST" ] || { echo "找不到 $MANIFEST" >&2; exit 2; }

changed=0; unchanged=0; drift=0; failed=0; missing=0
exported=(); manual_list=(); missing_list=()

while IFS=$'\t' read -r src dst mode note; do
    case "${src:-}" in ''|\#*) continue ;; esac
    if [ -n "$only" ]; then
        case "$dst" in "$only"*) ;; *) continue ;; esac
    fi
    if [ "$mode" = manual ]; then
        manual_list+=("$dst${note:+ （$note）}")
        continue
    fi

    s="$HOME/$src"; d="$REPO_ROOT/$dst"
    if [ ! -e "$s" ]; then
        missing=$((missing+1)); missing_list+=("$src")
        continue
    fi

    if cmp -s "$s" "$d" 2>/dev/null; then
        unchanged=$((unchanged+1)); continue
    fi

    if [ "$check" = 1 ]; then
        drift=$((drift+1))
        echo "  [漂移] $src ≠ $dst"
        diff -u "$d" "$s" 2>/dev/null | head -20
    elif [ "$dry" = 1 ]; then
        echo "  [dry-run] 将导出 $src → $dst"
        changed=$((changed+1))
    else
        mkdir -p "$(dirname "$d")"
        if cp -p "$s" "$d"; then
            echo "  导出 $src → $dst"
            exported+=("$dst"); changed=$((changed+1))
        else
            echo "  [失败] 写入 $dst" >&2; failed=$((failed+1))
        fi
    fi
done < "$MANIFEST"

echo "----"
echo "同步 $changed ｜ 未变 $unchanged ｜ 漂移 $drift ｜ 本机缺失 $missing ｜ 失败 $failed"

if [ "${#missing_list[@]}" -gt 0 ]; then
    echo "本机没有这些文件（清单里有、$HOME 下不存在）："
    for m in "${missing_list[@]}"; do echo "  $m"; done
fi
if [ "${#manual_list[@]}" -gt 0 ]; then
    echo "以下文件是 manual 模式（脚本不碰，需人工维护）："
    for m in "${manual_list[@]}"; do echo "  $m"; done
fi

if [ "$check" = 1 ]; then
    [ "$drift" -gt 0 ] && { echo "结果：有漂移（本机改了但没导出）"; exit 1; }
    echo "结果：无漂移"
    exit 0
fi

if [ "${#exported[@]}" -gt 0 ]; then
    echo
    echo "已写回仓库工作树，但**没有提交**。请人工复核："
    echo "  cd $REPO_ROOT && git diff          # 逐文件看"
    echo "  scripts/check-secrets.sh           # 扫描后才可提交"
fi
[ "$failed" -gt 0 ] && exit 1
exit 0
