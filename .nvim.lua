-- Project-local Neovim config for asteroid2026 (Swift + sourcekit-lsp).
--
-- This file is loaded automatically when you open Neovim from this project
-- directory IF your kickstart.nvim-based config allows project-local config:
--
--   1. In your main init.lua (outside this repo), enable it:
--        vim.opt.exrc = true
--   2. Open nvim here once and run `:trust` (or `:Trust` depending on version)
--      to allowlist this file when Neovim prompts you.
--
-- What it does: starts the Swift toolchain's own `sourcekit-lsp` for `swift`
-- files. kickstart.nvim installs most servers via Mason + nvim-lspconfig, but
-- sourcekit-lsp ships with Swift itself, so it must NOT go through Mason --
-- it just needs to be enabled with the right `cmd` / project root.
--
-- Tested with Neovim 0.11+ (`vim.lsp.config` API used by current kickstart).
-- A legacy `nvim-lspconfig` fallback is kept for older kickstart configs.

-- Avoid double-loading when `:luafile` is run manually.
if vim.g.asteroid2026_sourcekit_loaded then
  return
end
vim.g.asteroid2026_sourcekit_loaded = true

-- 1. Resolve the sourcekit-lsp binary. It ships with the Swift toolchain,
--    so prefer whatever is on PATH (`swiftly`, `xcrun`, apt install, etc.).
local cmd = { vim.fn.exepath("sourcekit-lsp") }
if cmd[1] == "" then
  -- Fallback for swiftly-managed toolchains when PATH is not set inside nvim.
  local home = vim.uv.os_homedir()
  local fallback = home .. "/.local/share/swiftly/bin/sourcekit-lsp"
  if vim.uv.fs_stat(fallback) then
    cmd = { fallback }
  else
    vim.notify(
      "[asteroid2026] sourcekit-lsp not found on PATH (expected from the Swift toolchain). Install Swift or add sourcekit-lsp to PATH.",
      vim.log.levels.WARN
    )
    return
  end
end

-- 2. Build client capabilities the same way kickstart.nvim does, so
--    completion (blink.cmp on current kickstart, cmp-nvim-lsp on older ones)
--    keeps working. Falls back to plain LSP capabilities if neither is present.
local capabilities = vim.lsp.protocol.make_client_capabilities()
local has_blink, blink = pcall(require, "blink.cmp")
if has_blink and blink.get_lsp_capabilities then
  capabilities = blink.get_lsp_capabilities(capabilities)
else
  local has_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
  if has_cmp and cmp_nvim_lsp.default_capabilities then
    capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
  end
end

local sourcekit_config = {
  cmd = cmd,
  filetypes = { "swift", "objc", "objcpp" },
  root_markers = { "Package.swift", ".git", "compile_commands.json" },
  capabilities = capabilities,
}

-- 3. Register and enable. Current kickstart (Neovim 0.11+) uses the native
--    `vim.lsp.config` / `vim.lsp.enable` API; older kickstart uses lspconfig.
if vim.lsp and vim.lsp.config then
  vim.lsp.config("sourcekit", sourcekit_config)
  vim.lsp.enable("sourcekit")
else
  local ok, lspconfig = pcall(require, "lspconfig")
  if ok and lspconfig.sourcekit then
    lspconfig.sourcekit.setup(sourcekit_config)
  else
    vim.notify(
      "[asteroid2026] neither vim.lsp.config nor nvim-lspconfig is available; cannot configure sourcekit-lsp.",
      vim.log.levels.WARN
    )
  end
end
