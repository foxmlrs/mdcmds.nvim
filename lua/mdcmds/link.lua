-- 链接：M.add(r) 把范围内的文字包成 [文字]()，光标落在括号里并进插入模式等敲地址。
-- 不做任何自动钩子（不包装 vim.paste），只有命令触发才会动 buffer。
-- [改写自] tadmccorkle/markdown.nvim 的 lua/markdown/link.lua（MIT）

local api = vim.api
local ts = vim.treesitter

local md_ts = require("mdcmds.treesitter")
local notify = require("mdcmds.notify")
local util = require("mdcmds.util")

local M = {}

---@param node TSNode
---@return boolean
local function is_inline(node)
	return node:type() == "inline"
end

--- 范围不在一个行内块里就报一声、不动 buffer
---@param r R4
---@return boolean
local function range_is_inline(r)
	ts.get_parser(0, "markdown"):parse()
	local inline = md_ts.find_node(is_inline, { pos = { r[1], r[2] } })
	if inline == nil or not ts.node_contains(inline, r) then
		notify.info("范围不在一个行内块里（跨空行 / 含列表标记之类），没动")
		return false
	end
	return true
end

--- 把范围里的文字包成 [文字]()，然后进插入模式等敲地址。
---@param r R4 目标范围
function M.add(r)
	if not range_is_inline(r) then
		return
	end

	util.insert_text(r[3], r[4], "]()")
	util.insert_text(r[1], r[2], "[")

	-- enter insert mode to type destination
	local col = r[4] + 2
	if r[1] == r[3] then
		col = col + 1
	end
	api.nvim_win_set_cursor(0, { r[3] + 1, col })
	vim.cmd("startinsert")
end

return M
