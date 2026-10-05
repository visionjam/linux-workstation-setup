#!/bin/sh
# herdr 顶栏「GPU」探针：利用率 + 已用显存（需要 NVIDIA 驱动，nvidia-smi 在 PATH 里）。
# ⚠️ 若 server 派生进程的 PATH 不全会找不到 nvidia-smi —— 此时改成绝对路径即可
#    （server 环境是它启动时刻的快照，未必继承你交互式 shell 的 PATH）。
nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>/dev/null \
    | awk -F', ' '{printf "🎮%s%% %.1fG", $1, $2/1024}'
