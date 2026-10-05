#!/bin/sh
# herdr 顶栏「负载」探针：1 分钟 load average。全机最便宜的探针（一次 awk，零 fork）。
awk '{printf "⚡%.2f", $1}' /proc/loadavg
