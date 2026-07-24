-- AST-based [[wikilink]] resolver for Quarto/Pandoc, installed verbatim
-- into every vault's root by `vk new` (modules/features/vk/vk.sh).
--
-- Supports two forms:
--   [[permanent/compiler-design]]                 -> link text = target
--   [[permanent/compiler-design.md|Display Text]] -> link text = "Display Text"
--
-- Cross-vault mesh links (see the spec's "Class 2") are handled by the
-- exact same logic: a target like "../../work/_site/permanent/foo" is
-- just a relative path as far as this filter is concerned - it gets the
-- same ".md -> .html" rewrite and passes straight through.
--
-- Operates on the whole Inlines run (not a single Str) rather than
-- regexing raw Markdown text, because Pandoc's parser splits a
-- wikilink into several separate Str/Space/SoftBreak AST nodes
-- whenever its target or display text contains a space (e.g.
-- "[[Agentic Coding Tools.md|Agentic Coding Tools]]") - a single-Str
-- match would silently never fire for those and print the literal
-- brackets. Any other inline (Emph, Code, an actual Link, ...) breaks
-- the accumulated run, so a wikilink is only recognized when written as
-- plain text, not nested inside other markup.

-- Flatten a run of plain Str/Space/SoftBreak inlines starting at index
-- `from` back into one string, stopping at the first inline of any
-- other type. Returns the string and the index of the last inline
-- consumed.
local function flatten_run(inlines, from)
  local text = ""
  local to = from - 1
  for k = from, #inlines do
    local el = inlines[k]
    if el.t == "Str" then
      text = text .. el.text
    elseif el.t == "Space" or el.t == "SoftBreak" then
      text = text .. " "
    else
      break
    end
    to = k
  end
  return text, to
end

-- Turn a plain string back into Str/Space inlines (used for whatever
-- text surrounds a resolved wikilink within the same run).
local function to_inlines(text)
  local out = pandoc.List()
  local first = true
  for word in text:gmatch("%S+") do
    if not first then out:insert(pandoc.Space()) end
    out:insert(pandoc.Str(word))
    first = false
  end
  if text:match("^%s") and #out > 0 then out:insert(1, pandoc.Space()) end
  if text:match("%s$") and #out > 0 then out:insert(pandoc.Space()) end
  return out
end

local function resolve_link(target, display)
  target = target:match("^%s*(.-)%s*$")
  if not display or display == "" then
    display = target
  else
    display = display:match("^%s*(.-)%s*$")
  end

  local url = target
  if not string.find(url, "%.md$") and not string.find(url, "%.html$") then
    url = url:lower():gsub(" ", "-") .. ".html"
  else
    url = url:gsub("%.md$", ".html")
  end
  return pandoc.Link(to_inlines(display), url)
end

function Inlines(inlines)
  local out = pandoc.List()
  local changed = false
  local i = 1
  local n = #inlines

  while i <= n do
    local el = inlines[i]
    if el.t == "Str" and el.text:find("%[%[") then
      local text, to = flatten_run(inlines, i)
      local pos = 1
      local any = false

      while true do
        local s = text:find("%[%[", pos)
        if not s then break end
        local e = text:find("%]%]", s + 2)
        if not e then break end

        local inner = text:sub(s + 2, e - 1)
        -- Split on the *first* "|" only, so a display text containing
        -- its own "|" (unlikely, but not worth crashing over) doesn't
        -- confuse the match.
        local target, display = inner:match("^(.-)|(.-)$")
        if not target then
          target = inner
          display = nil
        end

        if s > pos then
          out:extend(to_inlines(text:sub(pos, s - 1)))
        end
        out:insert(resolve_link(target, display))
        pos = e + 2
        any = true
        changed = true
      end

      if any then
        if pos <= #text then
          out:extend(to_inlines(text:sub(pos)))
        end
        i = to + 1
      else
        out:insert(el)
        i = i + 1
      end
    else
      out:insert(el)
      i = i + 1
    end
  end

  if changed then return out end
  return nil
end
