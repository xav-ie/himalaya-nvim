# VimScript to Lua Migration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate the entire himalaya-nvim plugin from VimScript to Lua, targeting Neovim 0.10+ only, with plenary.nvim tests alongside each module.

**Architecture:** Bottom-up migration of leaf modules first (log, config, job, request), then state/domain utilities, pickers, core email domain, UI layers, and finally the entry point. Old VimScript and new Lua coexist during migration via `vim.fn` / `luaeval` bridging. Each module gets tests before its VimScript counterpart is deleted.

**Tech Stack:** Neovim 0.10+, Lua, `vim.system()`, `vim.notify`, plenary.nvim (testing), `vim.ui.select` (native picker)

---

### Task 1: Set up test infrastructure

**Files:**
- Create: `tests/minimal_init.lua`
- Create: `Makefile`

**Step 1: Create minimal Neovim config for test runner**

```lua
-- tests/minimal_init.lua
vim.opt.runtimepath:append('.')

local plenary_path = vim.fn.stdpath('data') .. '/site/pack/test/start/plenary.nvim'
if vim.fn.isdirectory(plenary_path) == 0 then
  vim.fn.system({
    'git', 'clone', '--depth', '1',
    'https://github.com/nvim-lua/plenary.nvim',
    plenary_path,
  })
end
vim.opt.runtimepath:append(plenary_path)
```

**Step 2: Create Makefile with test target**

```makefile
.PHONY: test

test:
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

**Step 3: Create a smoke test to verify the harness works**

Create `tests/himalaya/smoke_spec.lua`:

```lua
describe('test harness', function()
  it('can run tests', function()
    assert.is_true(true)
  end)
end)
```

**Step 4: Run the smoke test**

Run: `make test`
Expected: 1 test passes, plenary.nvim auto-clones if missing

**Step 5: Commit**

```bash
git add tests/minimal_init.lua tests/himalaya/smoke_spec.lua Makefile
git commit -m "build: add plenary.nvim test infrastructure"
```

---

### Task 2: Migrate `log.lua`

**Files:**
- Create: `lua/himalaya/log.lua`
- Test: `tests/himalaya/log_spec.lua`
- Replaces: `autoload/himalaya/log.vim` (17 lines)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/log_spec.lua
describe('himalaya.log', function()
  local log = require('himalaya.log')

  it('exposes info, warn, and err functions', function()
    assert.is_function(log.info)
    assert.is_function(log.warn)
    assert.is_function(log.err)
  end)

  it('calls vim.notify with correct level for info', function()
    local called_with = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      called_with = { msg = msg, level = level }
    end
    log.info('test message')
    vim.notify = orig
    assert.are.equal('test message', called_with.msg)
    assert.are.equal(vim.log.levels.INFO, called_with.level)
  end)

  it('calls vim.notify with correct level for warn', function()
    local called_with = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      called_with = { msg = msg, level = level }
    end
    log.warn('warning')
    vim.notify = orig
    assert.are.equal('warning', called_with.msg)
    assert.are.equal(vim.log.levels.WARN, called_with.level)
  end)

  it('calls vim.notify with correct level for err', function()
    local called_with = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      called_with = { msg = msg, level = level }
    end
    log.err('error')
    vim.notify = orig
    assert.are.equal('error', called_with.msg)
    assert.are.equal(vim.log.levels.ERROR, called_with.level)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module `himalaya.log` not found

**Step 3: Write minimal implementation**

```lua
-- lua/himalaya/log.lua
local M = {}

function M.info(msg)
  vim.notify(msg, vim.log.levels.INFO)
end

function M.warn(msg)
  vim.notify(msg, vim.log.levels.WARN)
end

function M.err(msg)
  vim.notify(msg, vim.log.levels.ERROR)
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All 4 tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/log.lua tests/himalaya/log_spec.lua
git commit -m "feat: migrate log module to Lua"
```

---

### Task 3: Migrate `config.lua`

**Files:**
- Create: `lua/himalaya/config.lua`
- Test: `tests/himalaya/config_spec.lua`
- Replaces: scattered `g:himalaya_*` variable reads

**Step 1: Write the failing test**

```lua
-- tests/himalaya/config_spec.lua
describe('himalaya.config', function()
  local config

  before_each(function()
    package.loaded['himalaya.config'] = nil
    config = require('himalaya.config')
    config._reset()
  end)

  it('returns defaults when setup not called', function()
    local c = config.get()
    assert.are.equal('himalaya', c.executable)
    assert.is_nil(c.config_path)
    assert.is_nil(c.folder_picker)
    assert.are.equal(false, c.telescope_preview)
    assert.is_nil(c.complete_contact_cmd)
    assert.are.same({}, c.custom_flags)
    assert.are.equal(true, c.always_confirm)
  end)

  it('deep merges user overrides', function()
    config.setup({ executable = '/usr/bin/himalaya', always_confirm = false })
    local c = config.get()
    assert.are.equal('/usr/bin/himalaya', c.executable)
    assert.are.equal(false, c.always_confirm)
    -- untouched defaults remain
    assert.are.same({}, c.custom_flags)
  end)

  it('merges custom_flags correctly', function()
    config.setup({ custom_flags = { 'important', 'urgent' } })
    local c = config.get()
    assert.are.same({ 'important', 'urgent' }, c.custom_flags)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module `himalaya.config` not found

**Step 3: Write minimal implementation**

```lua
-- lua/himalaya/config.lua
local M = {}

local defaults = {
  executable = 'himalaya',
  config_path = nil,
  folder_picker = nil,
  telescope_preview = false,
  complete_contact_cmd = nil,
  custom_flags = {},
  always_confirm = true,
}

local current = vim.deepcopy(defaults)

function M.setup(opts)
  current = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
end

function M.get()
  return current
end

function M._reset()
  current = vim.deepcopy(defaults)
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All 3 tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/config.lua tests/himalaya/config_spec.lua
git commit -m "feat: migrate config module to Lua with setup() pattern"
```

---

### Task 4: Migrate `job.lua`

**Files:**
- Create: `lua/himalaya/job.lua`
- Test: `tests/himalaya/job_spec.lua`
- Replaces: `autoload/himalaya/job.vim`, `autoload/himalaya/job/neovim.vim`, `autoload/himalaya/job/vim8.vim` (~110 lines total)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/job_spec.lua
describe('himalaya.job', function()
  local job = require('himalaya.job')

  it('exposes a run function', function()
    assert.is_function(job.run)
  end)

  it('runs a command and collects stdout', function()
    local done = false
    local result = nil

    job.run({ 'echo', 'hello world' }, {
      on_exit = function(out, err, code)
        result = out
        done = true
      end,
    })

    vim.wait(5000, function() return done end)
    assert.is_true(done)
    assert.are.equal('hello world\n', result)
    -- Note: echo adds a trailing newline
  end)

  it('collects stderr on failure', function()
    local done = false
    local err_result = nil
    local exit_code = nil

    job.run({ 'sh', '-c', 'echo bad >&2; exit 1' }, {
      on_exit = function(out, err, code)
        err_result = err
        exit_code = code
        done = true
      end,
    })

    vim.wait(5000, function() return done end)
    assert.is_true(done)
    assert.are.equal(1, exit_code)
    assert.is_truthy(err_result:match('bad'))
  end)

  it('can pipe stdin', function()
    local done = false
    local result = nil

    job.run({ 'cat' }, {
      stdin = 'piped content',
      on_exit = function(out, err, code)
        result = out
        done = true
      end,
    })

    vim.wait(5000, function() return done end)
    assert.is_true(done)
    assert.are.equal('piped content', result)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module `himalaya.job` not found

**Step 3: Write minimal implementation**

```lua
-- lua/himalaya/job.lua
local M = {}

--- Run a command asynchronously via vim.system().
--- @param cmd string[] Command and arguments
--- @param opts { stdin?: string, on_exit: fun(stdout: string, stderr: string, code: integer) }
--- @return vim.SystemObj
function M.run(cmd, opts)
  local sys_opts = {
    text = true,
    env = { RUST_LOG = 'off' },
  }

  if opts.stdin then
    sys_opts.stdin = opts.stdin
  end

  return vim.system(cmd, sys_opts, function(result)
    vim.schedule(function()
      opts.on_exit(result.stdout or '', result.stderr or '', result.code)
    end)
  end)
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All 4 tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/job.lua tests/himalaya/job_spec.lua
git commit -m "feat: migrate job module to Lua using vim.system()"
```

---

### Task 5: Migrate `request.lua`

**Files:**
- Create: `lua/himalaya/request.lua`
- Test: `tests/himalaya/request_spec.lua`
- Replaces: `autoload/himalaya/request.vim` (26 lines)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/request_spec.lua
describe('himalaya.request', function()
  local request
  local config
  local job

  before_each(function()
    package.loaded['himalaya.request'] = nil
    package.loaded['himalaya.config'] = nil
    package.loaded['himalaya.job'] = nil
    config = require('himalaya.config')
    config._reset()
    job = require('himalaya.job')
    request = require('himalaya.request')
  end)

  describe('build_cmd', function()
    it('builds a basic command with json output', function()
      local cmd = request._build_cmd('envelope list --folder %s', { 'INBOX' }, 'json')
      assert.are.equal(cmd[1], 'himalaya')
      assert.is_truthy(vim.tbl_contains(cmd, '--output'))
      assert.is_truthy(vim.tbl_contains(cmd, 'json'))
      -- should contain 'envelope', 'list', '--folder', 'INBOX'
      local joined = table.concat(cmd, ' ')
      assert.is_truthy(joined:match('envelope'))
      assert.is_truthy(joined:match('INBOX'))
    end)

    it('prepends --config when config_path is set', function()
      config.setup({ config_path = '/tmp/himalaya.toml' })
      local cmd = request._build_cmd('folder list', {}, 'json')
      local joined = table.concat(cmd, ' ')
      assert.is_truthy(joined:match('--config'))
      assert.is_truthy(joined:match('/tmp/himalaya.toml'))
    end)

    it('uses custom executable', function()
      config.setup({ executable = '/usr/local/bin/himalaya' })
      local cmd = request._build_cmd('folder list', {}, 'json')
      assert.are.equal('/usr/local/bin/himalaya', cmd[1])
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module `himalaya.request` not found

**Step 3: Write minimal implementation**

```lua
-- lua/himalaya/request.lua
local config = require('himalaya.config')
local job = require('himalaya.job')
local log = require('himalaya.log')

local M = {}

--- Build the command table for a himalaya CLI invocation.
--- @param cmd_fmt string printf-style format for the subcommand (e.g. 'envelope list --folder %s')
--- @param args string[] arguments to substitute into cmd_fmt
--- @param output_mode string 'json' or 'plain'
--- @return string[] command table suitable for vim.system()
function M._build_cmd(cmd_fmt, args, output_mode)
  local cfg = config.get()
  local subcmd = #args > 0 and string.format(cmd_fmt, unpack(args)) or cmd_fmt

  local parts = { cfg.executable, '--output', output_mode }

  if cfg.config_path then
    table.insert(parts, '--config')
    table.insert(parts, cfg.config_path)
  end

  for word in subcmd:gmatch('%S+') do
    table.insert(parts, word)
  end

  return parts
end

--- Run a JSON request against the himalaya CLI.
--- @param opts { cmd: string, args?: string[], msg: string, on_data: fun(data: any), stdin?: string }
function M.json(opts)
  local args = opts.args or {}
  log.info(string.format('%s...', opts.msg))
  local cmd = M._build_cmd(opts.cmd, args, 'json')

  job.run(cmd, {
    stdin = opts.stdin,
    on_exit = function(stdout, stderr, code)
      if code ~= 0 and stderr ~= '' then
        log.err(stderr)
        return
      end
      local ok, data = pcall(vim.json.decode, stdout)
      if not ok then
        log.err('Failed to parse JSON: ' .. stdout)
        return
      end
      opts.on_data(data)
      vim.cmd('redraw')
      log.info(string.format('%s [OK]', opts.msg))
    end,
  })
end

--- Run a plain text request against the himalaya CLI.
--- @param opts { cmd: string, args?: string[], msg: string, on_data: fun(data: string), stdin?: string }
function M.plain(opts)
  local args = opts.args or {}
  log.info(string.format('%s...', opts.msg))
  local cmd = M._build_cmd(opts.cmd, args, 'plain')

  job.run(cmd, {
    stdin = opts.stdin,
    on_exit = function(stdout, stderr, code)
      if code ~= 0 and stderr ~= '' then
        log.err(stderr)
        return
      end
      opts.on_data(stdout)
      vim.cmd('redraw')
      log.info(string.format('%s [OK]', opts.msg))
    end,
  })
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All 3 tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/request.lua tests/himalaya/request_spec.lua
git commit -m "feat: migrate request module to Lua"
```

---

### Task 6: Migrate `state/account.lua`

**Files:**
- Create: `lua/himalaya/state/account.lua`
- Test: `tests/himalaya/state/account_spec.lua`
- Replaces: `autoload/himalaya/domain/account.vim` (9 lines)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/state/account_spec.lua
describe('himalaya.state.account', function()
  local account

  before_each(function()
    package.loaded['himalaya.state.account'] = nil
    account = require('himalaya.state.account')
  end)

  it('defaults to empty string', function()
    assert.are.equal('', account.current())
  end)

  it('stores selected account', function()
    account.select('work')
    assert.are.equal('work', account.current())
  end)

  it('can switch accounts', function()
    account.select('work')
    account.select('personal')
    assert.are.equal('personal', account.current())
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

```lua
-- lua/himalaya/state/account.lua
local M = {}

local current_account = ''

function M.current()
  return current_account
end

function M.select(name)
  current_account = name
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All 3 tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/state/account.lua tests/himalaya/state/account_spec.lua
git commit -m "feat: migrate account state to Lua"
```

---

### Task 7: Migrate `state/folder.lua`

**Files:**
- Create: `lua/himalaya/state/folder.lua`
- Test: `tests/himalaya/state/folder_spec.lua`
- Replaces: folder/page state from `autoload/himalaya/domain/folder.vim` (the state parts only — s:page, s:folder, getters, page navigation)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/state/folder_spec.lua
describe('himalaya.state.folder', function()
  local folder

  before_each(function()
    package.loaded['himalaya.state.folder'] = nil
    folder = require('himalaya.state.folder')
  end)

  it('defaults to INBOX', function()
    assert.are.equal('INBOX', folder.current())
  end)

  it('defaults to page 1', function()
    assert.are.equal(1, folder.current_page())
  end)

  it('sets folder and resets page', function()
    folder.next_page()
    folder.set('Sent')
    assert.are.equal('Sent', folder.current())
    assert.are.equal(1, folder.current_page())
  end)

  it('increments page', function()
    folder.next_page()
    assert.are.equal(2, folder.current_page())
    folder.next_page()
    assert.are.equal(3, folder.current_page())
  end)

  it('decrements page but not below 1', function()
    folder.next_page()
    folder.next_page()
    assert.are.equal(3, folder.current_page())
    folder.previous_page()
    assert.are.equal(2, folder.current_page())
    folder.previous_page()
    assert.are.equal(1, folder.current_page())
    folder.previous_page()
    assert.are.equal(1, folder.current_page())
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

```lua
-- lua/himalaya/state/folder.lua
local M = {}

local current_folder = 'INBOX'
local current_page = 1

function M.current()
  return current_folder
end

function M.current_page()
  return current_page
end

function M.set(name)
  current_folder = name
  current_page = 1
end

function M.next_page()
  current_page = current_page + 1
end

function M.previous_page()
  current_page = math.max(1, current_page - 1)
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All 5 tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/state/folder.lua tests/himalaya/state/folder_spec.lua
git commit -m "feat: migrate folder state to Lua"
```

---

### Task 8: Migrate `domain/email/flags.lua`

**Files:**
- Create: `lua/himalaya/domain/email/flags.lua`
- Test: `tests/himalaya/domain/email/flags_spec.lua`
- Replaces: `autoload/himalaya/domain/email/flags.vim` (9 lines)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/domain/email/flags_spec.lua
describe('himalaya.domain.email.flags', function()
  local flags
  local config

  before_each(function()
    package.loaded['himalaya.domain.email.flags'] = nil
    package.loaded['himalaya.config'] = nil
    config = require('himalaya.config')
    config._reset()
    flags = require('himalaya.domain.email.flags')
  end)

  it('returns default flags', function()
    local result = flags.complete_list()
    assert.is_truthy(vim.tbl_contains(result, 'seen'))
    assert.is_truthy(vim.tbl_contains(result, 'answered'))
    assert.is_truthy(vim.tbl_contains(result, 'flagged'))
    assert.is_truthy(vim.tbl_contains(result, 'deleted'))
    assert.is_truthy(vim.tbl_contains(result, 'drafts'))
  end)

  it('includes custom flags from config', function()
    config.setup({ custom_flags = { 'important', 'urgent' } })
    local result = flags.complete_list()
    assert.is_truthy(vim.tbl_contains(result, 'important'))
    assert.is_truthy(vim.tbl_contains(result, 'urgent'))
    -- defaults still present
    assert.is_truthy(vim.tbl_contains(result, 'seen'))
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

```lua
-- lua/himalaya/domain/email/flags.lua
local config = require('himalaya.config')

local M = {}

local default_flags = { 'seen', 'answered', 'flagged', 'deleted', 'drafts' }

function M.complete_list()
  local cfg = config.get()
  local all = vim.list_extend(vim.deepcopy(default_flags), cfg.custom_flags)
  return all
end

--- Completion function for use with vim's command-line completion.
--- Returns newline-separated string of flag names.
function M.complete(arg_lead, cmd_line, cursor_pos)
  return table.concat(M.complete_list(), '\n')
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All 2 tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/domain/email/flags.lua tests/himalaya/domain/email/flags_spec.lua
git commit -m "feat: migrate email flags completion to Lua"
```

---

### Task 9: Migrate `domain/email/thread.lua`

**Files:**
- Create: `lua/himalaya/domain/email/thread.lua`
- Test: `tests/himalaya/domain/email/thread_spec.lua`
- Replaces: `autoload/himalaya/domain/email/thread.vim` (3 lines)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/domain/email/thread_spec.lua
describe('himalaya.domain.email.thread', function()
  local thread = require('himalaya.domain.email.thread')

  it('returns true for lines starting with >', function()
    assert.is_truthy(thread.fold('> quoted text'))
    assert.is_truthy(thread.fold('>> double quoted'))
  end)

  it('returns false for lines not starting with >', function()
    assert.is_falsy(thread.fold('normal text'))
    assert.is_falsy(thread.fold(''))
    assert.is_falsy(thread.fold('  > indented quote'))
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

```lua
-- lua/himalaya/domain/email/thread.lua
local M = {}

--- Fold expression for email threads.
--- Returns '1' for quoted lines (starting with '>'), '0' otherwise.
--- Designed for use with foldmethod=expr.
--- @param line string the line content
--- @return string fold level
function M.fold(line)
  if line:sub(1, 1) == '>' then
    return '1'
  end
  return '0'
end

--- Fold expression wrapper that takes a line number (for foldexpr).
--- @param lnum integer line number
--- @return string fold level
function M.foldexpr(lnum)
  return M.fold(vim.fn.getline(lnum))
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All 2 tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/domain/email/thread.lua tests/himalaya/domain/email/thread_spec.lua
git commit -m "feat: migrate thread folding to Lua"
```

---

### Task 10: Migrate `keybinds.lua`

**Files:**
- Create: `lua/himalaya/keybinds.lua`
- Test: `tests/himalaya/keybinds_spec.lua`
- Replaces: `autoload/himalaya/keybinds.vim` (11 lines)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/keybinds_spec.lua
describe('himalaya.keybinds', function()
  local keybinds = require('himalaya.keybinds')

  it('defines buffer-local keymaps', function()
    -- create a scratch buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)

    local called = false
    keybinds.define(buf, {
      { 'n', 'gx', function() called = true end, 'test-action' },
    })

    -- verify the keymap exists on this buffer
    local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
    local found = false
    for _, map in ipairs(maps) do
      if map.lhs == 'gx' then
        found = true
        break
      end
    end
    assert.is_true(found)

    -- cleanup
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

```lua
-- lua/himalaya/keybinds.lua
local M = {}

--- Define buffer-local keymaps with <Plug> support.
--- @param bufnr integer buffer number
--- @param bindings table[] list of { mode, key, callback, name }
function M.define(bufnr, bindings)
  for _, binding in ipairs(bindings) do
    local mode, key, callback, name = binding[1], binding[2], binding[3], binding[4]
    local plug = '<Plug>(himalaya-' .. name .. ')'

    -- Create the <Plug> mapping (global, silent)
    vim.keymap.set(mode, plug, callback, { silent = true, desc = 'Himalaya: ' .. name })

    -- Set the default buffer-local binding only if user hasn't overridden
    if vim.fn.hasmapto(plug, mode) == 0 then
      vim.keymap.set(mode, key, plug, { buffer = bufnr, nowait = true })
    end
  end
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All 1 test passes

**Step 5: Commit**

```bash
git add lua/himalaya/keybinds.lua tests/himalaya/keybinds_spec.lua
git commit -m "feat: migrate keybinds module to Lua"
```

---

### Task 11: Migrate `pickers/native.lua`

**Files:**
- Create: `lua/himalaya/pickers/native.lua`
- Test: `tests/himalaya/pickers/native_spec.lua`
- Replaces: `autoload/himalaya/domain/folder/pickers/native.vim` (13 lines)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/pickers/native_spec.lua
describe('himalaya.pickers.native', function()
  local native = require('himalaya.pickers.native')

  it('exposes a select function', function()
    assert.is_function(native.select)
  end)

  it('calls vim.ui.select with folder names', function()
    local select_called_with = {}
    local orig = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      select_called_with = { items = items, opts = opts }
      -- simulate selecting the second folder
      on_choice('Sent')
    end

    local selected = nil
    local folders = {
      { name = 'INBOX' },
      { name = 'Sent' },
      { name = 'Drafts' },
    }
    native.select(function(folder) selected = folder end, folders)

    vim.ui.select = orig

    assert.are.same({ 'INBOX', 'Sent', 'Drafts' }, select_called_with.items)
    assert.are.equal('Sent', selected)
  end)

  it('does nothing when selection is nil (cancelled)', function()
    local orig = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      on_choice(nil)
    end

    local selected = nil
    native.select(function(folder) selected = folder end, { { name = 'INBOX' } })

    vim.ui.select = orig
    assert.is_nil(selected)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

```lua
-- lua/himalaya/pickers/native.lua
local M = {}

--- Select a folder using vim.ui.select (integrates with dressing.nvim etc.)
--- @param callback fun(folder: string) called with selected folder name
--- @param folders table[] list of { name: string } folder objects
function M.select(callback, folders)
  local names = {}
  for _, f in ipairs(folders) do
    table.insert(names, f.name)
  end

  vim.ui.select(names, { prompt = 'Select folder: ' }, function(choice)
    if choice then
      callback(choice)
    end
  end)
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All 3 tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/pickers/native.lua tests/himalaya/pickers/native_spec.lua
git commit -m "feat: add native folder picker using vim.ui.select"
```

---

### Task 12: Migrate `pickers/fzf.lua`

**Files:**
- Create: `lua/himalaya/pickers/fzf.lua`
- Replaces: `autoload/himalaya/domain/folder/pickers/fzf.vim` (12 lines)

No test for this module — it requires fzf.vim to be installed. Tested manually.

**Step 1: Write implementation**

```lua
-- lua/himalaya/pickers/fzf.lua
local M = {}

--- Select a folder using fzf.vim
--- @param callback fun(folder: string) called with selected folder name
--- @param folders table[] list of { name: string } folder objects
function M.select(callback, folders)
  local names = {}
  for _, f in ipairs(folders) do
    table.insert(names, f.name)
  end

  vim.fn['fzf#run']({
    source = names,
    sink = callback,
    down = '25%',
  })
end

return M
```

**Step 2: Commit**

```bash
git add lua/himalaya/pickers/fzf.lua
git commit -m "feat: add fzf.vim folder picker in Lua"
```

---

### Task 13: Migrate `pickers/fzflua.lua`

**Files:**
- Modify: `lua/himalaya/folder/pickers/fzflua.lua` → move to `lua/himalaya/pickers/fzflua.lua`
- Replaces: `autoload/himalaya/domain/folder/pickers/fzflua.vim` (8 lines) and old `lua/himalaya/folder/pickers/fzflua.lua` (21 lines)

**Step 1: Create the new file at the new path**

```lua
-- lua/himalaya/pickers/fzflua.lua
local M = {}

--- Select a folder using fzf-lua
--- @param callback fun(folder: string) called with selected folder name
--- @param folders table[] list of { name: string } folder objects
function M.select(callback, folders)
  local fzf_lua = require('fzf-lua')

  local names = {}
  for _, f in ipairs(folders) do
    table.insert(names, f.name)
  end

  fzf_lua.fzf_exec(names, {
    prompt = 'Folders> ',
    actions = {
      ['default'] = function(selected)
        callback(selected[1])
      end,
    },
  })
end

return M
```

**Step 2: Commit**

```bash
git add lua/himalaya/pickers/fzflua.lua
git commit -m "feat: migrate fzf-lua picker to new module path"
```

---

### Task 14: Migrate `pickers/telescope.lua`

**Files:**
- Modify: `lua/himalaya/folder/pickers/telescope.lua` → move to `lua/himalaya/pickers/telescope.lua`
- Replaces: `autoload/himalaya/domain/folder/pickers/telescope.vim` (8 lines) and old `lua/himalaya/folder/pickers/telescope.lua` (63 lines)

**Step 1: Create the new file at the new path**

The telescope picker calls back into VimScript for preview via `vim.fn['himalaya#domain#email#list_with']`. During migration, it will call the Lua `domain.email.list_with` once that module exists. For now, leave the preview calling the VimScript function via `vim.fn`, and add a TODO to update after Task 18 (email domain migration).

```lua
-- lua/himalaya/pickers/telescope.lua
local config = require('himalaya.config')

local M = {}

--- Select a folder using telescope.nvim
--- @param callback fun(folder: string) called with selected folder name
--- @param folders table[] list of { name: string } folder objects
function M.select(callback, folders)
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local finders = require('telescope.finders')
  local pickers = require('telescope.pickers')
  local sorters = require('telescope.sorters')
  local previewers = require('telescope.previewers')

  local cfg = config.get()
  local previewer = nil

  local finder_opts = {
    results = folders,
    entry_maker = function(entry)
      return {
        value = entry.name,
        display = entry.name,
        ordinal = entry.name,
      }
    end,
  }

  if cfg.telescope_preview then
    previewer = previewers.display_content.new({})
    finder_opts.entry_maker = function(entry)
      return {
        value = entry.name,
        display = entry.name,
        ordinal = entry.name,
        preview_command = function(e, bufnr)
          -- TODO: call Lua domain.email.list_with after Task 18
          vim.api.nvim_buf_call(bufnr, function()
            local account_mod = require('himalaya.state.account')
            local account = account_mod.current()
            local ok, output = pcall(vim.fn['himalaya#domain#email#list_with'], account, e.value, 0, '')
            if not ok then
              vim.cmd('redraw')
              vim.bo.modifiable = true
              local errors = vim.split(tostring(output), '\n')
              errors[1] = 'Errors: ' .. errors[1]
              vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, errors)
            end
          end)
        end,
      }
    end
  end

  pickers.new({}, {
    results_title = 'Folders',
    finder = finders.new_table(finder_opts),
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        callback(selection.display)
      end)
      return true
    end,
    previewer = previewer,
  }):find()
end

return M
```

**Step 2: Commit**

```bash
git add lua/himalaya/pickers/telescope.lua
git commit -m "feat: migrate telescope picker to new module path"
```

---

### Task 15: Migrate `pickers/init.lua` (auto-detection + dispatch)

**Files:**
- Create: `lua/himalaya/pickers/init.lua`
- Replaces: picker detection logic in `autoload/himalaya/domain/folder.vim` (`s:open_picker` function)

**Step 1: Write implementation**

```lua
-- lua/himalaya/pickers/init.lua
local config = require('himalaya.config')

local M = {}

--- Detect which picker to use based on config or available plugins.
--- @return string picker name ('telescope', 'fzflua', 'fzf', 'native')
function M.detect()
  local cfg = config.get()
  if cfg.folder_picker then
    return cfg.folder_picker
  end

  if pcall(require, 'telescope') then
    return 'telescope'
  elseif pcall(require, 'fzf-lua') then
    return 'fzflua'
  elseif vim.fn.exists('*fzf#run') == 1 then
    return 'fzf'
  else
    return 'native'
  end
end

--- Open the folder picker.
--- @param callback fun(folder: string) called with selected folder name
--- @param folders table[] list of { name: string } folder objects
function M.select(callback, folders)
  local picker_name = M.detect()
  local picker = require('himalaya.pickers.' .. picker_name)
  picker.select(callback, folders)
end

return M
```

**Step 2: Commit**

```bash
git add lua/himalaya/pickers/init.lua
git commit -m "feat: add picker auto-detection and dispatch"
```

---

### Task 16: Migrate `domain/folder.lua`

**Files:**
- Create: `lua/himalaya/domain/folder.lua`
- Test: `tests/himalaya/domain/folder_spec.lua`
- Replaces: `autoload/himalaya/domain/folder.vim` (61 lines — the domain logic, not the state parts already migrated)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/domain/folder_spec.lua
describe('himalaya.domain.folder', function()
  local folder_domain
  local request
  local folder_state

  before_each(function()
    package.loaded['himalaya.domain.folder'] = nil
    package.loaded['himalaya.request'] = nil
    package.loaded['himalaya.state.folder'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.config'] = nil
    require('himalaya.config')._reset()
    folder_domain = require('himalaya.domain.folder')
    request = require('himalaya.request')
    folder_state = require('himalaya.state.folder')
  end)

  it('exposes open_picker, select, and set functions', function()
    assert.is_function(folder_domain.open_picker)
    assert.is_function(folder_domain.select)
    assert.is_function(folder_domain.set)
  end)

  it('set updates folder state', function()
    -- We can't fully test set() because it calls email.list(),
    -- but we can check the state change by stubbing the list call
    folder_state.set('Sent')
    assert.are.equal('Sent', folder_state.current())
    assert.are.equal(1, folder_state.current_page())
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module not found

**Step 3: Write minimal implementation**

```lua
-- lua/himalaya/domain/folder.lua
local request = require('himalaya.request')
local account_state = require('himalaya.state.account')
local folder_state = require('himalaya.state.folder')
local pickers = require('himalaya.pickers')

local M = {}

--- Open the folder picker, calling callback with the selected folder name.
--- @param callback fun(folder: string)
function M.open_picker(callback)
  local account = account_state.current()
  request.json({
    cmd = 'folder list --account %s',
    args = { account },
    msg = 'Listing folders',
    on_data = function(data)
      pickers.select(callback, data)
    end,
  })
end

--- Open the folder picker and switch to the selected folder.
function M.select()
  M.open_picker(M.set)
end

--- Set the current folder and refresh the envelope listing.
--- @param folder string
function M.set(folder)
  folder_state.set(folder)
  -- email.list() will be called here once domain/email.lua is migrated
  -- For now, bridge to VimScript:
  vim.fn['himalaya#domain#email#list']()
end

--- Select the next page of envelopes.
function M.select_next_page()
  folder_state.next_page()
  vim.fn['himalaya#domain#email#list']()
end

--- Select the previous page of envelopes.
function M.select_previous_page()
  folder_state.previous_page()
  vim.fn['himalaya#domain#email#list']()
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All 2 tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/domain/folder.lua tests/himalaya/domain/folder_spec.lua
git commit -m "feat: migrate folder domain to Lua"
```

---

### Task 17: Migrate `domain/email.lua`

**Files:**
- Create: `lua/himalaya/domain/email.lua`
- Test: `tests/himalaya/domain/email_spec.lua`
- Replaces: `autoload/himalaya/domain/email.vim` (404 lines)

This is the largest module. It contains: list, read, write, reply, reply_all, forward, delete, copy, move, flag_add, flag_remove, download_attachments, open_browser, save_draft, process_draft, complete_contact, set_list_envelopes_query, and several private helpers.

**Step 1: Write the failing test**

```lua
-- tests/himalaya/domain/email_spec.lua
describe('himalaya.domain.email', function()
  local email

  before_each(function()
    package.loaded['himalaya.domain.email'] = nil
    package.loaded['himalaya.config'] = nil
    package.loaded['himalaya.state.account'] = nil
    package.loaded['himalaya.state.folder'] = nil
    require('himalaya.config')._reset()
    email = require('himalaya.domain.email')
  end)

  it('exposes all public functions', function()
    assert.is_function(email.list)
    assert.is_function(email.list_with)
    assert.is_function(email.read)
    assert.is_function(email.write)
    assert.is_function(email.reply)
    assert.is_function(email.reply_all)
    assert.is_function(email.forward)
    assert.is_function(email.delete)
    assert.is_function(email.copy)
    assert.is_function(email.move)
    assert.is_function(email.select_folder_then_copy)
    assert.is_function(email.select_folder_then_move)
    assert.is_function(email.flag_add)
    assert.is_function(email.flag_remove)
    assert.is_function(email.download_attachments)
    assert.is_function(email.open_browser)
    assert.is_function(email.save_draft)
    assert.is_function(email.process_draft)
    assert.is_function(email.complete_contact)
    assert.is_function(email.set_list_envelopes_query)
  end)

  describe('get_email_id_from_line', function()
    it('extracts numeric id from a listing line', function()
      assert.are.equal('123', email._get_email_id_from_line('|123|*|Subject|Sender|2024-01-01|'))
    end)

    it('returns empty for header line', function()
      -- header line has text like "ID" not a number
      assert.are.equal('', email._get_email_id_from_line('|ID|FLAGS|SUBJECT|FROM|DATE|'))
    end)
  end)

  describe('bufwidth', function()
    it('returns a positive number', function()
      local width = email._bufwidth()
      assert.is_true(width > 0)
    end)
  end)

  describe('line_to_complete_item', function()
    it('formats email-only contact', function()
      local result = email._line_to_complete_item('user@example.com')
      assert.are.equal('<user@example.com>', result)
    end)

    it('formats contact with name', function()
      local result = email._line_to_complete_item('user@example.com\tJohn Doe')
      assert.are.equal('"John Doe"<user@example.com>', result)
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module not found

**Step 3: Write the implementation**

This is large. The implementation preserves all behavior from the VimScript version.

```lua
-- lua/himalaya/domain/email.lua
local request = require('himalaya.request')
local log = require('himalaya.log')
local config = require('himalaya.config')
local account_state = require('himalaya.state.account')
local folder_state = require('himalaya.state.folder')
local folder_domain = require('himalaya.domain.folder')

local M = {}

-- Module-level state
local current_id = ''
local draft = ''
local query = ''

--- Calculate usable buffer width (excluding line numbers, sign column, fold column).
function M._bufwidth()
  local width = vim.api.nvim_win_get_width(0)
  local numberwidth = math.max(vim.wo.numberwidth, #tostring(vim.fn.line('$')) + 1)
  local numwidth = (vim.wo.number or vim.wo.relativenumber) and numberwidth or 0
  local foldwidth = vim.wo.foldcolumn

  local signwidth = 0
  if vim.wo.signcolumn == 'yes' then
    signwidth = 2
  elseif vim.wo.signcolumn == 'auto' then
    local signs = vim.fn.execute(string.format('sign place buffer=%d', vim.fn.bufnr('')))
    local sign_lines = vim.split(signs, '\n')
    signwidth = #sign_lines > 2 and 2 or 0
  end

  return width - numwidth - foldwidth - signwidth
end

--- Extract email ID from a listing line.
--- @param line string
--- @return string id (empty string if no numeric match)
function M._get_email_id_from_line(line)
  return vim.fn.matchstr(line, '\\d\\+')
end

--- Get the email ID from the line under the cursor.
--- @return string id
function M._get_email_id_under_cursor()
  local line = vim.fn.getline('.')
  local id = M._get_email_id_from_line(line)
  if id == '' then
    error('email not found')
  end
  return id
end

--- Get email IDs from a range of lines (for visual selection).
--- @param from integer first line number
--- @param to integer last line number
--- @return string space-separated IDs
function M._get_email_id_under_cursors(from, to)
  local ids = {}
  for lnum = from, to do
    local id = M._get_email_id_from_line(vim.fn.getline(lnum))
    if id ~= '' then
      table.insert(ids, id)
    end
  end
  if #ids == 0 then
    error('emails not found')
  end
  return table.concat(ids, ' ')
end

--- Close all open buffers whose name matches a pattern.
--- @param name string pattern to match against buffer names
local function close_open_buffers(name)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      if bufname:find(name, 1, true) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end
end

--- Determine if current buffer is the envelope listing.
--- @return boolean
local function in_listing_buffer()
  return vim.api.nvim_buf_get_name(0):find('Himalaya envelopes', 1, true) ~= nil
end

--- Get the relevant email ID depending on which buffer we're in.
--- @return string
local function contextual_id()
  if in_listing_buffer() then
    return M._get_email_id_under_cursor()
  end
  return current_id
end

--- Format a contact completion line into "Name"<email> format.
--- @param line string tab-separated: email[\tname]
--- @return string
function M._line_to_complete_item(line)
  local fields = vim.split(line, '\t')
  local email_addr = fields[1]
  local name = ''
  if #fields > 1 then
    name = string.format('"%s"', fields[2])
  end
  return name .. string.format('<%s>', email_addr)
end

--- List envelopes for the current (or specified) account.
--- @param account? string optional account to switch to
function M.list(account)
  if account and account ~= '' then
    account_state.select(account)
  end
  local acct = account_state.current()
  local folder = folder_state.current()
  local page = folder_state.current_page()
  M.list_with(acct, folder, page, query)
end

--- List envelopes with explicit parameters.
function M.list_with(account, folder, page, q)
  request.plain({
    cmd = 'envelope list --folder %s --account %s --max-width %d --page-size %d --page %d %s',
    args = { folder, account, M._bufwidth(), vim.fn.winheight(0) - 1, page, q or '' },
    msg = string.format('Fetching %s envelopes', folder),
    on_data = function(data)
      local buftype = in_listing_buffer() and 'file' or 'edit'
      local query_display = (query == '' or query == nil) and 'all' or query
      vim.cmd(string.format('silent! %s Himalaya envelopes [%s] [%s] [page %d]', buftype, folder, query_display, page))
      vim.bo.modifiable = true
      vim.cmd('silent! %d')
      local lines = vim.split(data, '\n')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      -- remove trailing empty line if present
      local last = vim.api.nvim_buf_get_lines(0, -2, -1, false)
      if #last == 1 and last[1] == '' then
        vim.api.nvim_buf_set_lines(0, -2, -1, false, {})
      end
      vim.bo.filetype = 'himalaya-email-listing'
      vim.bo.modified = false
      vim.cmd('0')
    end,
  })
end

--- Read the email under the cursor.
function M.read()
  current_id = M._get_email_id_under_cursor()
  if current_id == '' or current_id == 'ID' then
    return
  end
  local account = account_state.current()
  local folder = folder_state.current()
  request.plain({
    cmd = 'message read --account %s --folder %s %s',
    args = { account, folder, current_id },
    msg = string.format('Fetching email %s', current_id),
    on_data = function(data)
      close_open_buffers('Himalaya read email')
      vim.cmd(string.format('silent! botright new Himalaya read email [%s]', current_id))
      vim.bo.modifiable = true
      vim.cmd('silent! %d')
      local content = data:gsub('\r', '')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(content, '\n'))
      -- remove trailing empty line
      local last = vim.api.nvim_buf_get_lines(0, -2, -1, false)
      if #last == 1 and last[1] == '' then
        vim.api.nvim_buf_set_lines(0, -2, -1, false, {})
      end
      vim.bo.filetype = 'himalaya-email-reading'
      vim.bo.modified = false
      vim.cmd('0')
    end,
  })
end

--- Download attachments for the current email.
function M.download_attachments()
  local account = account_state.current()
  local folder = folder_state.current()
  local id = contextual_id()
  request.plain({
    cmd = 'attachment download --account %s --folder %s %s',
    args = { account, folder, id },
    msg = 'Downloading attachments',
    on_data = function(data) log.info(data) end,
  })
end

--- Open the write buffer with a template.
--- @param template? string optional pre-filled template content
local function open_write_buffer(label, content)
  local bufname = string.format('Himalaya %s', label)
  if label == 'write' then
    vim.cmd(string.format('silent! botright new %s', bufname))
  end
  if vim.fn.winnr('$') == 1 then
    vim.cmd(string.format('silent! botright split %s', bufname))
  else
    vim.cmd(string.format('silent! edit %s', bufname))
  end
  vim.bo.modifiable = true
  vim.cmd('silent! %d')
  local text = content:gsub('\r', '')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(text, '\n'))
  -- remove trailing empty line
  local last = vim.api.nvim_buf_get_lines(0, -2, -1, false)
  if #last == 1 and last[1] == '' then
    vim.api.nvim_buf_set_lines(0, -2, -1, false, {})
  end
  vim.bo.filetype = 'himalaya-email-writing'
  vim.bo.modified = false
  vim.cmd('0')
end

--- Compose a new email.
--- @param template? string optional pre-filled template
function M.write(template)
  if template then
    open_write_buffer('edit', template)
  else
    local account = account_state.current()
    request.plain({
      cmd = 'template write --account %s',
      args = { account },
      msg = 'Fetching new template',
      on_data = function(data) open_write_buffer('write', data) end,
    })
  end
end

--- Reply to the current email.
function M.reply()
  local account = account_state.current()
  local folder = folder_state.current()
  local id = contextual_id()
  request.plain({
    cmd = 'template reply --account %s --folder %s %s',
    args = { account, folder, id },
    msg = 'Fetching reply template',
    on_data = function(data)
      open_write_buffer(string.format('reply [%s]', id), data)
    end,
  })
end

--- Reply-all to the current email.
function M.reply_all()
  local account = account_state.current()
  local folder = folder_state.current()
  local id = contextual_id()
  request.plain({
    cmd = 'template reply --account %s --folder %s --all %s',
    args = { account, folder, id },
    msg = 'Fetching reply all template',
    on_data = function(data)
      open_write_buffer(string.format('reply all [%s]', id), data)
    end,
  })
end

--- Forward the current email.
function M.forward()
  local account = account_state.current()
  local folder = folder_state.current()
  local id = contextual_id()
  request.plain({
    cmd = 'template forward --account %s --folder %s %s',
    args = { account, folder, id },
    msg = 'Fetching forward template',
    on_data = function(data)
      open_write_buffer(string.format('forward [%s]', id), data)
    end,
  })
end

--- Set the envelope list query and refresh.
function M.set_list_envelopes_query()
  query = vim.fn.input('Query: ')
  M.list()
end

--- Save draft content from the current buffer.
function M.save_draft()
  draft = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') .. '\n'
  vim.cmd('redraw')
  log.info('Save draft [OK]')
  vim.bo.modified = false
end

--- Process the draft: send, save as draft, quit, or cancel.
function M.process_draft()
  local account = account_state.current()
  local folder = folder_state.current()

  local ok, err = pcall(function()
    while true do
      local choice = vim.fn.input('(s)end, (d)raft, (q)uit or (c)ancel? ')
      choice = choice:lower():sub(1, 1)
      vim.cmd('redraw | echo')

      if choice == 's' then
        local tmpfile = vim.fn.tempname()
        vim.fn.writefile(vim.api.nvim_buf_get_lines(0, 0, -1, false), tmpfile)

        request.plain({
          cmd = 'template send --account %s',
          args = { account },
          stdin = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') .. '\n',
          msg = 'Sending email',
          on_data = function()
            vim.fn.delete(tmpfile)
          end,
        })

        request.plain({
          cmd = 'flag add --account %s --folder %s answered %s',
          args = { account, folder, current_id },
          msg = 'Adding answered flag',
          on_data = function() end,
        })
        return
      elseif choice == 'd' then
        request.plain({
          cmd = 'template save --account %s --folder drafts',
          args = { account },
          stdin = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') .. '\n',
          msg = 'Saving draft',
          on_data = function() end,
        })
        return
      elseif choice == 'q' then
        return
      elseif choice == 'c' then
        local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') .. '\n'
        M.write(content)
        error('Prompt:Interrupt')
      end
    end
  end)

  if not ok then
    if type(err) == 'string' and err:match(':Interrupt$') then
      -- user cancelled, do nothing
    else
      log.err(tostring(err))
    end
  end
end

--- Copy email to another folder (after folder picker selection).
--- @param target_folder string
function M.copy(target_folder)
  local id = contextual_id()
  local account = account_state.current()
  local folder = folder_state.current()
  request.plain({
    cmd = 'message copy --account %s --folder %s %s %s',
    args = { account, folder, target_folder, id },
    msg = 'Copying email',
    on_data = function()
      M.list_with(account, folder, folder_state.current_page(), query)
    end,
  })
end

--- Open folder picker then copy.
function M.select_folder_then_copy()
  folder_domain.open_picker(M.copy)
end

--- Move email to another folder (after folder picker selection).
--- @param target_folder string
function M.move(target_folder)
  local id = contextual_id()
  local cfg = config.get()

  if cfg.always_confirm then
    local choice = vim.fn.input(string.format('Are you sure you want to move the email %s? (y/N) ', id))
    vim.cmd('redraw | echo')
    if choice ~= 'y' then return end
  end

  local account = account_state.current()
  local folder = folder_state.current()
  request.plain({
    cmd = 'message move --account %s --folder %s %s %s',
    args = { account, folder, target_folder, id },
    msg = 'Moving email',
    on_data = function()
      M.list_with(account, folder, folder_state.current_page(), query)
    end,
  })
end

--- Open folder picker then move.
function M.select_folder_then_move()
  folder_domain.open_picker(M.move)
end

--- Delete email(s). Supports visual range.
--- @param first_line? integer
--- @param last_line? integer
function M.delete(first_line, last_line)
  local ids
  if in_listing_buffer() and first_line and last_line then
    ids = M._get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    ids = M._get_email_id_under_cursor()
  else
    ids = current_id
  end

  local cfg = config.get()
  if cfg.always_confirm then
    local choice = vim.fn.input(string.format('Are you sure you want to delete email(s) %s? (y/N) ', ids))
    vim.cmd('redraw | echo')
    if choice ~= 'y' then return end
  end

  local account = account_state.current()
  local folder = folder_state.current()
  request.plain({
    cmd = 'message delete --account %s --folder %s %s',
    args = { account, folder, ids },
    msg = 'Deleting email',
    on_data = function()
      M.list_with(account, folder, folder_state.current_page(), query)
    end,
  })
end

--- Add flag(s) to email(s). Supports visual range.
--- @param first_line? integer
--- @param last_line? integer
function M.flag_add(first_line, last_line)
  local ids
  if in_listing_buffer() and first_line and last_line then
    ids = M._get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    ids = M._get_email_id_under_cursor()
  else
    ids = current_id
  end

  local flags_mod = require('himalaya.domain.email.flags')
  local flags = vim.fn.input('Flag to add: ', '', 'custom,' .. table.concat(flags_mod.complete_list(), '\n'))
  vim.cmd('redraw | echo')

  local flag_list = vim.split(vim.trim(flags), '%s+')
  if #flag_list == 0 or (#flag_list == 1 and flag_list[1] == '') then
    return
  end

  local account = account_state.current()
  local folder = folder_state.current()
  request.plain({
    cmd = 'flag add --account %s --folder %s %s %s',
    args = { account, folder, flags, ids },
    msg = 'Adding flags: ' .. flags .. ' to email',
    on_data = function()
      M.list_with(account, folder, folder_state.current_page(), query)
    end,
  })
end

--- Remove flag(s) from email(s). Supports visual range.
--- @param first_line? integer
--- @param last_line? integer
function M.flag_remove(first_line, last_line)
  local ids
  if in_listing_buffer() and first_line and last_line then
    ids = M._get_email_id_under_cursors(first_line, last_line)
  elseif in_listing_buffer() then
    ids = M._get_email_id_under_cursor()
  else
    ids = current_id
  end

  local flags_mod = require('himalaya.domain.email.flags')
  local flags = vim.fn.input('Flag to remove: ', '', 'custom,' .. table.concat(flags_mod.complete_list(), '\n'))
  vim.cmd('redraw | echo')

  local flag_list = vim.split(vim.trim(flags), '%s+')
  if #flag_list == 0 or (#flag_list == 1 and flag_list[1] == '') then
    return
  end

  local account = account_state.current()
  local folder = folder_state.current()
  request.plain({
    cmd = 'flag remove --account %s --folder %s %s %s',
    args = { account, folder, flags, ids },
    msg = 'Removing flags: ' .. flags .. ' from email',
    on_data = function()
      M.list_with(account, folder, folder_state.current_page(), query)
    end,
  })
end

--- Open the current email in the browser.
function M.open_browser()
  local account = account_state.current()
  local folder = folder_state.current()
  request.plain({
    cmd = 'message export --account %s --folder %s --open %s',
    args = { account, folder, current_id },
    msg = 'Opening message in the browser',
    on_data = function(data) log.info(data) end,
  })
end

--- Contact completion function for omnifunc/completefunc.
--- @param findstart integer 1 = find start column, 0 = return matches
--- @param base string the text to complete
--- @return integer|table
function M.complete_contact(findstart, base)
  local cfg = config.get()
  if findstart == 1 then
    if not cfg.complete_contact_cmd then
      vim.api.nvim_err_writeln('You must set complete_contact_cmd in himalaya setup() to complete contacts')
      return -3
    end
    local line_to_cursor = vim.fn.getline('.'):sub(1, vim.fn.col('.') - 1)
    local start = vim.fn.match(line_to_cursor, '[^:,]*$')
    -- skip leading spaces
    while start <= #line_to_cursor and line_to_cursor:sub(start + 1, start + 1) == ' ' do
      start = start + 1
    end
    return start
  else
    local cmd_str = cfg.complete_contact_cmd:gsub('%%s', base)
    local output = vim.fn.system(cmd_str)
    local lines = vim.split(output, '\n')
    local items = {}
    for _, line in ipairs(lines) do
      if line ~= '' then
        table.insert(items, M._line_to_complete_item(line))
      end
    end
    return items
  end
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All tests pass

**Step 5: Update `domain/folder.lua` to call Lua email.list instead of vim.fn bridge**

In `lua/himalaya/domain/folder.lua`, replace the `vim.fn['himalaya#domain#email#list']()` calls with `require('himalaya.domain.email').list()`. Be careful of circular require — use lazy require:

```lua
-- In domain/folder.lua, replace vim.fn calls:
function M.set(folder)
  folder_state.set(folder)
  require('himalaya.domain.email').list()
end

function M.select_next_page()
  folder_state.next_page()
  require('himalaya.domain.email').list()
end

function M.select_previous_page()
  folder_state.previous_page()
  require('himalaya.domain.email').list()
end
```

**Step 6: Update `pickers/telescope.lua` preview to call Lua email.list_with**

In the telescope picker's `preview_command`, replace the `vim.fn` call with `require('himalaya.domain.email').list_with(...)`.

**Step 7: Commit**

```bash
git add lua/himalaya/domain/email.lua tests/himalaya/domain/email_spec.lua lua/himalaya/domain/folder.lua lua/himalaya/pickers/telescope.lua
git commit -m "feat: migrate email domain to Lua (largest module)"
```

---

### Task 18: Migrate `ui/listing.lua`

**Files:**
- Create: `lua/himalaya/ui/listing.lua`
- Test: `tests/himalaya/ui/listing_spec.lua`
- Replaces: `ftplugin/himalaya-email-listing.vim` (26 lines) + `syntax/himalaya-email-listing.vim` (27 lines)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/ui/listing_spec.lua
describe('himalaya.ui.listing', function()
  local listing

  before_each(function()
    package.loaded['himalaya.ui.listing'] = nil
    listing = require('himalaya.ui.listing')
  end)

  it('exposes a setup function', function()
    assert.is_function(listing.setup)
  end)

  it('defines highlight groups', function()
    listing.define_highlights()
    -- Check that highlight groups exist (no error thrown)
    local hl = vim.api.nvim_get_hl(0, { name = 'HimalayaHead' })
    assert.is_truthy(hl.bold)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module not found

**Step 3: Write implementation**

```lua
-- lua/himalaya/ui/listing.lua
local keybinds = require('himalaya.keybinds')
local email = require('himalaya.domain.email')
local folder_domain = require('himalaya.domain.folder')

local M = {}

function M.define_highlights()
  vim.api.nvim_set_hl(0, 'HimalayaSeparator', { link = 'VertSplit', default = true })
  vim.api.nvim_set_hl(0, 'HimalayaId', { link = 'Identifier', default = true })
  vim.api.nvim_set_hl(0, 'HimalayaFlags', { link = 'Special', default = true })
  vim.api.nvim_set_hl(0, 'HimalayaSubject', { link = 'String', default = true })
  vim.api.nvim_set_hl(0, 'HimalayaSender', { link = 'Structure', default = true })
  vim.api.nvim_set_hl(0, 'HimalayaDate', { link = 'Constant', default = true })
  vim.api.nvim_set_hl(0, 'HimalayaHead', { bold = true, default = true })
end

--- Apply syntax highlighting to the listing buffer using vim syntax commands.
--- @param bufnr integer
function M.apply_syntax(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd([[
      syntax match HimalayaSeparator /|/
      syntax match HimalayaId        /^|.\{-}/                          contains=HimalayaSeparator
      syntax match HimalayaFlags     /^|.\{-}|.\{-}/                    contains=HimalayaId,HimalayaSeparator
      syntax match HimalayaSubject   /^|.\{-}|.\{-}|.\{-}/              contains=HimalayaId,HimalayaFlags,HimalayaSeparator
      syntax match HimalayaSender    /^|.\{-}|.\{-}|.\{-}|.\{-}/        contains=HimalayaId,HimalayaFlags,HimalayaSubject,HimalayaSeparator
      syntax match HimalayaDate      /^|.\{-}|.\{-}|.\{-}|.\{-}|.\{-}|/ contains=HimalayaId,HimalayaFlags,HimalayaSubject,HimalayaSender,HimalayaSeparator
      syntax match HimalayaHead      /.*\%1l/                           contains=HimalayaSeparator
      syntax match HimalayaUnseen    /^|.\{-}|.*\*.*$/                  contains=HimalayaSeparator
    ]])
  end)
end

--- Set up the listing buffer: options, keymaps, highlights.
--- @param bufnr integer
function M.setup(bufnr)
  vim.bo[bufnr].buftype = 'nofile'
  vim.wo.cursorline = true
  vim.bo[bufnr].modifiable = false
  vim.wo.wrap = false

  M.define_highlights()
  M.apply_syntax(bufnr)

  keybinds.define(bufnr, {
    { 'n', 'gm',   folder_domain.select,               'folder-select' },
    { 'n', 'gp',   folder_domain.select_previous_page,  'folder-select-previous-page' },
    { 'n', 'gn',   folder_domain.select_next_page,      'folder-select-next-page' },
    { 'n', '<cr>', email.read,                           'email-read' },
    { 'n', 'gw',   email.write,                          'email-write' },
    { 'n', 'gr',   email.reply,                          'email-reply' },
    { 'n', 'gR',   email.reply_all,                      'email-reply-all' },
    { 'n', 'gf',   email.forward,                        'email-forward' },
    { 'n', 'ga',   email.download_attachments,            'email-download-attachments' },
    { 'n', 'gC',   email.select_folder_then_copy,        'email-select-folder-then-copy' },
    { 'n', 'gM',   email.select_folder_then_move,        'email-select-folder-then-move' },
    { 'n', 'gD',   function() email.delete(vim.fn.line('.'), vim.fn.line('.')) end, 'email-delete' },
    { 'v', 'gD',   function() email.delete(vim.fn.line("'<"), vim.fn.line("'>")) end, 'email-delete-visual' },
    { 'n', 'gFa',  function() email.flag_add(vim.fn.line('.'), vim.fn.line('.')) end, 'email-flag-add' },
    { 'v', 'gFa',  function() email.flag_add(vim.fn.line("'<"), vim.fn.line("'>")) end, 'email-flag-add-visual' },
    { 'n', 'gFr',  function() email.flag_remove(vim.fn.line('.'), vim.fn.line('.')) end, 'email-flag-remove' },
    { 'v', 'gFr',  function() email.flag_remove(vim.fn.line("'<"), vim.fn.line("'>")) end, 'email-flag-remove-visual' },
    { 'n', 'g/',   email.set_list_envelopes_query,       'email-set-list-envelopes-query' },
  })
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/ui/listing.lua tests/himalaya/ui/listing_spec.lua
git commit -m "feat: migrate listing UI to Lua with highlights and keymaps"
```

---

### Task 19: Migrate `ui/reading.lua`

**Files:**
- Create: `lua/himalaya/ui/reading.lua`
- Test: `tests/himalaya/ui/reading_spec.lua`
- Replaces: `ftplugin/himalaya-email-reading.vim` (19 lines) + `syntax/himalaya-email-reading.vim` (7 lines)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/ui/reading_spec.lua
describe('himalaya.ui.reading', function()
  local reading

  before_each(function()
    package.loaded['himalaya.ui.reading'] = nil
    reading = require('himalaya.ui.reading')
  end)

  it('exposes a setup function', function()
    assert.is_function(reading.setup)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module not found

**Step 3: Write implementation**

```lua
-- lua/himalaya/ui/reading.lua
local keybinds = require('himalaya.keybinds')
local email = require('himalaya.domain.email')
local thread = require('himalaya.domain.email.thread')

local M = {}

--- Set up the reading buffer: options, keymaps, fold settings.
--- @param bufnr integer
function M.setup(bufnr)
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].filetype = 'mail'
  vim.wo.foldmethod = 'expr'
  vim.wo.foldexpr = "v:lua.require'himalaya.domain.email.thread'.foldexpr(v:lnum)"
  vim.bo[bufnr].modifiable = false

  keybinds.define(bufnr, {
    { 'n', 'gw', email.write,                    'email-write' },
    { 'n', 'gr', email.reply,                    'email-reply' },
    { 'n', 'gR', email.reply_all,                'email-reply-all' },
    { 'n', 'gf', email.forward,                  'email-forward' },
    { 'n', 'ga', email.download_attachments,      'email-download-attachments' },
    { 'n', 'gC', email.select_folder_then_copy,  'email-select-folder-then-copy' },
    { 'n', 'gM', email.select_folder_then_move,  'email-select-folder-then-move' },
    { 'n', 'gD', email.delete,                   'email-delete' },
    { 'n', 'go', email.open_browser,             'email-open-browser' },
  })
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/ui/reading.lua tests/himalaya/ui/reading_spec.lua
git commit -m "feat: migrate reading UI to Lua"
```

---

### Task 20: Migrate `ui/writing.lua`

**Files:**
- Create: `lua/himalaya/ui/writing.lua`
- Test: `tests/himalaya/ui/writing_spec.lua`
- Replaces: `ftplugin/himalaya-email-writing.vim` (19 lines) + `syntax/himalaya-email-writing.vim` (7 lines)

**Step 1: Write the failing test**

```lua
-- tests/himalaya/ui/writing_spec.lua
describe('himalaya.ui.writing', function()
  local writing

  before_each(function()
    package.loaded['himalaya.ui.writing'] = nil
    writing = require('himalaya.ui.writing')
  end)

  it('exposes a setup function', function()
    assert.is_function(writing.setup)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — module not found

**Step 3: Write implementation**

```lua
-- lua/himalaya/ui/writing.lua
local keybinds = require('himalaya.keybinds')
local email = require('himalaya.domain.email')
local config = require('himalaya.config')
local thread = require('himalaya.domain.email.thread')

local M = {}

--- Set up the writing buffer: options, keymaps, autocmds.
--- @param bufnr integer
function M.setup(bufnr)
  vim.bo[bufnr].filetype = 'mail'
  vim.wo.foldmethod = 'expr'
  vim.wo.foldexpr = "v:lua.require'himalaya.domain.email.thread'.foldexpr(v:lnum)"
  vim.wo.startofline = true

  local cfg = config.get()
  if cfg.complete_contact_cmd then
    vim.bo[bufnr].completefunc = "v:lua.require'himalaya.domain.email'.complete_contact"
  end

  -- BufWriteCmd: intercept :w to save draft
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = bufnr,
    callback = function()
      email.save_draft()
    end,
  })

  -- BufLeave: process draft when leaving buffer
  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = bufnr,
    callback = function()
      email.process_draft()
    end,
  })
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lua/himalaya/ui/writing.lua tests/himalaya/ui/writing_spec.lua
git commit -m "feat: migrate writing UI to Lua"
```

---

### Task 21: Migrate entry point — `init.lua` + `plugin/himalaya.lua`

**Files:**
- Create: `lua/himalaya/init.lua`
- Create: `plugin/himalaya.lua`
- Replaces: `plugin/himalaya.vim` (39 lines)

**Step 1: Write `lua/himalaya/init.lua`**

```lua
-- lua/himalaya/init.lua
local config = require('himalaya.config')
local log = require('himalaya.log')

local M = {}

--- User-facing setup function.
--- @param opts? table user config overrides
function M.setup(opts)
  config.setup(opts)

  local cfg = config.get()
  if vim.fn.executable(cfg.executable) == 0 then
    log.err('Himalaya CLI not found, see https://pimalaya.org/himalaya/cli/latest/installation/')
    return
  end
end

--- Register all Ex commands. Called from plugin/himalaya.lua.
function M._register_commands()
  local email = require('himalaya.domain.email')
  local folder = require('himalaya.domain.folder')

  vim.api.nvim_create_user_command('Himalaya', function(opts)
    email.list(opts.fargs[1])
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('HimalayaCopy', function()
    email.select_folder_then_copy()
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('HimalayaMove', function()
    email.select_folder_then_move()
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('HimalayaDelete', function(opts)
    email.delete(opts.line1, opts.line2)
  end, { nargs = '*', range = true })

  vim.api.nvim_create_user_command('HimalayaWrite', function()
    email.write()
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('HimalayaReply', function()
    email.reply()
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('HimalayaReplyAll', function()
    email.reply_all()
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('HimalayaForward', function()
    email.forward()
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('HimalayaFolders', function()
    folder.select()
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('HimalayaFolder', function(opts)
    folder.set(opts.fargs[1])
  end, { nargs = 1 })

  vim.api.nvim_create_user_command('HimalayaNextPage', function()
    folder.select_next_page()
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('HimalayaPreviousPage', function()
    folder.select_previous_page()
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('HimalayaAttachments', function()
    email.download_attachments()
  end, { nargs = '*' })

  vim.api.nvim_create_user_command('HimalayaFlagAdd', function(opts)
    email.flag_add(opts.line1, opts.line2)
  end, { nargs = '*', range = true })

  vim.api.nvim_create_user_command('HimalayaFlagRemove', function(opts)
    email.flag_remove(opts.line1, opts.line2)
  end, { nargs = '*', range = true })
end

--- Register filetype autocommands so the UI setup modules run when
--- filetype is set (replacing ftplugin/*.vim and syntax/*.vim files).
function M._register_filetypes()
  local group = vim.api.nvim_create_augroup('himalaya', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'himalaya-email-listing',
    callback = function(ev)
      require('himalaya.ui.listing').setup(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'himalaya-email-reading',
    callback = function(ev)
      require('himalaya.ui.reading').setup(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'himalaya-email-writing',
    callback = function(ev)
      require('himalaya.ui.writing').setup(ev.buf)
    end,
  })
end

return M
```

**Step 2: Write `plugin/himalaya.lua`**

```lua
-- plugin/himalaya.lua
if vim.g.himalaya_loaded then
  return
end

local himalaya = require('himalaya')
himalaya._register_commands()
himalaya._register_filetypes()

vim.g.himalaya_loaded = true
```

**Step 3: Commit**

```bash
git add lua/himalaya/init.lua plugin/himalaya.lua
git commit -m "feat: add Lua entry point and command registration"
```

---

### Task 22: Delete all VimScript files

**Files:**
- Delete: `plugin/himalaya.vim`
- Delete: `autoload/himalaya/log.vim`
- Delete: `autoload/himalaya/job.vim`
- Delete: `autoload/himalaya/job/neovim.vim`
- Delete: `autoload/himalaya/job/vim8.vim`
- Delete: `autoload/himalaya/request.vim`
- Delete: `autoload/himalaya/keybinds.vim`
- Delete: `autoload/himalaya/domain/account.vim`
- Delete: `autoload/himalaya/domain/folder.vim`
- Delete: `autoload/himalaya/domain/email.vim`
- Delete: `autoload/himalaya/domain/email/flags.vim`
- Delete: `autoload/himalaya/domain/email/thread.vim`
- Delete: `autoload/himalaya/domain/folder/pickers/native.vim`
- Delete: `autoload/himalaya/domain/folder/pickers/fzf.vim`
- Delete: `autoload/himalaya/domain/folder/pickers/fzflua.vim`
- Delete: `autoload/himalaya/domain/folder/pickers/telescope.vim`
- Delete: `ftplugin/himalaya-email-listing.vim`
- Delete: `ftplugin/himalaya-email-reading.vim`
- Delete: `ftplugin/himalaya-email-writing.vim`
- Delete: `syntax/himalaya-email-listing.vim`
- Delete: `syntax/himalaya-email-reading.vim`
- Delete: `syntax/himalaya-email-writing.vim`
- Delete: `lua/himalaya/folder/pickers/fzflua.lua` (old path)
- Delete: `lua/himalaya/folder/pickers/telescope.lua` (old path)
- Delete: `tests/himalaya/smoke_spec.lua` (no longer needed)

**Step 1: Remove all VimScript files and old Lua paths**

```bash
rm plugin/himalaya.vim
rm -rf autoload/
rm -rf ftplugin/
rm -rf syntax/
rm -rf lua/himalaya/folder/
rm tests/himalaya/smoke_spec.lua
```

**Step 2: Verify tests still pass**

Run: `make test`
Expected: All tests pass (no VimScript dependencies remain)

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: remove all VimScript files, migration complete"
```

---

### Task 23: Run full test suite and fix any issues

**Step 1: Run all tests**

Run: `make test`
Expected: All tests pass

**Step 2: If any tests fail, fix them and re-run**

Fix any issues discovered, re-run until green.

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve post-migration test failures"
```

---

### Task 24: Add `doc/himalaya.txt` vimdoc help file

**Files:**
- Create: `doc/himalaya.txt`

**Step 1: Write the vimdoc file**

```vimdoc
*himalaya.txt*  Neovim client for the Himalaya CLI email client

Author: Clstrn <clement.douin@posteo.net>
License: MIT

CONTENTS                                            *himalaya-contents*

  1. Introduction .................... |himalaya-introduction|
  2. Requirements .................... |himalaya-requirements|
  3. Setup ........................... |himalaya-setup|
  4. Commands ........................ |himalaya-commands|
  5. Keybindings .................... |himalaya-keybindings|
  6. Configuration ................... |himalaya-configuration|
  7. Folder Pickers .................. |himalaya-folder-pickers|

==============================================================================
1. INTRODUCTION                                     *himalaya-introduction*

himalaya.nvim is a Neovim front-end for the Himalaya CLI email client.
It provides an interactive email interface inside Neovim by communicating
asynchronously with the `himalaya` binary.

==============================================================================
2. REQUIREMENTS                                     *himalaya-requirements*

- Neovim >= 0.10
- himalaya CLI binary on PATH
  https://pimalaya.org/himalaya/cli/latest/installation/

==============================================================================
3. SETUP                                            *himalaya-setup*

                                                    *himalaya.setup()*
Call `require('himalaya').setup()` in your Neovim config: >lua

  require('himalaya').setup({
    executable = 'himalaya',
    config_path = nil,
    folder_picker = nil,
    telescope_preview = false,
    complete_contact_cmd = nil,
    custom_flags = {},
    always_confirm = true,
  })
<

==============================================================================
4. COMMANDS                                         *himalaya-commands*

:Himalaya [account]           List envelopes (optional account switch)
:HimalayaCopy                 Copy email to another folder
:HimalayaMove                 Move email to another folder
:HimalayaDelete               Delete email(s) (supports visual range)
:HimalayaWrite                Compose new email
:HimalayaReply                Reply to email
:HimalayaReplyAll             Reply-all
:HimalayaForward              Forward email
:HimalayaFolders              Open folder picker
:HimalayaFolder {name}        Switch to named folder
:HimalayaNextPage             Next page of envelopes
:HimalayaPreviousPage         Previous page
:HimalayaAttachments          Download attachments
:HimalayaFlagAdd              Add flag(s) to email(s) (supports visual range)
:HimalayaFlagRemove           Remove flag(s) (supports visual range)

==============================================================================
5. KEYBINDINGS                                      *himalaya-keybindings*

Envelope listing buffer:~

  gm        Select folder
  gp        Previous page
  gn        Next page
  <CR>      Read email
  gw        Compose new email
  gr        Reply
  gR        Reply all
  gf        Forward
  ga        Download attachments
  gC        Copy to folder
  gM        Move to folder
  gD        Delete (normal and visual mode)
  gFa       Add flag (normal and visual mode)
  gFr       Remove flag (normal and visual mode)
  g/        Set search query

Email reading buffer:~

  gw        Compose new email
  gr        Reply
  gR        Reply all
  gf        Forward
  ga        Download attachments
  gC        Copy to folder
  gM        Move to folder
  gD        Delete
  go        Open in browser

All keybindings use |<Plug>| mappings and can be overridden.

==============================================================================
6. CONFIGURATION                                    *himalaya-configuration*

                                                    *himalaya-executable*
executable ~
  Type: string, Default: `'himalaya'`
  Path to the himalaya binary.

                                                    *himalaya-config-path*
config_path ~
  Type: string|nil, Default: `nil`
  Custom TOML config file path. Adds `--config` flag to CLI calls.

                                                    *himalaya-folder-picker*
folder_picker ~
  Type: string|nil, Default: `nil` (auto-detect)
  Force a specific picker: `'native'`, `'fzf'`, `'fzflua'`, or `'telescope'`.

                                                    *himalaya-telescope-preview*
telescope_preview ~
  Type: boolean, Default: `false`
  Enable live folder preview in telescope picker.

                                                    *himalaya-complete-contact-cmd*
complete_contact_cmd ~
  Type: string|nil, Default: `nil`
  Shell command for contact completion. `%s` is replaced with the query.

                                                    *himalaya-custom-flags*
custom_flags ~
  Type: string[], Default: `{}`
  Additional flag names for tab-completion in flag commands.

                                                    *himalaya-always-confirm*
always_confirm ~
  Type: boolean, Default: `true`
  Prompt before move/delete operations.

==============================================================================
7. FOLDER PICKERS                                   *himalaya-folder-pickers*

The plugin auto-detects available picker plugins in this order:
  1. telescope.nvim
  2. fzf-lua
  3. fzf.vim
  4. native (vim.ui.select)

Override with the `folder_picker` config option.

The native picker uses |vim.ui.select()| which integrates with UI plugins
like dressing.nvim.

==============================================================================
vim:tw=78:ts=8:ft=help:norl:
```

**Step 2: Generate helptags**

Run: `nvim --headless -c "helptags doc/" -c "q"`

**Step 3: Commit**

```bash
git add doc/
git commit -m "docs: add vimdoc help file"
```

---

### Task 25: Update README.md

**Step 1: Update the README to reflect Lua migration**

Key changes:
- Update requirements to state Neovim 0.10+
- Replace VimScript config examples with Lua `setup()` call
- Remove Vim 8 references
- Note the `setup()` is required

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README for Lua migration"
```

---

### Task 26: Final verification

**Step 1: Run full test suite**

Run: `make test`
Expected: All tests pass

**Step 2: Verify no VimScript files remain**

Run: `find . -name '*.vim' -not -path './.git/*'`
Expected: No output (zero .vim files outside .git)

**Step 3: Manual smoke test**

Load the plugin in Neovim with a himalaya config and verify:
- `:Himalaya` lists envelopes
- Reading, replying, composing work
- Folder picker works
- `:help himalaya` opens the help file
