# Neovim Config (kickstart.nvim derivative)

## Structure

- `init.lua` — entrypoint; options, keymaps, lazy.nvim bootstrap, and `{ import = "custom.plugins" }`
- `lua/custom/plugins/*.lua` — one file per plugin or concern (snacks, lsp, telescope, blink-cmp, etc.)
- `lua/kickstart/plugins/*.lua` — unused kickstart modular plugins (not imported; kept for reference)

## Keymaps

| Keys | Action |
|------|--------|
| `<space>` | Leader |
| `<A-,>` / `<A-.>` | Prev/next buffer |
| `<A-1>`–`<A-9>` | Goto buffer position |
| `<A-c>` | Close buffer |
| `<leader>E` | Toggle NvimTree |
| `<leader>f` | Format buffer (conform.nvim) |
| `s` / `S` (normal) | Flash jump / Treesitter jump |
| `<leader>gg` | Open lazygit (via snacks) |
| `<leader>z` | Toggle zen mode (via snacks) |
| `<leader>gb` / `gl` / `gs` / `gd` / `gf` | Git branches/log/status/diff/file-log (via snacks) |
| `<leader>u*` | Toggle toggles (spell/wrap/relnum/diagnostics/conceal/etc) |
| `:Google <query>` | Opens Google search URL in browser |

## Plugin Management

- **Manager:** lazy.nvim — plugins install automatically on first `nvim` launch
- `:Lazy` — UI to view/update/check status
- `:Lazy update` — update all plugins
- `:Mason` — manage LSP servers, linters, formatters
- `lazy-lock.json` is **gitignored** (per kickstart default; re-enable tracking if desired)

## LSP & Tooling

- **Completion:** blink.cmp (not nvim-cmp) — configured in `blink-cmp.lua`
- **Format on save:** conform.nvim with timeout 500ms; `<leader>f` for manual format
- **LSP servers defined** in `lsp.lua` under the `servers` table (only `lua_ls` active by default, plus `ocamllsp` and `tinymist`)
- **OCaml:** `vim.lsp.enable("ocamllsp")`, tinymist for Typst configured in `lsp.lua`
- **Diagnostics:** `tiny-inline-diagnostic` replaces default virtual text (`virtual_text` is disabled)
- **Treesitter** auto-installs languages; `:TSUpdate` to update parsers
- `:checkhealth` to verify the setup

## Adding a new plugin

Create a new `.lua` file in `lua/custom/plugins/` returning a lazy.nvim spec table. lazy.nvim auto-loads all files from that directory on next startup. No need to edit `init.lua`.

## Notable

- Colorscheme: astrotheme (astrodark palette)
- Nerd Font enabled (`vim.g.have_nerd_font = true`)
- Tab width: 2 spaces
- Clipboard synced with OS (`unnamedplus`)
- Markdown preview via peek.nvim (`:PeekOpen` / `:PeekClose`)
- Typst autopairs: `$`, `*`, `_` rules defined in autopairs.lua
