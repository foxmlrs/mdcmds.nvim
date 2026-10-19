-- treesitter 辅助：找满足条件的节点、数字节点数、判断是否占满父节点、按节点找注入树。
-- [改写自] tadmccorkle/markdown.nvim 的 lua/markdown/treesitter.lua（MIT）

local ts = vim.treesitter

local M = {}

--- Finds the smallest node satisfying `predicate` based on the provided options.
---@param predicate fun(node: TSNode): boolean
---@param opts table? `vim.treesitter.get_node` opts
---@return TSNode|nil
---
---@see vim.treesitter.get_node
function M.find_node(predicate, opts)
	local node = ts.get_node(opts)
	while node ~= nil and not predicate(node) do
		node = node:parent()
	end
	return node
end

--- Gets the number of `node`'s children that satisfy `predicate`.
---@param node TSNode
---@param predicate fun(child: TSNode): boolean
---@return integer
function M.child_count(node, predicate)
	local count = 0
	for child in node:iter_children() do
		if predicate(child) then
			count = count + 1
		end
	end
	return count
end

--- Determines if `node` spans the inner range of its immediate parent.
---@param node TSNode
---@param inner_col_offset? integer `1` if not provided
---@return boolean
---
--- The inner column offset is used to narrow the subrange of the parent checked. For example, if
--- the node's range is `{ 0, 2, 1, 8 }` and its parent range is `{ 0, 0, 1, 10 }`, this will return
--- true given an offset of `2`.
function M.spans_parent_range(node, inner_col_offset)
	local parent = node:parent()
	if parent == nil then
		return false
	end

	local range = { node:range() }
	local parent_range = { parent:range() }

	inner_col_offset = inner_col_offset or 1
	return range[1] == parent_range[1] and range[3] == parent_range[3]
		and range[2] == parent_range[2] + inner_col_offset
		and range[4] == parent_range[4] - inner_col_offset
end

--- Finds a tree from `trees` contained within the `node`.
---@param trees TSTree[]
---@param node TSNode
---@return TSTree|nil
function M.find_tree_in_node(trees, node)
	for _, t in pairs(trees) do
		if ts.node_contains(node, { t:root():range() }) then
			return t
		end
	end
end

local single_node_from_match

if vim.fn.has("nvim-0.10.0") == 1 then
	---@param match table<integer, TSNode[]>
	---@param captureIndex integer
	single_node_from_match = function(match, captureIndex)
		local nodes = match[captureIndex]
		if nodes ~= nil then
			return nodes[1]
		else
			return nil
		end
	end
else
	---@param match table<integer, TSNode>
	---@param captureIndex integer
	single_node_from_match = function(match, captureIndex)
		return match[captureIndex]
	end
end

--- Gets a single node from a tree-sitter match obtained from
--- `vim.treesitter.Query:iter_matches`.
---
--- Behaves as if the node is obtained by indexing into a match table with `captureIndex`. Returns
--- `nil` if no node is matched to that capture group.
---
--- Provides backwards compatibility with nvim <0.10.0. Assumes the soon-to-be default behavior of
--- `iter_matches` with the option `all = true` is used in nvim >=0.10.0.
---@type fun(match: table<integer, TSNode|TSNode[]>, captureIndex: integer): TSNode
M.single_node_from_match = single_node_from_match

return M
