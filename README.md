# mdcmds.nvim

Neovim 里编辑 markdown 的**一组命令**（`lua/mdcmds/`），只注册 `:MDxxx`，**不带任何键位**。

- 所有命令都是 **markdown 缓冲区局部**的：别的 filetype 里根本不存在
- 加载时只注册命令，不改 buffer、不挂 `vim.paste`：你不敲命令，文档一个字节都不会变
- 只管编辑，**不管渲染**（渲染请用 render-markdown.nvim 之类）
- 依赖 treesitter 的 `markdown` parser；行内样式还需要 `markdown` 的 inline 注入

改写自 [tadmccorkle/markdown.nvim](https://github.com/tadmccorkle/markdown.nvim)（MIT）：
只保留了列表 / 链接 / 行内样式，TOC、标题跳转、`<Plug>` 映射、粘贴 URL 自动转链接全部删掉。

## 安装

```lua
vim.pack.add({
    { src = "https://github.com/<你的用户名>/mdcmds.nvim" },
})

require("mdcmds").setup() -- 只在 markdown 缓冲区注册 :MDxxx 命令
```

模块名是 `mdcmds`，所以仓库根下必须是 `lua/mdcmds/*.lua`。

## 命令

列表

| 命令 | 说明 |
| --- | --- |
| `:MDListItemBelow` | 在光标项下面插新项（缩进、标记照抄；有序一律写 `1.`；任务项带 `[ ] `） |
| `:MDListItemAbove` | 同上，插在上面 |
| `:MDResetListNumbering [range]` | 重排有序列表号（顺手把 `1)` 规整成 `1.`；不给 range = 整个 buffer） |
| `:MDTaskToggle [range]` | 切任务框（有未勾的全勾，否则全不勾；不给 range = 当前行） |

链接

| 命令 | 说明 |
| --- | --- |
| `:MDLinkAdd [range]` | 把范围文字包成 `[文字]()`，光标落在括号里并进插入模式等你敲地址 |

行内样式（样式键：`i` 斜体、`b` 粗体、`s` 删除线、`c` 行内代码）

| 命令 | 说明 |
| --- | --- |
| `:MDInlineToggle {i\|b\|s\|c} [range]` | 加 / 去样式（不给 range = 当前行；不给样式键 = 等敲一个字母） |
| `:MDInlineDelete {i\|b\|s\|c}` | 删掉包住光标的那层样式 |
| `:MDInlineChange {a} {b}` | 把包住光标的那层样式换成另一种 |
| `:MDInlineSmart {i\|b\|s\|c} [range]` | 上面三条的合并版：已包着目标样式 → 删；包着别种 → 改；什么都没包 → 加上 |

## range 规则

- 命令都吃 Vim 的 range：`:5,9MDInlineToggle b`、`:'<,'>MDLinkAdd`、`:MDTaskToggle`
- `:'<,'>`（可视模式）→ 用真实选区（带列）；手写行号 → 整行；不给 → 当前行
- 行内样式按 **inline 节点**生效：标题文字会加样式，列表标记 / 代码块围栏不受影响

## 自定义键位

插件自己一个键都不注册。常见的做法是在自己的配置里，用 `FileType` autocmd 挂 buffer 局部键：

```lua
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "markdown" },
    callback = function(args)
        local o = { buffer = args.buf }
        vim.keymap.set("n", "<leader>mx", "<Cmd>MDTaskToggle<CR>", vim.tbl_extend("force", o, { desc = "切任务框" }))
        vim.keymap.set("x", "<leader>mx", ":MDTaskToggle<CR>", vim.tbl_extend("force", o, { desc = "切任务框" }))
        vim.keymap.set("n", "<leader>ml", "<Cmd>MDLinkAdd<CR>", vim.tbl_extend("force", o, { desc = "链接" }))
        vim.keymap.set("n", "<leader>mb", "<Cmd>MDInlineSmart b<CR>", vim.tbl_extend("force", o, { desc = "粗体" }))
    end,
})
```

> 可视模式映射要用 `:` 开头（Vim 会自动带 `<,'>` 范围）；用 `<Cmd>` 会丢范围，`:MDLinkAdd` 会退化成整行。

## 配置

行内样式的标记写在 `lua/mdcmds/config.lua` 的 `inline_surround` 表里（`*` / `**` / `~~` / ` ` `），`setup()` 不接受参数，调用一次就把它挂到 markdown 缓冲区上。

新增 / 改名样式键（`i` `b` `s` `c`）要同时改 `config.lua` 和 `init.lua` 里的 `STYLE_KEYS`；只改标记文本的话只改 `config.lua`。

## License

MIT，见 [LICENSE](./LICENSE)。原始实现版权归 tadmccorkle（markdown.nvim）所有。
