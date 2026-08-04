-- taskwarrior.lua — Pandoc Lua filter for vk's `taskwarrior` directive.
--
-- vk's MyST-native authoring syntax is:
--
--   :::{taskwarrior} Active GQL Tasks
--   :project: gql-spec
--   :status: pending
--   :tags: database,gql
--   :limit: 5
--
--   Optional fallback text.
--   :::
--
-- Before a MyST build, vk's Pandoc preprocessing step (see
-- ../scripts/taskwarrior-preprocess.py) rewrites only these directive
-- blocks - and nothing else in the document - into a standard Pandoc
-- fenced Div:
--
--   ::: {.taskwarrior title="Active GQL Tasks" project="gql-spec"
--     status="pending" tags="database,gql" limit="5"}
--   Optional fallback text.
--   :::
--
-- This filter matches that Div, queries the user's real Taskwarrior
-- data/config (~/.taskrc & ~/.task - deliberately no rc:/dev/null
-- override, same as running `task` directly), and replaces the Div's
-- content with a rendered task table. The resulting document is
-- ordinary Pandoc AST -> Markdown, which is spliced back into the
-- staging tree for MyST to render normally.
--
-- Security: every directive attribute is passed to `task` through
-- `pandoc.pipe`'s argv array, which execs `task` directly (no shell
-- involved) - so values can never be interpreted as shell syntax or
-- used to inject extra commands, regardless of what a note author
-- writes in project/status/tags.
--
-- Failure handling: a missing `task` binary, a failing query, malformed
-- JSON, or an empty result set all fall back to the directive's own
-- body content if present, or a short generated note otherwise - never
-- a hard build failure and never a silently empty page.

local json = require("pandoc.json")

-- Taskwarrior exports dates as "YYYYMMDDTHHMMSSZ" - reduce to
-- "YYYY-MM-DD" for a compact table; anything not matching that shape
-- (or absent) passes through/blanks as-is.
local function format_date(tw_date)
  if not tw_date then return "-" end
  local year, month, day = tw_date:match("(%d%d%d%d)(%d%d)(%d%d)")
  if year then return year .. "-" .. month .. "-" .. day end
  return tw_date
end

local function split_tags(s)
  local out = {}
  for tag in s:gmatch("[^,]+") do
    table.insert(out, (tag:gsub("^%s+", ""):gsub("%s+$", "")))
  end
  return out
end

-- Fallback content: the directive's own body if it has one, otherwise a
-- single generated note paragraph.
local function fallback_blocks(div, message)
  if #div.content > 0 then
    return div.content
  end
  return { pandoc.Para({ pandoc.Emph({ pandoc.Str(message) }) }) }
end

local function render_table(title, tasks)
  local st = pandoc.SimpleTable(
    title and title ~= "" and { pandoc.Str(title) } or {},
    { pandoc.AlignDefault, pandoc.AlignDefault, pandoc.AlignDefault, pandoc.AlignDefault },
    { 0, 0, 0, 0 },
    {
      pandoc.Plain({ pandoc.Str("ID") }),
      pandoc.Plain({ pandoc.Str("Description") }),
      pandoc.Plain({ pandoc.Str("Priority") }),
      pandoc.Plain({ pandoc.Str("Due") }),
    },
    (function()
      local rows = {}
      for _, item in ipairs(tasks) do
        local id = item.id and string.format("%d", item.id) or "-"
        table.insert(rows, {
          pandoc.Plain({ pandoc.Str(id) }),
          pandoc.Plain({ pandoc.Str(item.description or "") }),
          pandoc.Plain({ pandoc.Str(item.priority or "-") }),
          pandoc.Plain({ pandoc.Str(format_date(item.due)) }),
        })
      end
      return rows
    end)()
  )
  return { pandoc.utils.from_simple_table(st) }
end

function Div(div)
  if not div.classes:includes("taskwarrior") then
    return nil
  end

  local attrs = div.attributes
  local title = attrs["title"] or ""

  if os.execute("command -v task >/dev/null 2>&1") ~= true then
    return pandoc.Div(fallback_blocks(div,
      "Taskwarrior ('task') not found - install/enable it to use the taskwarrior directive."))
  end

  local args = {}
  if attrs["project"] then table.insert(args, "project:" .. attrs["project"]) end
  if attrs["status"] then table.insert(args, "status:" .. attrs["status"]) end
  if attrs["tags"] then
    for _, tag in ipairs(split_tags(attrs["tags"])) do
      table.insert(args, "+" .. tag)
    end
  end
  table.insert(args, "export")

  local ok, raw = pcall(pandoc.pipe, "task", args, "")
  if not ok or not raw then
    return pandoc.Div(fallback_blocks(div,
      "Taskwarrior query failed - showing fallback content."))
  end

  local decode_ok, tasks = pcall(json.decode, raw)
  if not decode_ok or not tasks then
    return pandoc.Div(fallback_blocks(div,
      "Taskwarrior returned unreadable output - showing fallback content."))
  end

  if #tasks == 0 then
    return pandoc.Div(fallback_blocks(div, "No matching tasks found."))
  end

  local limit = tonumber(attrs["limit"])
  if limit and limit > 0 and limit < #tasks then
    local trimmed = {}
    for i = 1, limit do
      trimmed[i] = tasks[i]
    end
    tasks = trimmed
  end

  return pandoc.Div(render_table(title, tasks))
end
