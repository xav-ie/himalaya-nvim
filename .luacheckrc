std = "lua51"
read_globals = { "vim" }
globals = { "vim.g", "vim.b", "vim.w", "vim.o", "vim.bo", "vim.wo", "vim.go", "vim.opt_local" }

files["tests/"] = {
  read_globals = {
    "describe", "it", "before_each", "after_each",
    "setup", "teardown", "insulate", "assert", "spy", "stub", "mock",
    "pending", "finally", "jit",
  },
  globals = {
    "vim.fn", "vim.api", "vim.cmd", "vim.ui", "vim.notify",
  },
}

-- Ignore line-length (stylua handles formatting)
ignore = { "631" }
