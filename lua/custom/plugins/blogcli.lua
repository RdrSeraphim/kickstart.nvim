-- Integration for `blogcli`, the Go CLI/TUI in rdrseraphim/blog
-- (cmd/blogcli) for authoring posts: metadata scaffolding, mnemonic
-- footnote renumbering, and terminal/HTML preview.
--
-- Requires the `blogcli` binary on your PATH (from the blog repo:
-- `go build -o ~/go/bin/blogcli ./cmd/blogcli`, or `go install
-- ./cmd/blogcli` with GOBIN on PATH). Override the command with
-- vim.g.blogcli_cmd if you keep it somewhere else.
--
-- All keymaps below live under <leader>p and are only set on markdown
-- buffers that sit inside a Hugo site (found by walking up for a
-- hugo.toml), so they won't shadow anything in unrelated markdown files.

local function blogcli_cmd()
  return vim.g.blogcli_cmd or 'blogcli'
end

---Find the Hugo site root containing `path`, or nil if there isn't one.
local function find_hugo_root(path)
  local found = vim.fs.find('hugo.toml', { path = vim.fs.dirname(path), upward = true })[1]
  return found and vim.fs.dirname(found) or nil
end

---Run `cmd` in a floating terminal. By default the window closes itself
---when the process exits (right for long-running preview UIs that have
---their own quit key); pass opts.close_on_exit = false to instead leave
---the window open on exit, showing final output, until the user hits `q`
---(right for one-shot commands like `new` whose last lines matter).
local function float_term(cmd, opts)
  opts = opts or {}
  local close_on_exit = opts.close_on_exit
  if close_on_exit == nil then
    close_on_exit = true
  end

  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.85)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = opts.title and (' ' .. opts.title .. ' ') or nil,
    title_pos = opts.title and 'center' or nil,
  })

  vim.fn.jobstart(cmd, {
    term = true,
    cwd = opts.cwd,
    on_exit = function()
      if close_on_exit and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if opts.on_exit then
        opts.on_exit()
      end
    end,
  })

  vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { buffer = buf, desc = 'Exit terminal mode' })
  vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf, desc = 'Close preview' })
  vim.cmd.startinsert()
end

local function require_blogcli()
  if vim.fn.executable(blogcli_cmd()) == 0 then
    vim.notify(
      "blogcli: '" .. blogcli_cmd() .. "' not found on PATH. Build it from the blog repo with "
        .. '`go build -o ~/go/bin/blogcli ./cmd/blogcli`, or set vim.g.blogcli_cmd.',
      vim.log.levels.ERROR
    )
    return false
  end
  return true
end

local function preview_terminal()
  if not require_blogcli() then
    return
  end
  local file = vim.api.nvim_buf_get_name(0)
  float_term({ blogcli_cmd(), 'preview', file }, { title = 'blogcli preview' })
end

local function preview_html()
  if not require_blogcli() then
    return
  end
  local file = vim.api.nvim_buf_get_name(0)
  float_term({ blogcli_cmd(), 'preview', '--html', file }, { title = 'blogcli preview --html' })
end

local function new_post()
  if not require_blogcli() then
    return
  end
  local root = find_hugo_root(vim.api.nvim_buf_get_name(0)) or vim.fn.getcwd()
  float_term({ blogcli_cmd(), 'new' }, {
    title = 'blogcli new',
    cwd = root,
    close_on_exit = false,
  })
end

local function fix_footnotes()
  if not require_blogcli() then
    return
  end
  if vim.bo.modified then
    vim.notify('blogcli: save the buffer before renumbering footnotes', vim.log.levels.WARN)
    return
  end

  local file = vim.api.nvim_buf_get_name(0)
  local result = vim.system({ blogcli_cmd(), 'footnotes', '-w', file }, { text = true }):wait()

  if result.code ~= 0 then
    vim.notify('blogcli footnotes: ' .. vim.trim(result.stderr), vim.log.levels.ERROR)
    return
  end

  vim.cmd.edit()
  local msg = vim.trim(result.stderr)
  vim.notify(msg ~= '' and msg or 'blogcli: footnotes renumbered', vim.log.levels.INFO)
end

local augroup = vim.api.nvim_create_augroup('blogcli', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
  group = augroup,
  pattern = 'markdown',
  callback = function(ev)
    if not find_hugo_root(vim.api.nvim_buf_get_name(ev.buf)) then
      return
    end

    local map = function(lhs, fn, desc)
      vim.keymap.set('n', lhs, fn, { buffer = ev.buf, desc = desc })
    end

    map('<leader>pp', preview_terminal, 'Blog: [P]review post in terminal')
    map('<leader>ph', preview_html, 'Blog: [P]review post as [H]TML')
    map('<leader>pf', fix_footnotes, 'Blog: [P]ost [F]ix/renumber footnotes')
    map('<leader>pn', new_post, 'Blog: [P]ost [N]ew')
  end,
})
