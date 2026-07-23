-- AST-based [[wikilink]] resolver for Quarto/Pandoc, installed verbatim
-- into every vault's root by `vk new` (modules/features/vk/vk.sh). Works
-- on the parsed AST rather than regexing raw Markdown text, so it's safe
-- against wikilinks that land inside otherwise-ambiguous surrounding
-- punctuation.
--
-- Supports two forms:
--   [[permanent/compiler-design]]                 -> link text = target
--   [[permanent/compiler-design.md|Display Text]] -> link text = "Display Text"
--
-- Cross-vault mesh links (see the spec's "Class 2") are handled by the
-- exact same logic: a target like "../../work/_site/permanent/foo" is
-- just a relative path as far as this filter is concerned - it gets the
-- same ".md -> .html" rewrite and passes straight through.
function Str(el)
  -- Try the more specific piped form first - the plain form's pattern
  -- ("%[%[(.-)%]%]") would otherwise greedily match straight through to
  -- the final "]]" on a piped link too (Lua's "-" is non-greedy but
  -- there's no earlier "]]" to stop at), swallowing "target|display"
  -- whole as the target and never reaching the piped branch at all.
  local target, display = string.match(el.text, "%[%[(.-)|(.-)%]%]")
  if not target then
    target = string.match(el.text, "%[%[(.-)%]%]")
    display = nil
  end

  if target then
    target = target:match("^%s*(.-)%s*$")
    if not display or display == "" then display = target else display = display:match("^%s*(.-)%s*$") end

    local url = target
    if not string.find(url, "%.md$") and not string.find(url, "%.html$") then
      url = url:lower():gsub(" ", "-") .. ".html"
    else
      url = url:gsub("%.md$", ".html")
    end
    return pandoc.Link(pandoc.Str(display), url)
  end
  return el
end
