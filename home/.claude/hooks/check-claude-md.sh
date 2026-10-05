#!/usr/bin/env bash
# Hook: 检查 CLAUDE.md 是否存在并提示「已加载」
# 三个设计点：
#   ① python3 而不是 python —— Ubuntu 发行版没有 python 命令，照搬会直接报错
#   ② 依次检查两个位置 —— 先「项目根/CLAUDE.md」（更具体，优先），
#      再回退到「用户级 ~/.claude/CLAUDE.md」；只找项目根会在家目录误报「未找到」
#   ③ 标题改用命令行参数传入 —— 原版把标题直接拼进 Python 字符串，
#      标题里若有引号会让脚本崩掉；参数传入不会
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${CLAUDE_CWD:-$PWD}")

for MD in "$ROOT/CLAUDE.md" "$HOME/.claude/CLAUDE.md"; do
  [ -f "$MD" ] || continue
  HEADER=$(head -1 "$MD")
  python3 -c "import json,sys; print(json.dumps({'systemMessage':'✓ CLAUDE.md 已加载 — '+sys.argv[1]}))" "$HEADER"
  exit 0
done

echo '{"systemMessage":"⚠ CLAUDE.md 未找到"}'
