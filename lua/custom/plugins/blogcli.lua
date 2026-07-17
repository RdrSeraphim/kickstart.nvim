-- Integration for `blogcli`, the footnote renumbering tool in
-- rdrseraphim/blog (cmd/blogcli): turns a footnote written with its text
-- right in the marker, e.g. [^A cat sound.], into the blog's numbered
-- [^1]/[^2] endnote style.
--
-- Metadata scaffolding and preview are intentionally *not* handled here:
-- use `hugo new posts/YYYY/MM/DD/slug/index.md` / `hugo new pages/slug.md`
-- (archetypes/ already matches the site's front matter) for new content,
-- and `hugo server` (browser) or a renderer like render-markdown.nvim's
-- `:RenderMarkdown` (in-buffer) for preview.
--
-- Requires the `blogcli` binary on your PATH (from the blog repo:
-- `go build -o ~/go/bin/blogcli ./cmd/blogcli`, or `go install
-- ./cmd/blogcli` with GOBIN on PATH). Override the command with
-- vim.g.blogcli_cmd if you keep it somewhere else.
--
-- <leader>pf is only set on markdown buffers that sit inside a Hugo site
-- (found by walking up for a hugo.toml), so it won't shadow anything in
-- unrelated markdown files.

local function blogcli_cmd()
  return vim.g.blogcli_cmd or 'blogcli'
end

---Find the Hugo site root containing `path`, or nil if there isn't one.
local function find_hugo_root(path)
  local found = vim.fs.find('hugo.toml', { path = vim.fs.dirname(path), upward = true })[1]
  return found and vim.fs.dirname(found) or nil
end

local function fix_footnotes()
  if vim.fn.executable(blogcli_cmd()) == 0 then
    vim.notify(
      "blogcli: '" .. blogcli_cmd() .. "' not found on PATH. Build it from the blog repo with "
        .. '`go build -o ~/go/bin/blogcli ./cmd/blogcli`, or set vim.g.blogcli_cmd.',
      vim.log.levels.ERROR
    )
    return
  end
  if vim.bo.modified then
    vim.notify('blogcli: save the buffer before renumbering footnotes', vim.log.levels.WARN)
    return
  end

  local file = vim.api.nvim_buf_get_name(0)
  local result = vim.system({ blogcli_cmd(), '-w', file }, { text = true }):wait()

  if result.code ~= 0 then
    vim.notify('blogcli: ' .. vim.trim(result.stderr), vim.log.levels.ERROR)
    return
  end

  vim.cmd.edit()
  local msg = vim.trim(result.stderr)
  vim.notify(msg ~= '' and msg or 'blogcli: footnotes renumbered', vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('blogcli', { clear = true }),
  pattern = 'markdown',
  callback = function(ev)
    if not find_hugo_root(vim.api.nvim_buf_get_name(ev.buf)) then
      return
    end
    vim.keymap.set('n', '<leader>pf', fix_footnotes, { buffer = ev.buf, desc = 'Blog: [P]ost [F]ix/renumber footnotes' })
  end,
})
