# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
# ============================================================
#  以下是自己加的配置
#  约定：每一节都写成「重复 source 也不会重复生效」的幂等形式
# ============================================================

# ---- 1. 用户私有命令目录 ------------------------------------
# 手工安装的单文件二进制（starship/atuin/…）都放在这里。
# 加 case 判断而不是简单 `[ -d ] &&`：嵌套开 shell 时会重复追加 PATH。
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# ---- 2. 默认编辑器 ------------------------------------------
# 需要手写内容时（git commit、crontab -e 等）自动打开 VS Code。
# --wait 是关键：不加的话 VS Code 一启动命令就返回了，文件还是空的。
# 用 command -v 判断，万一 code 不可用就不设置，免得 git 之类的卡住。
if command -v code >/dev/null 2>&1; then
    export EDITOR="code --wait"
    export VISUAL="code --wait"
fi

# ---- 3. nvm（Node 版本管理器）-------------------------------
# 装 Linux 原生 Node（不要用任何往 Linux 目录塞 Windows 二进制的方案，
# 会 Exec format error）。nvm 只在交互式 shell 里加载 —— 登录非交互
# 场景（IDE 任务运行器、ssh 命令）拿不到 node，用 ~/.local/bin/nvm-link
# 把 default 版本的 node/npm/npx 软链过去补这个缺口。
# ⚠️ nvm install / nvm alias default 换版本后必须重跑 nvm-link。
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                    # 加载 nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # 加载补全
# 国内下载 node 速度慢的话，取消下面这行的注释用镜像：
# export NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node

# ---- 4. 代理白名单补齐 --------------------------------------
# 场景：环境的注入方（虚拟网络/容器宿主等）会塞一套代理变量进来，其
# no_proxy 不含「想让其直连」的域名，于是流量白白绕行本地代理。
#
# ⚠️ 关键坑：环境变量名区分大小写，no_proxy 和 NO_PROXY 是**两个独立
# 变量**，不是同一个的两种写法。而 curl / python-requests / undici 查
# 这两个时**小写优先** —— 只改大写等于没改，而且不报任何错。
# 所以两份都要补，且要做成幂等（重复 source 不越加越多）。
#
# 下面示例补了两个域名，按需替换成你自己的：
#   api.deepseek.com            模型 API 直连（不绕代理）
#   pypi.tuna.tsinghua.edu.cn   国内 PyPI 镜像直连（实测大文件差 5 倍）
case ",${no_proxy-}," in
    *",api.deepseek.com,"*) ;;                              # 已含 → 不动
    ",,")  export no_proxy="api.deepseek.com" ;;            # 原本没设
    *)     export no_proxy="$no_proxy,api.deepseek.com" ;;  # 追加
esac
case ",${NO_PROXY-}," in
    *",api.deepseek.com,"*) ;;
    ",,")  export NO_PROXY="api.deepseek.com" ;;
    *)     export NO_PROXY="$NO_PROXY,api.deepseek.com" ;;
esac

case ",${no_proxy-}," in
    *",pypi.tuna.tsinghua.edu.cn,"*) ;;
    ",,")  export no_proxy="pypi.tuna.tsinghua.edu.cn" ;;
    *)     export no_proxy="$no_proxy,pypi.tuna.tsinghua.edu.cn" ;;
esac
case ",${NO_PROXY-}," in
    *",pypi.tuna.tsinghua.edu.cn,"*) ;;
    ",,")  export NO_PROXY="pypi.tuna.tsinghua.edu.cn" ;;
    *)     export NO_PROXY="$NO_PROXY,pypi.tuna.tsinghua.edu.cn" ;;
esac

# ---- 5. 开机欢迎图（fastfetch）—— 每次开机只刷一次 ------------
# 目标：新开终端的第一层 shell 里显示一次系统信息图，之后开的 pane/窗口
# 不再重复刷。放 .bashrc 而不是 .profile：很多复用器直接 execve("/bin/bash")
# 拉起非登录 shell，bash 只在登录 shell 读 .profile，写那儿不会触发。
#
# 两道闸：
#   ① 看父进程是不是 shell —— 嵌套 shell 直接跳过。
#      读 /proc/<pid>/comm 用 bash 内建 read，不 fork，开销可忽略。
#      终端模拟器拉起的首层 shell、复用器 pane、ssh 登录都会通过这关。
#   ② 本 boot 是否已刷过 —— 内核每次启动生成随机 boot_id
#      （/proc/sys/kernel/random/boot_id），与标记文件比对**内容**。
#      放 ~/.cache，靠内容对不上触发，不依赖目录可写或系统清过。
#   竞态：同一瞬间开两个 shell 可能都过闸刷两次 —— 开机场景撞不上，不治。
#
# ⚠️ 别改回 SHLVL 守卫：/proc/<pid>/environ 里的 SHLVL 只反映 exec 时刻的
#    值，bash 启动后自增 1 —— 实测中间 shell 的真实值和你读到的对不上。
#
# 为什么用 fastfetch 不用 neofetch：实测 23ms/次 vs 几百毫秒，差一个数量级。
if command -v fastfetch >/dev/null 2>&1; then
    read -r _parent_proc _ < "/proc/$PPID/comm" 2>/dev/null || _parent_proc=unknown
    case "${_parent_proc##*/}" in
        bash|sh|dash|zsh|ksh|fish) ;;  # 父进程是 shell → 嵌套，不刷
        login) ;;                      # TTY 引导会话（无窗口）→ 不刷
        *)                             # 第一层 shell → 过「本 boot 是否已刷」闸
            _boot_id=$(< /proc/sys/kernel/random/boot_id)
            _boot_marker="$HOME/.cache/fastfetch-boot-id"
            # 标记写成功才刷（写失败宁可静默，也不退化成「每个 shell 都刷」）
            if [ ! -f "$_boot_marker" ] ||
               [ "$(< "$_boot_marker")" != "$_boot_id" ]; then
                printf '%s\n' "$_boot_id" > "$_boot_marker" && fastfetch
            fi
            unset _boot_id _boot_marker
            ;;
    esac
    unset _parent_proc
fi

# ---- 6. 现代 CLI 接线：fzf / starship / atuin / zoxide / direnv ----
# 都带守卫：命令不在就整行跳过，不报错。
#
#   fzf      —— 补 key-bindings：Ctrl-T 选路径、Alt-C 跳目录
#   starship —— 提示符（个性化在 ~/.config/starship.toml）
#   atuin    —— 历史进 SQLite，Ctrl-R = 全量历史模糊搜索
#   zoxide   —— z <关键词> 按 frecency 跳目录；zi 交互版（借 fzf）
#   direnv   —— 进入带 .envrc 的目录自动 source、离开自动卸载
#
# ⚠️ 顺序有讲究，别重排：fzf 的 key-bindings 也想占 Ctrl-R，atuin 必须放
#    最后才能把它收回来（atuin 的 bind 逻辑是先 unbind 再覆盖）。
#    最终：Ctrl-R 归 atuin，Ctrl-T / Alt-C 归 fzf。
#
# 两个 disable 的取舍（atuin 18.23 实测支持）：
#   --disable-up-arrow  保住「↑ = 上一条命令」的原生习惯
#   --disable-ai        别让「?」键弹 atuin 的 AI 搜索（没配 key 只会报错）
#
# ⚠️ direnv 有安全门槛：.envrc 首次出现必须 `direnv allow` 才生效 ——
#    这是防「clone 个仓库就被执行任意代码」的设计，不是坏了。
#
# 这些工具用 apt 或 scripts/packages/install-binaries.sh 安装。

[ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && \
    . /usr/share/doc/fzf/examples/key-bindings.bash

command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"
command -v atuin    >/dev/null 2>&1 && eval "$(atuin init bash --disable-up-arrow --disable-ai)"
command -v zoxide   >/dev/null 2>&1 && eval "$(zoxide init bash)"
command -v direnv   >/dev/null 2>&1 && eval "$(direnv hook bash)"
