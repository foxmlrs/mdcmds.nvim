-- ============================================================
-- markdown 编辑工具（只有命令，没有任何键位）
--
-- 全部功能都挂在 **markdown 缓冲区** 上（buffer 局部命令，别的文件类型里不存在），
-- 命令名统一 :MD 前缀。插件加载只做一件事：把这些命令注册出来。
-- 不设键位、不包装 vim.paste、不读不写 buffer —— 你不敲命令，文档一个字节都不会变。
--
-- 列表
--   :MDListItemBelow                在光标项下面插新项（缩进、标记照抄；有序一律写 "1."；任务项带 "[ ] "）
--   :MDListItemAbove                同上，插在上面
--   :MDResetListNumbering [range]   重排有序列表号（顺手把 "1)" 规整成 "1."；不给 range = 整个 buffer）
--   :MDTaskToggle [range]           切任务框（有未勾的全勾，否则全不勾；不给 range = 当前行）
-- 链接
--   :MDLinkAdd [range]              把范围文字包成 [文字]()，光标落在括号里，进插入模式等敲地址
-- 行内样式（样式键 i=斜体 b=粗体 s=删除线 c=行内代码，标记在 config.lua）
--   :MDInlineToggle {i|b|s|c} [range]     加/去样式（不给 range = 当前行；不给样式键 = 等敲一个字母）
--   :MDInlineDelete {i|b|s|c}             删掉包住光标的那层样式（无 range，看光标）
--   :MDInlineChange {i|b|s|c} {i|b|s|c}   把包住光标的那层换成另一种（无 range，看光标）
--   :MDInlineSmart {i|b|s|c} [range]      上面三条的合并版（给键位用）：
--                                         已包着目标样式 → 删；包着别种 → 改；什么都没包 → 给 range 加上
--
-- range 规则
--   * 命令都吃 Vim 的 range：`:5,9MDInlineToggle b`、`:'<,'>MDLinkAdd`、`:MDTaskToggle`
--   * `:'<,'>`（可视模式）→ 用真实选区（带列）；手写行号 → 整行；不给 → 当前行
--   * 行内样式按 **inline 节点** 生效：标题文字会加样式，列表标记 / 代码块围栏不受影响
--
-- 依赖：treesitter 的 markdown parser（行内样式还需要 markdown 的 inline 注入）
-- [改写自] tadmccorkle/markdown.nvim（MIT），用法见文件头即可，不需要读源码
-- ============================================================

local api = vim.api

local inline = require("mdcmds.inline")
local link = require("mdcmds.link")
local list = require("mdcmds.list")
local notify = require("mdcmds.notify")
local util = require("mdcmds.util")

local M = {}

-- 样式键（和 config.lua 里的 key 对应）
local STYLE_KEYS = { "i", "b", "s", "c" }

---@param key any
---@return boolean
local function is_style(key)
    return type(key) == "string" and vim.tbl_contains(STYLE_KEYS, key)
end

--- 命令补全：样式键
---@param lead string
---@return string[]
local function complete_style(lead)
    return vim.tbl_filter(function(k)
        return vim.startswith(k, lead)
    end, STYLE_KEYS)
end

--- 命令的 range → R4
---   从可视模式过来（:'<,'>，Vim 报的 range 是 2 且与 '< '> 两标记完全对得上）→ 用真正的选区（带列）
---   手写行号范围 / 没给 range                  → 整行
---@param opts table
---@return R4
local function cmd_range(opts)
    if opts.range == 2 then
        local s = api.nvim_buf_get_mark(0, "<")
        local e = api.nvim_buf_get_mark(0, ">")
        if s[1] ~= 0 and s[1] == opts.line1 and e[1] == opts.line2 then
            return util.get_visual_range()
        end
    end
    local s, e = util.get_user_command_range(opts)
    return util.get_line_range(s, e)
end

--- 注册 markdown 缓冲区里的命令
---@param bufnr integer
local function register_cmds(bufnr)
    ---@param name string
    ---@param cmd function
    ---@param opts table
    local function create(name, cmd, opts)
        api.nvim_buf_create_user_command(bufnr, name, cmd, opts)
    end

    -- ------------- 列表 -------------
    create("MDListItemBelow", function()
        list.insert_list_item_below()
    end, { desc = "在光标项下面插入新列表项" })

    create("MDListItemAbove", function()
        list.insert_list_item_above()
    end, { desc = "在光标项上面插入新列表项" })

    create("MDResetListNumbering", function(opts)
        local s, e
        if opts.range ~= 0 then
            s, e = util.get_user_command_range(opts)
        else
            s, e = 0, -1 -- 整个 buffer
        end
        list.reset_list_numbering(s, e)
    end, { range = true, desc = "重排有序列表号" })

    create("MDTaskToggle", function(opts)
        local s, e = util.get_user_command_range(opts)
        list.toggle_task(s, e)
    end, { range = true, desc = "切换任务框 [ ] ↔ [x]" })

    -- ------------- 链接 -------------
    create("MDLinkAdd", function(opts)
        link.add(cmd_range(opts))
    end, { range = true, desc = "把范围内的文字包成 [文字](地址)" })

    -- ------------- 行内样式 -------------
    create("MDInlineToggle", function(opts)
        local key = opts.fargs[1]
        if key ~= nil and not is_style(key) then
            return notify.error("样式键只能是 i / b / s / c（斜体 / 粗体 / 删除线 / 行内代码）")
        end
        inline.toggle_emphasis(cmd_range(opts), key)
    end, { range = true, nargs = "?", complete = complete_style, desc = "给范围内的文字加/去行内样式" })

    create("MDInlineDelete", function(opts)
        local key = opts.fargs[1]
        if key ~= nil and not is_style(key) then
            return notify.error("样式键只能是 i / b / s / c（斜体 / 粗体 / 删除线 / 行内代码）")
        end
        inline.delete_emphasis(key)
    end, { nargs = "?", complete = complete_style, desc = "删掉包住光标的那层行内样式" })

    create("MDInlineChange", function(opts)
        local from, to = opts.fargs[1], opts.fargs[2]
        -- 一个都不给：跟原来的 cs{from}{to} 一样，等敲两个字母
        if from == nil and to == nil then
            return inline.change_emphasis(nil, nil)
        end
        if not (is_style(from) and is_style(to)) then
            return notify.error("用法：:MDInlineChange {原样式} {新样式}，样式键 i / b / s / c")
        end
        inline.change_emphasis(from, to)
    end, { nargs = "*", complete = complete_style, desc = "把包住光标的样式换成另一种" })

    create("MDInlineSmart", function(opts)
        local key = opts.fargs[1]
        if key ~= nil and not is_style(key) then
            return notify.error("样式键只能是 i / b / s / c（斜体 / 粗体 / 删除线 / 行内代码）")
        end
        inline.smart(key, cmd_range(opts))
    end, { range = true, nargs = "?", complete = complete_style, desc = "合并版：已带→删，带别种→改，没有→加" })
end

local group = api.nvim_create_augroup("MarkdownTools", { clear = true })

function M.setup()
    local fts = vim.treesitter.language.get_filetypes("markdown")

    -- 注意：这个 autocmd 只负责「在 markdown 缓冲区里把这些命令注册出来」，
    -- 不碰 buffer 内容，也不设任何键位。
    api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = fts,
        desc = "markdown 工具命令（改写版 markdown.nvim，只注册命令）",
        callback = function(opts)
            register_cmds(opts.buf)
        end,
    })

    -- setup 之前就已经打开的 markdown 缓冲区也补注册一次
    -- （按 filetype 自己判断，不靠合成 FileType 事件，免得碰到别的缓冲区）
    for _, bufnr in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(bufnr) and vim.tbl_contains(fts, vim.bo[bufnr].filetype) then
            register_cmds(bufnr)
        end
    end
end

return M
