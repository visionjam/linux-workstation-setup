#!/usr/bin/env bash
# ============================================================
# check-secrets.sh —— 提交前/推送前的密钥与隐私扫描
#
# 用法：scripts/check-secrets.sh [选项]
#   --staged    只扫暂存区（pre-commit 钩子用）
#   --all       扫「已跟踪 + 未跟踪但未被 ignore」的全部文件（默认）
#   --history   扫全部 git 历史（推送前必跑）
#   路径...     只扫指定文件
#   --strict    WARN 也算失败（发布前的最终检查用）
#   --quiet     只报汇总
#
# 退出码：0 干净 ｜ 1 有 BLOCK（--strict 下 WARN 也算）｜ 2 用法错
#
# 规则数据在 check-secrets.patterns（BLOCK/WARN 两级，制表符分隔，
# 可选第 4 列是传给 grep 的 flags 如 i），
# 文本级白名单在 check-secrets.allow（对「命中的那段文本」做 ERE 匹配）。
# 命中输出默认打码（前 4 后 4），不会把密钥完整打进终端。
# ============================================================
set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PATTERNS="$REPO_ROOT/scripts/check-secrets.patterns"
ALLOW="$REPO_ROOT/scripts/check-secrets.allow"
SELF_REL="scripts/check-secrets.sh"

mode=""; strict=0; quiet=0; targets=()
while [ $# -gt 0 ]; do
    case "$1" in
        --staged)  mode=staged ;;
        --all)     mode=all ;;
        --history) mode=history ;;
        --strict)  strict=1 ;;
        --quiet)   quiet=1 ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        echo "未知参数：$1" >&2; exit 2 ;;
        *)         targets+=("$1") ;;
    esac
    shift
done
[ -n "$mode" ] || mode=all
[ -f "$PATTERNS" ] || { echo "找不到 $PATTERNS" >&2; exit 2; }
[ -f "$ALLOW" ]    || { echo "找不到 $ALLOW" >&2; exit 2; }

cd "$REPO_ROOT" || exit 2

block=0; warn=0

mask() {  # 命中片段打码：短的一律星号，长的留前4后4
    local s="$1"
    if [ "${#s}" -le 8 ]; then printf '********'
    else printf '%s...%s' "${s:0:4}" "${s: -4}"; fi
}

is_allowed() {  # $1=命中文本；命中白名单返回 0
    local t="$1" re
    while IFS= read -r re; do
        case "$re" in ''|\#*) continue ;; esac
        printf '%s' "$t" | grep -qE -e "$re" && return 0
    done < "$ALLOW"
    return 1
}

report_hit() {  # $1=level $2=file $3=行号 $4=说明 $5=命中片段 $6=整行
    local level="$1" file="$2" ln="$3" desc="$4" hit="$5" line="$6"
    if [ "$level" = BLOCK ]; then block=$((block+1)); else warn=$((warn+1)); fi
    [ "$quiet" = 1 ] && return 0
    printf '[%s] %s:%s  (%s)\n' "$level" "$file" "$ln" "$desc"
    printf '        命中：%s\n' "$(mask "$hit")"
    printf '        行内容（已截断）：%s\n' "$(printf '%s' "$line" | cut -c1-120)"
}

scan_file() {  # 逐规则扫一个文件；命中片段先过白名单
    local file="$1" level pat desc flags ln line hit bad
    while IFS=$'\t' read -r level pat desc flags; do
        case "$level" in ''|\#*) continue ;; esac
        while IFS=: read -r ln line; do
            bad=""
            while IFS= read -r hit; do
                is_allowed "$hit" && continue
                bad="$hit"; break
            done < <(printf '%s\n' "$line" | grep -o${flags:-}E -e "$pat" 2>/dev/null || true)
            [ -n "$bad" ] || continue
            report_hit "$level" "$file" "$ln" "$desc" "$bad" "$line"
        done < <(grep -nI${flags:-}E --binary-files=without-match -e "$pat" "$file" 2>/dev/null || true)
    done < "$PATTERNS"
}

if [ "$mode" = history ]; then
    # 历史模式：对每个提交里的每个规则做 git grep（发布前跑一次，慢没关系）
    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
        echo "还没有任何提交，--history 无事可做。"
        exit 0
    fi
    while IFS=$'\t' read -r level pat desc flags; do
        case "$level" in ''|\#*) continue ;; esac
        while IFS= read -r out; do
            [ -n "$out" ] || continue
            hit=$(printf '%s' "$out" | grep -o${flags:-}E -e "$pat" | head -1 || true)
            if [ -n "$hit" ] && ! is_allowed "$hit"; then
                if [ "$level" = BLOCK ]; then block=$((block+1)); else warn=$((warn+1)); fi
                [ "$quiet" = 1 ] || printf '[%s·history] %s\n        命中：%s\n' \
                    "$level" "$(printf '%s' "$out" | cut -c1-160)" "$(mask "$hit")"
            fi
        done < <(git grep -In${flags:-}E -e "$pat" $(git rev-list --all) -- . \
                    ":(exclude)scripts/check-secrets.patterns" \
                    ":(exclude)scripts/check-secrets.allow" 2>/dev/null || true)
    done < "$PATTERNS"
else
    if [ "${#targets[@]}" -gt 0 ]; then
        files=("${targets[@]}")
    elif [ "$mode" = staged ]; then
        mapfile -t files < <(git diff --cached --name-only --diff-filter=ACM)
    else
        mapfile -t files < <(git ls-files --cached --others --exclude-standard)
    fi

    scanned=0
    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        case "$f" in
            scripts/check-secrets.patterns|scripts/check-secrets.allow|"$SELF_REL") continue ;;
            .git/*) continue ;;
        esac
        scan_file "$f"
        scanned=$((scanned+1))
    done
    echo "----"
    echo "扫描 $scanned 个文件：BLOCK $block ｜ WARN $warn"
fi

if [ "$block" -gt 0 ] || { [ "$strict" = 1 ] && [ "$warn" -gt 0 ]; }; then
    echo "结果：不通过（BLOCK $block / WARN $warn）"
    exit 1
fi
echo "结果：通过"
exit 0
