-- 统一提示：前缀 "markdown: "，schedule_wrap 避免在 treesitter 回调里直接 notify。
-- [改写自] tadmccorkle/markdown.nvim 的 lua/markdown/notify.lua（MIT）

local M = {}

---@param level integer
---@return fun(fmt: string, ...: any)
local function notify(level)
	return vim.schedule_wrap(function(s, ...)
		vim.notify("markdown: " .. s:format(...), level)
	end)
end

---@param fmt string Format string
---@param ... any Optional format string arguments
function M.info(fmt, ...)
	notify(vim.log.levels.INFO)(fmt, ...)
end

---@param fmt string Format string
---@param ... any Optional format string arguments
function M.error(fmt, ...)
	notify(vim.log.levels.ERROR)(fmt, ...)
end

return M
