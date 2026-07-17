-- Integration for `blogcli`, the authoring helpers in rdrseraphim/blog
-- (cmd/blogcli) that Hugo and editor plugins don't already cover:
--
--   footnotes    turns a footnote written with its text right in the
--                marker, e.g. [^A cat sound.], into the blog's numbered
--                [^1]/[^2] endnote style
--   frontmatter  normalizes a content file's front matter (to canonical
--                TOML, filling in lastmod/slug, fixing field order) to
--                match the rest of the site
--   lint         reports front matter problems (missing summary, cover
--                without cover-alt, etc.)
--
-- On saving a post or page it runs the fixers automatically (format on
-- save) and then lints; the same actions are also on keymaps. Metadata
-- scaffolding and preview are intentionally *not* handled here: use
-- `hugo new ...` (archetypes/ already matches the site's front matter)
-- and `hugo server` / render-markdown.nvim's `:RenderMarkdown`.
--
-- Requires the `blogcli` binary on your PATH (from the blog repo:
-- `go build -o ~/go/bin/blogcli ./cmd/blogcli`, or `go install
-- ./cmd/blogcli` with GOBIN on PATH). Override the command with
-- vim.g.blogcli_cmd if you keep it somewhere else.
--
-- Config (all optional):
--   vim.g.blogcli_cmd             path to the binary (default 'blogcli')
--   vim.g.blogcli_format_on_save  false to disable the on-save fixers
--   vim.g.blogcli_lint_on_save    false | 'errors' (default) | 'all'
--                                 'errors' surfaces only lint errors on
--                                 save; 'all' also shows warnings.

local function blogcli()
  return vim.g.blogcli_cmd or 'blogcli'
end

local function have_blogcli()
  return vim.fn.executable(blogcli()) == 1
end

local function missing_blogcli_notice()
  vim.notify(
    "blogcli: '" .. blogcli() .. "' not found on PATH. Build it from the blog repo with "
      .. '`go build -o ~/go/bin/blogcli ./cmd/blogcli`, or set vim.g.blogcli_cmd.',
    vim.log.levels.ERROR
  )
end

---Find the Hugo site root containing `path`, or nil if there isn't one.
local function find_hugo_root(path)
  local found = vim.fs.find('hugo.toml', { path = vim.fs.dirname(path), upward = true })[1]
  return found and vim.fs.dirname(found) or nil
end

---True if `path` is a post or page inside a Hugo site (the content the
---blogcli fixers have an opinion about).
local function is_blog_content(path)
  if path == '' or not find_hugo_root(path) then
    return false
  end
  local p = path:gsub('\\', '/')
  return p:match '/content/posts/' ~= nil or p:match '/content/pages/' ~= nil
end

---Run `blogcli <sub> -w <file>`. Returns ok, stderr-message.
local function apply_fix(sub, file)
  local r = vim.system({ blogcli(), sub, '-w', file }, { text = true }):wait()
  return r.code == 0, vim.trim(r.stderr)
end

---Splice the on-disk file back into the buffer, preserving undo history
---and cursor and leaving the buffer marked unmodified. No-op if the file
---and buffer already match.
local function sync_buffer_from_disk(buf, file)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local disk = vim.fn.readfile(file)
  local cur = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if vim.deep_equal(disk, cur) then
    return
  end
  local view = vim.fn.winsaveview()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, disk)
  pcall(vim.fn.winrestview, view)
  vim.bo[buf].modified = false
end

---Run the fixers (frontmatter, then footnotes) on the file backing `buf`.
local function format_buffer(buf)
  local file = vim.api.nvim_buf_get_name(buf)

  local ok, err = apply_fix('frontmatter', file)
  if not ok then
    vim.notify('blogcli frontmatter: ' .. err, vim.log.levels.ERROR)
    return
  end

  -- A footnotes error (e.g. a bare [^3] with no definition) shouldn't
  -- block the save; keep any front matter fix and warn.
  local fok, ferr = apply_fix('footnotes', file)
  if not fok then
    vim.notify('blogcli footnotes: ' .. ferr, vim.log.levels.WARN)
  end

  sync_buffer_from_disk(buf, file)
end

---Run `blogcli lint <file>` and report per the on-save policy: always
---show errors, show warnings only when `mode` is 'all'.
local function lint_feedback(file, mode)
  local r = vim.system({ blogcli(), 'lint', file }, { text = true }):wait()
  local report = vim.trim(r.stdout)
  if r.code ~= 0 then
    vim.notify(report ~= '' and report or 'blogcli lint failed', vim.log.levels.ERROR)
  elseif mode == 'all' and report ~= '' then
    vim.notify(report, vim.log.levels.WARN)
  end
end

-- ── Manual actions (keymaps) ────────────────────────────────────────────

local function run_fix(subcommand, action_desc)
  if not have_blogcli() then
    missing_blogcli_notice()
    return
  end
  if vim.bo.modified then
    vim.notify('blogcli: save the buffer before ' .. action_desc, vim.log.levels.WARN)
    return
  end
  local file = vim.api.nvim_buf_get_name(0)
  local ok, msg = apply_fix(subcommand, file)
  if not ok then
    vim.notify('blogcli: ' .. msg, vim.log.levels.ERROR)
    return
  end
  vim.cmd.edit()
  vim.notify(msg ~= '' and msg or ('blogcli: ' .. action_desc .. ' done'), vim.log.levels.INFO)
end

local function lint_current()
  if not have_blogcli() then
    missing_blogcli_notice()
    return
  end
  local r = vim.system({ blogcli(), 'lint', vim.api.nvim_buf_get_name(0) }, { text = true }):wait()
  local report = vim.trim(r.stdout)
  if report == '' then
    vim.notify('blogcli: front matter looks clean', vim.log.levels.INFO)
    return
  end
  vim.notify(report, r.code ~= 0 and vim.log.levels.ERROR or vim.log.levels.WARN)
end

-- ── Wiring ──────────────────────────────────────────────────────────────

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
    map('<leader>pf', function() run_fix('footnotes', 'renumbering footnotes') end, 'Blog: [P]ost [F]ix/renumber footnotes')
    map('<leader>pm', function() run_fix('frontmatter', 'fixing front matter') end, 'Blog: [P]ost fix front [M]atter')
    map('<leader>pl', lint_current, 'Blog: [P]ost [L]int front matter')
  end,
})

vim.api.nvim_create_autocmd('BufWritePost', {
  group = augroup,
  pattern = '*.md',
  callback = function(ev)
    if not is_blog_content(vim.api.nvim_buf_get_name(ev.buf)) or not have_blogcli() then
      return
    end
    if vim.g.blogcli_format_on_save ~= false then
      format_buffer(ev.buf)
    end
    local lint_mode = vim.g.blogcli_lint_on_save
    if lint_mode == nil then
      lint_mode = 'errors'
    end
    if lint_mode ~= false then
      lint_feedback(vim.api.nvim_buf_get_name(ev.buf), lint_mode)
    end
  end,
})
