-- 列表：插新项 / 重排有序号 / 切任务框。
-- 对外函数见文件末尾：insert_list_item_above / insert_list_item_below /
-- reset_list_numbering / toggle_task，以及给「插入模式回车续接」判断用的 in_list_item()。
-- 有序项标记一律写成 "1."（渲染器自己排号）；要真实序号显式用 reset_list_numbering。
-- [改写自] tadmccorkle/markdown.nvim 的 lua/markdown/list.lua（MIT）

local api = vim.api
local ts = vim.treesitter

local md_ts = require("mdcmds.treesitter")
local util = require("mdcmds.util")

local M = {}

local LIST_ITEM_TYPE = "list_item"
local LIST_MARKER_DOT_TYPE = "list_marker_dot"
local LIST_MARKER_PAREN_TYPE = "list_marker_parenthesis"
local TASK_MARKER_CHECKED_TYPE = "task_list_marker_checked"
local TASK_MARKER_UNCHECKED_TYPE = "task_list_marker_unchecked"
local PARAGRAPH_TYPE = "paragraph"
local INLINE_TYPE = "inline"

local ordered_list_query = ts.query.parse("markdown", [[
	(list
		(list_item [
			(list_marker_dot)
			(list_marker_parenthesis)
		])) @l
]])
--
---@param node TSNode
---@return boolean
local function is_list_item(node)
	return node:type() == LIST_ITEM_TYPE
end

---@param list_item TSNode
---@param change integer
local function adjust_child_indent(list_item, change)
	local li_row = list_item:start()
	for child in list_item:iter_children() do
		local start_row, start_col, end_row, _ = child:range()
		if start_row ~= li_row and start_col ~= 0 then
			-- final row is a block continuation and shouldn't be changed
			for row = start_row, end_row - 1, 1 do
				if change < 0 then
					util.delete_text(row, 0, math.abs(change))
				else
					util.insert_text(row, 0, string.rep(" ", change))
				end
			end
		end
	end
end

--- 把有序项的编号写成 num，"1." 的点号形式（顺手把 "1)" 这种也规整成 "1."）
---
--- 所有列位置都从 **marker 节点**算，不用 list_item:start()：
--- treesitter 的 markdown parser 会把缩进吞进「列表第一项」的 list_item/marker 里
--- （`  1) a` 的 list_item 起在列 0，marker 原文是 "  1) "），拿 list_item 起点去替换会写坏文本。
---@param list_item TSNode
local function set_list_item_num(list_item, num)
	local marker = list_item:named_child(0)
	if marker == nil then
		return
	end

	local marker_text = ts.get_node_text(marker, 0, nil)
	local row, marker_col = marker:start()

	-- 1) 先把括号型标记 "1)" 改成 "1."：同宽替换，不影响下一步数字列的坐标
	if marker:type() == LIST_MARKER_PAREN_TYPE then
		local paren = marker_text:find(")", 1, true)
		if paren ~= nil then
			util.replace_text(row, marker_col + paren - 1, 1, ".")
		end
	end

	-- 2) 再把数字换成 num（marker 原文可能带前导空白，按 match 出来的偏移算列）
	local digit_start, digits = marker_text:match("()(%d+)")
	if digits == nil then
		return
	end

	local num_str = tostring(num)
	if digits == num_str then
		return
	end

	util.replace_text(row, marker_col + digit_start - 1, #digits, num_str)

	local child_indent_change = #num_str - #digits
	if child_indent_change ~= 0 then
		adjust_child_indent(list_item, child_indent_change)
	end
end

---@param list TSNode
local function reset_list_numbering(list)
	local num = 1
	for list_item in list:iter_children() do
		if list_item:named() then
			set_list_item_num(list_item, num)
			num = num + 1
		end
	end
end

--- Resets list numbering in the current buffer.
---@param start_row integer Zero-based start row
---@param end_row integer Zero-based end row
---
--- Specify start = 0 and end = -1 to reset list numbering
--- for all lists in the current buffer.
function M.reset_list_numbering(start_row, end_row)
	if end_row >= 0 then
		end_row = end_row + 1
	end

	local t = ts.get_parser(0, "markdown"):parse()[1]
	for _, match, _ in ordered_list_query:iter_matches(t:root(), 0, start_row, end_row, { all = true }) do
		local list = md_ts.single_node_from_match(match, 1)
		reset_list_numbering(list)
	end
end

---@param list_item TSNode
local function get_last_list_item_inline(list_item)
	for i = list_item:named_child_count() - 1, 0, -1 do
		local child = list_item:named_child(i) --[[@as TSNode]]
		if child:type() == PARAGRAPH_TYPE then
			for j = child:named_child_count() - 1, 0, -1 do
				if child:named_child(j):type() == INLINE_TYPE then
					return child:named_child(j)
				end
			end
		end
	end
end

---@return integer row, integer col
local function get_curr_eol_pos()
	local curr_row = util.get_cursor()
	local curr_eol = vim.fn.col("$") - 1
	return curr_row, curr_eol
end

---@enum rel_pos relative position
local REL_POS = {
	above = 1,
	below = 2,
}

---@param loc rel_pos
---@return boolean
local function insert_list_item(loc)
	local curr_row, curr_eol = get_curr_eol_pos()

	ts.get_parser(0, "markdown"):parse()
	local list_item = md_ts.find_node(is_list_item, { pos = { curr_row, curr_eol } })
	if list_item == nil then
		return false
	end

	local marker = list_item:named_child(0)
	if marker == nil then
		return false
	end

	local marker_type = marker:type()
	local marker_row, marker_col = marker:start()

	---@type TSNode|nil
	local task_marker = marker:next_named_sibling()
	if
		task_marker ~= nil
		and task_marker:type() ~= TASK_MARKER_CHECKED_TYPE
		and task_marker:type() ~= TASK_MARKER_UNCHECKED_TYPE
	then
		task_marker = nil
	end

	local new_row
	if loc == REL_POS.above then
		new_row = list_item:start()
	else
		local inline = get_last_list_item_inline(list_item)
		if inline ~= nil then
			local inline_end = inline:end_()
			new_row = inline_end + 1
		else
			new_row = marker_row + 1
		end
	end

	-- 缩进：同一行 marker 起点之前的字符（第一项时 marker 会把缩进也吞进去，要加上那段的长度）
	local marker_text = ts.get_node_text(marker, 0, nil)
	local marker_leading_ws = #marker_text - #(marker_text:gsub("^%s+", ""))
	local indent = api.nvim_buf_get_text(0, marker_row, 0, marker_row, marker_col + marker_leading_ws, {})[1]
	local marker_txt = marker_text:gsub("^%s+", "") -- 第一项的 marker 原文带缩进，剥掉（缩进已单独算）
	local is_ordered = marker_type == LIST_MARKER_DOT_TYPE or marker_type == LIST_MARKER_PAREN_TYPE
	if is_ordered then
		-- 有序项一律写 "1. "：渲染器会自己排号，也省得 "1)" / "2." 混着出现
		-- （marker 节点的原文里不含标记后的空白，所以空格自己补上）
		marker_txt = "1. "
	end
	local task_marker_txt = task_marker and "[ ] " or ""
	api.nvim_buf_set_lines(0, new_row, new_row, true, { indent .. marker_txt .. task_marker_txt })

	new_row = new_row + 1
	api.nvim_win_set_cursor(0, { new_row, vim.fn.col({ new_row, "$" }) })
	vim.cmd("startinsert!")
	return true
end

--- Inserts a list item above the cursor in the current buffer.
---@return boolean # true if an item is inserted above, otherwise false
function M.insert_list_item_above()
	return insert_list_item(REL_POS.above)
end

--- Inserts a list item below the cursor in the current buffer.
---@return boolean # true if an item is inserted below, otherwise false
function M.insert_list_item_below()
	return insert_list_item(REL_POS.below)
end

---@param node TSNode
---@return boolean
local function is_task_list_item(node)
	if node:type() ~= LIST_ITEM_TYPE then
		return false
	end

	local task_marker = node:named_child(1)
	if task_marker == nil then
		return false
	end

	local tm_type = task_marker:type()
	return tm_type == TASK_MARKER_CHECKED_TYPE
		or tm_type == TASK_MARKER_UNCHECKED_TYPE
end

--- 光标是否在列表项里（不修改 buffer；给插入模式「回车续接列表」之类的判断用）
---@return boolean
function M.in_list_item()
	local row = util.get_cursor()
	local eol = vim.fn.col("$") - 1
	ts.get_parser(0, "markdown"):parse()
	return md_ts.find_node(is_list_item, { pos = { row, eol } }) ~= nil
end

--- Toggles list item task markers.
---@param start_row integer Zero-based start row
---@param end_row integer Zero-based end row
function M.toggle_task(start_row, end_row)
	ts.get_parser(0, "markdown"):parse()
	local task_markers = {}

	local last_node
	for row = start_row, end_row, 1 do
		local eol = vim.fn.col({ row + 1, "$" }) - 1
		local node = md_ts.find_node(is_task_list_item, { pos = { row, eol } })
		if node ~= nil and node ~= last_node then
			table.insert(task_markers, node:named_child(1))
			last_node = node
		end
	end

	local checked = false
	for i = 1, #task_markers, 1 do
		if task_markers[i]:type() == TASK_MARKER_UNCHECKED_TYPE then
			local row, start_col, _, end_col = task_markers[i]:range()
			util.replace_text(row, start_col, end_col - start_col + 1, "[x] ")
			checked = true
		end
	end

	if not checked then
		for i = 1, #task_markers, 1 do
			local row, start_col, _, end_col = task_markers[i]:range()
			util.replace_text(row, start_col, end_col - start_col + 1, "[ ] ")
		end
	end
end

return M
