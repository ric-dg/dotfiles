-- Neovim, no plugins (starts in milliseconds). One file for workstations and servers:
-- guarded so Neovim 0.7+ doesn't error. dotpush sends it to servers.
if vim.loader then vim.loader.enable() end   -- 0.9+: cache compiled Lua, faster start

local o = vim.opt
o.number = true
o.relativenumber = true
o.mouse = "a"
o.ignorecase = true
o.smartcase = true
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.smartindent = true
o.undofile = true                -- undo survives restarts
o.swapfile = false
o.termguicolors = true
o.signcolumn = "yes"
o.scrolloff = 8
o.updatetime = 250
o.splitright = true
o.splitbelow = true
o.list = true
o.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- Clipboard. Over ssh: yanks go to your local clipboard with OSC 52 (through tmux),
-- copy only, because asking the terminal for its clipboard can hang (paste with your
-- terminal's paste key). Locally: the system clipboard (wl-clipboard / xclip).
if vim.env.SSH_TTY then
  if vim.fn.has("nvim-0.10") == 1 then
    local osc52 = require("vim.ui.clipboard.osc52")
    local function paste() return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") } end
    vim.g.clipboard = {
      name = "OSC 52 (copy only)",
      copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
      paste = { ["+"] = paste, ["*"] = paste },
    }
    o.clipboard = "unnamedplus"
  end
else
  o.clipboard = "unnamedplus"
end

vim.g.mapleader = " "
local map = vim.keymap.set
map("n", "<Esc>", "<cmd>nohlsearch<CR>")
map("n", "<leader>w", "<cmd>write<CR>", { desc = "save" })
map("n", "<leader>e", "<cmd>Explore<CR>", { desc = "file explorer" })
map("n", "<leader>f", ":find **/", { desc = "find file" })
map("n", "<leader>g", ":silent grep! ", { desc = "ripgrep" })

if vim.fn.executable("rg") == 1 then
  o.grepprg = "rg --vimgrep --smart-case"
  o.grepformat = "%f:%l:%c:%m"
end
o.path:append("**")

-- highlight yanked text briefly
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() (vim.hl or vim.highlight).on_yank() end,
})

-- Language servers, built in (Neovim 0.11+, no plugins). Each server is defined in
-- lsp/<name>.lua; only those whose command is installed are enabled, and a server
-- starts only when a file of its type is opened. Same file on laptop and servers:
-- install the servers you need (the dotfiles `install.sh lsp` lists them).
-- Built-in keys: K hover, grn rename, gra code action, grr references, gri implementation,
-- gO symbols, [d / ]d diagnostics, <C-s> signature help (insert mode).
if vim.fn.has("nvim-0.11") == 1 then
  local servers = { "lua_ls", "bashls", "pyright", "ruff", "ts_ls", "svelte", "gopls", "rust_analyzer",
    "clangd", "yamlls", "jsonls", "dockerls", "terraformls", "marksman", "taplo" }
  local enabled = {}
  for _, name in ipairs(servers) do
    local cfg = vim.lsp.config[name]
    if cfg and cfg.cmd and type(cfg.cmd) == "table" and vim.fn.executable(cfg.cmd[1]) == 1 then
      enabled[#enabled + 1] = name
    end
  end
  vim.lsp.enable(enabled)
  vim.diagnostic.config({ virtual_text = true, severity_sort = true })
  o.completeopt = { "menu", "menuone", "noinsert", "popup" }
  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if client and client:supports_method("textDocument/completion") then
        vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
      end
      map("n", "<leader>F", function() vim.lsp.buf.format({ async = true }) end, { buffer = ev.buf, desc = "format" })
    end,
  })
end

-- machine-specific additions (untracked): ~/.config/nvim/local.lua
pcall(dofile, vim.fn.stdpath("config") .. "/local.lua")
