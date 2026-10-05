#!/usr/bin/env bash
# SessionStart hook: 自动打环境快照（可选功能）
#
# 依赖你自己的快照脚本 ~/env-backup/snapshot.sh（本仓库不含该脚本 —— 它是
# 另一个「本机备份系统」的组件，见 docs/environment.md 的备份体系一节）。
# 脚本不存在时**静默跳过**，不会打扰你。
#
# 只在「距上次快照超过 MAX_AGE_HOURS 小时」时才打，避免每次开会话都写盘。
# 目的：给每次「开工前」留一个可回退的状态。手动快照的窗口期会错过某些
#       工具对配置的瞬时且静默的改动 —— 自动快照把那个窗口补上。
#
# ⚠️ 判定成败看产物文件，不看退出码：
#    快照脚本可能「有 set -u 但没有 set -e」，tar 失败时退出码仍是 0。
#
# 阈值可用环境变量临时覆盖（方便测试）：
#    SNAPSHOT_MAX_AGE_HOURS=0 bash ~/.claude/hooks/auto-snapshot.sh

SNAP_DIR="$HOME/env-backup/snapshots"
SNAP_SH="$HOME/env-backup/snapshot.sh"
MAX_AGE_HOURS="${SNAPSHOT_MAX_AGE_HOURS:-24}"

# 没有快照系统 → 静默退出（不发 systemMessage，免得每次开会话都刷提示）
if [ ! -x "$SNAP_SH" ]; then
  exit 0
fi

# 最近一份快照的时间
LATEST=$(ls -1t "$SNAP_DIR"/env-*.tar.gz 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
  AGE_H=$(( ( $(date +%s) - $(stat -c %Y "$LATEST") ) / 3600 ))
  # 还新鲜 → 静默跳过（不输出任何东西，避免每次开会话都刷一行）
  [ "$AGE_H" -lt "$MAX_AGE_HOURS" ] && exit 0
  WHEN="距上次 ${AGE_H}h"
else
  WHEN="首次"
fi

# 打快照。快照脚本输出很啰嗦，stdout 直接丢弃
bash "$SNAP_SH" >/dev/null 2>&1
AFTER=$(ls -1t "$SNAP_DIR"/env-*.tar.gz 2>/dev/null | head -1)

# 成功判据：出现了新文件，且非空
if [ -n "$AFTER" ] && [ "$AFTER" != "$LATEST" ] && [ -s "$AFTER" ]; then
  echo "{\"systemMessage\":\"✓ 已自动打快照（${WHEN}）: $(basename "$AFTER")\"}"
else
  echo '{"systemMessage":"⚠ 自动快照未生成新文件，请手动跑 ~/env-backup/snapshot.sh 检查"}'
fi

exit 0
