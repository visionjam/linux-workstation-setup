-- ============================================================================
-- ~/.config/nvim/init.lua —— Neovim 配置（纯键盘路线）
--
-- 约定：
--   · 只写「有意选择」的项；Neovim 默认值够好的不重复写（默认值可查 :h nvim-defaults）
--   · 标准目录：配置 ~/.config/nvim/ ｜ 数据（插件）~/.local/share/nvim/ ｜ 状态 ~/.local/state/nvim/
--   · 改完本文件：在 nvim 里 :source % 重载，或重启
-- ============================================================================


-- ─────────────────────────────────────────────────────────────
-- 1. 基础显示
-- ─────────────────────────────────────────────────────────────
vim.g.mapleader = " "           -- 空格键当 leader（快捷键前缀，必须声明在任何 keymap 之前）
vim.g.maplocalleader = " "

vim.opt.number = true           -- 当前行显示绝对行号
vim.opt.relativenumber = true   -- 其他行显示与光标的距离：练 5j / d3k / y2w 计数的可视反馈
vim.opt.scrolloff = 8           -- 光标距上下边缘至少 8 行，浏览时上下文不贴边
vim.opt.signcolumn = "yes"      -- 常驻标记列（git 标记用它；不常驻的话这列时隐时现会让文字横跳）
vim.opt.termguicolors = true    -- 真彩色（现代终端均支持；不开配色主题会发灰）
vim.opt.list = true             -- 显示不可见字符
vim.opt.listchars = { tab = "▸ ", trail = "·", nbsp = "␣", extends = "›", precedes = "‹" }
-- ↑ tab 显示为 ▸、行尾空格为 ·；空格/tab 混用一眼现形。嫌花可 :set nolist 临时关

-- 注：swap / undo / backup 文件，Neovim 默认就集中在 ~/.local/state/nvim/ 下
--    （不像 vim 会散落在项目目录里），无需另外配置目录


-- ─────────────────────────────────────────────────────────────
-- 2. 搜索
-- ─────────────────────────────────────────────────────────────
vim.opt.ignorecase = true       -- 搜索忽略大小写……
vim.opt.smartcase = true        -- ……但输入里含大写字母时自动变敏感（黄金组合）
vim.opt.hlsearch = true         -- 高亮全部匹配（用 <Esc><Esc> 清掉，见第 5 节）
vim.opt.incsearch = true        -- 边输入边跳（默认已开，写明强调）
vim.opt.inccommand = "split"    -- :s 替换时开预览窗实时看结果（nvim 特有神器）
-- 命令行补全保持默认：nvim 自带模糊匹配浮窗（:h wildoptions），不用配


-- ─────────────────────────────────────────────────────────────
-- 3. 编辑行为
-- ─────────────────────────────────────────────────────────────
vim.opt.expandtab = true        -- Tab 键插入空格
vim.opt.tabstop = 4             -- 一个制表符显示成 4 列
vim.opt.softtabstop = 4         -- 编辑时按 Tab 等效于 4 个空格
vim.opt.shiftwidth = 4          -- >> << 每次缩进 4 列
vim.opt.shiftround = true       -- >> << 对齐到 shiftwidth 的整数倍（不会缩成奇怪的列数）
vim.opt.autoindent = true       -- 新行沿用上一行缩进
vim.opt.smartindent = true      -- 对新行做基础智能缩进
-- ↑ 这是全局默认；打开具体语言的文件时，内置 ftplugin 会按该语言惯例接管
--    （例如 C 文件自己调缩进参数）——这是 vim 系「分层配置」的正常行为

vim.opt.undofile = true         -- 持久化撤销：关文件甚至明天重开，u 还能一路退回去
vim.fn.mkdir(vim.fn.stdpath("state") .. "/undo", "p")   -- 确保撤销目录存在（undodir 默认就在这里）

vim.opt.mouse = ""              -- 显式全关鼠标（nvim 默认为 "nvi"）——纯键盘路线；想开改回 "a"
vim.opt.clipboard = "unnamedplus"  -- 复制/删除直接进系统剪贴板（Linux 上需 xclip 或 wl-clipboard）
vim.opt.confirm = true          -- :q 有未保存改动时弹确认，而非直接报错


-- ─────────────────────────────────────────────────────────────
-- 4. 插件（lazy.nvim）—— 管理器本体手动放在 ~/.local/share/nvim/lazy/lazy.nvim
-- ─────────────────────────────────────────────────────────────
-- 日常命令：:Lazy（面板：I 安装 / U 更新 / S 同步 / X 清理）｜ :checkhealth（全面体检）
-- 增删插件 = 改下面这张表 + :Lazy sync
-- 刻意不做懒加载（全部启动时加载）：启动开销很小，先省掉一层概念
-- 无 Nerd Font 环境：不装图标依赖 nvim-web-devicons，neo-tree 图标显式关闭（防豆腐块）

vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")
require("lazy").setup({
  -- 配色主题：priority 大 = 启动时先加载，避免先闪默认色再切换
  {
    "folke/tokyonight.nvim",
    priority = 1000,
    config = function()
      vim.cmd.colorscheme("tokyonight-night")   -- 变体：-night / -moon / -storm / -day
    end,
  },

  -- 状态栏（模式 / 文件名 / 行列 / 位置一目了然）
  { "nvim-lualine/lualine.nvim", opts = {} },

  -- 模糊搜索：文件和内容
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
  },

  -- 文件树
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",   -- neo-tree 官方要求钉 v3.x 分支
    dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim" },
    opts = {
      default_component_configs = {
        icon = { enabled = false },   -- 无 Nerd Font → 关图标列；以后装了字体改回 true
      },
      -- 隐藏文件默认不显示；树里按 H 可临时切换（和 yazi 的 . 键同类）
    },
  },

  -- git 行标记（新增/修改/删除显示在行号左侧标记列）
  { "lewis6991/gitsigns.nvim", opts = {} },

  -- 按键提示浮窗：按下 <leader> 停顿一拍，列出后面能按的键
  {
    "folke/which-key.nvim",
    opts = { icons = { breadcrumb = "»", separator = "»", group = "+" } },   -- 只用基本字符，无字体依赖
  },

  -- 编辑增强（mini.nvim 一个仓库两个模块）
  {
    "echasnovski/mini.nvim",
    config = function()
      require("mini.surround").setup()   -- 成对符号：sa 加 / sd 删 / sr 换（例：在词上 saiw" 包引号）
      require("mini.comment").setup()    -- 注释：gcc 本行 / gc 选区 / gcip 整段
    end,
  },

  -- 撤销树可视化
  { "mbbill/undotree" },
}, {
  checker = { enabled = false },   -- 不自动检查插件更新，手动 :Lazy update 即可
})


-- ─────────────────────────────────────────────────────────────
-- 5. 键位（<leader> 即空格键；配合 which-key：按空格停一拍会列出全部）
-- ─────────────────────────────────────────────────────────────
local map = vim.keymap.set
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { desc = "搜索：文件" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>",  { desc = "搜索：文件内容（ripgrep）" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>",    { desc = "搜索：已打开的文件" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>",  { desc = "搜索：帮助文档" })
map("n", "<leader>e",  "<cmd>Neotree toggle<CR>",       { desc = "文件树 开/关" })
map("n", "<leader>u",  "<cmd>UndotreeToggle<CR>",       { desc = "撤销树 开/关" })
map("n", "<Esc><Esc>", "<cmd>nohlsearch<CR>",           { desc = "清除搜索高亮" })
