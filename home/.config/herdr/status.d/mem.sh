#!/bin/sh
# herdr 顶栏「内存」探针：已用/总量。
# 已用 = MemTotal - MemAvailable（与 free 的 used 口径一致）；
# 读 /proc/meminfo 比 fork 一个 free 更省。
awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "🧠%.1f/%.0fG", (t-a)/1048576, t/1048576}' /proc/meminfo
