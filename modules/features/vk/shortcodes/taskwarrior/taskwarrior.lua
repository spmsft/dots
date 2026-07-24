-- taskwarrior.lua — vk shortcode: {{< task-table <taskwarrior filter args> >}}
--
-- Renders a live Taskwarrior query as an HTML table (ID/Description/
-- Priority/Due), reusing the user's real `task` config/data (no
-- rc:/dev/null override - deliberately reads ~/.taskrc & ~/.task, same
-- as running `task` directly in a shell) so the table always reflects
-- the tasks that actually exist. `task` itself is a soft/optional
-- dependency (suites.pim-apps.taskwarrior, default-on, but this filter
-- must not hard-fail a vault render just because one particular
-- machine has it disabled) - checked via `command -v` before shelling
-- out; missing/failed lookups render a friendly note instead of
-- breaking the whole page.
--
-- Built as a raw HTML RawBlock rather than a native pandoc.Table AST
-- node (e.g. via a generated Markdown table string + pandoc.read()) -
-- a real pandoc.Table here trips a quarto-internal crossref-walker bug
-- (its jog.lua module errors "Don't know how to traverse TableBody"
-- for shortcode-returned tables - the render output itself still comes
-- out correct, but the error spam is confusing). Since vk only ever
-- renders to html (see every vault's _quarto.yml), RawBlock sidesteps
-- that entirely with no loss of functionality - just remember to
-- html-escape any user-supplied text (descriptions) manually, since
-- RawBlock content is emitted verbatim.
local json = require("pandoc.json")

-- Taskwarrior exports dates as "YYYYMMDDTHHMMSSZ" - reduce to
-- "YYYY-MM-DD" for a compact table; anything that doesn't match that
-- shape (or is absent) is passed through/blanked as-is.
local function format_date(tw_date)
  if not tw_date then return "-" end
  local year, month, day = tw_date:match("(%d%d%d%d)(%d%d)(%d%d)")
  if year then return year .. "-" .. month .. "-" .. day end
  return tw_date
end

-- Single-quote a shell argument, escaping any embedded single quotes -
-- shortcode args come from note authors (trusted local content), but
-- quoting properly avoids surprises from args containing spaces/shell
-- metacharacters (e.g. `{{< task-table project:"Home Repairs" >}}`).
local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Escape HTML special characters for a raw HTML table cell - RawBlock
-- content is emitted verbatim by pandoc, so anything user-supplied
-- (task descriptions) must be escaped here, not left to pandoc.
local function html_escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

return {
  ['task-table'] = function(args)
    if os.execute("command -v task >/dev/null 2>&1") ~= true then
      return pandoc.Para({ pandoc.Emph({ pandoc.Str(
        "Taskwarrior ('task') not found - install/enable it to use task-table.") }) })
    end

    local quoted = {}
    for _, arg in ipairs(args) do
      table.insert(quoted, shell_quote(pandoc.utils.stringify(arg)))
    end
    local filter_args = table.concat(quoted, " ")

    local handle = io.popen("task " .. filter_args .. " export 2>/dev/null")
    local raw = handle:read("*a")
    handle:close()

    local ok, tasks = pcall(json.decode, raw)
    if not ok or not tasks or #tasks == 0 then
      return pandoc.Para({ pandoc.Emph({ pandoc.Str("No tasks found.") }) })
    end

    -- Built as raw HTML (rather than a generated Markdown table parsed
    -- back via pandoc.read()) - a native pandoc.Table AST node here
    -- trips a real quarto-internal crossref-walker bug (its jog.lua
    -- module errors with "Don't know how to traverse TableBody" for
    -- shortcode-returned tables, though the render output itself comes
    -- out correct) - since vk only ever renders to html (see every
    -- vault's _quarto.yml), a plain RawBlock sidesteps that bug
    -- entirely with no loss of functionality.
    local html = { '<table class="table task-table">',
      "<thead><tr><th>ID</th><th>Description</th><th>Priority</th><th>Due</th></tr></thead>",
      "<tbody>" }

    for _, item in ipairs(tasks) do
      local id = item.id and string.format("%d", item.id) or "-"
      local desc = html_escape(item.description or "")
      local priority = html_escape(item.priority or "-")
      local due = format_date(item.due)
      table.insert(html, string.format(
        "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
        id, desc, priority, due))
    end
    table.insert(html, "</tbody></table>")

    return pandoc.RawBlock("html", table.concat(html, "\n"))
  end
}

