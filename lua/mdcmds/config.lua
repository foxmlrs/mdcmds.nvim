-- 行内样式表：哪个字母代表哪种样式、加样式时插什么标记。
--   key 是命令里传的字母（:MDInlineToggle b 里的 b）
--   txt 是包在文字两边的标记
-- 注意：新增/改名 key 必须同时改 init.lua 里的 STYLE_KEYS；只改 txt 不用。
-- [改写自] tadmccorkle/markdown.nvim 的 lua/markdown/config.lua（MIT）

local M = {}

local cfg = {
    inline_surround = {
        emphasis = { key = "i", txt = "*" },       -- 斜体（通常渲染成斜体）
        strong = { key = "b", txt = "**" },        -- 粗体
        strikethrough = { key = "s", txt = "~~" }, -- 删除线
        code = { key = "c", txt = "`" },           -- 行内代码
    },
}

---@return table
function M.get()
    return cfg
end

return M
