#!/bin/sh
# herdr 顶栏「代理状态」探针 —— 三级判断：
#   🛑 端口连不上     → 代理进程没跑
#   ⚠  端口通但出不去 → 隧道建了、代理自己出不去（上游/订阅问题）
#   🌐 正常           → 隧道 + 真实出网都通
# 出网探针选 gstatic 的 generate_204：纯 204 无正文，是标准连通性端点。
# ⚠️ 端口探活用 bash 的 /dev/tcp —— /bin/sh 是 dash，没这个特性，必须显式起 bash。
# 代理地址按需改（默认按本机 7890 端口写）。
if ! timeout 1 bash -c '</dev/tcp/127.0.0.1/7890' 2>/dev/null; then
    printf '🛑'
elif curl -m 2 -fs -o /dev/null -x http://127.0.0.1:7890 https://www.gstatic.com/generate_204 2>/dev/null; then
    printf '🌐'
else
    printf '⚠'
fi
