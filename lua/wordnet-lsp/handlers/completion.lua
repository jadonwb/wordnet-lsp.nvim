--- textDocument/completion handler — modeled after blink-cmp-words' source.lua.
--- Uses the proven disk-based wordnet engine with fzy fuzzy matching.
--- Thesaurus completion is intentionally excluded (synonyms belong in code actions).

local wordnet = require('wordnet-lsp.wordnet')

local M = {}

--- Completion configuration — matches blink-cmp-words' DEFAULT_OPTS.
local config = {
  --- Minimum keyword length to query WordNet. Keywords shorter than
  --- or equal to this are silently skipped (no disk I/O).
  --- Matches blink-cmp-words' `dictionary_search_threshold` (default 3).
  dictionary_search_threshold = 3,
}

--- Pointer types shown in the resolved definition.
local DEFINITION_POINTERS = { '!', '&', '^', '@', '~' }

--- Apply user configuration.
--- @param opts table|nil
function M.setup(opts)
  if opts then
    config = vim.tbl_deep_extend('keep', opts, config)
  end
end

----------------------------------------------------------------------
-- Word extraction (same logic used by hover handler)
----------------------------------------------------------------------

local function is_word_char(c)
  return c:match('[%w\'-]') ~= nil
end

--- Extract the word prefix before cursor (completion only needs text left of cursor).
local function get_word_prefix(line, byte_col)
  if not line or #line == 0 then return nil end
  local pos = byte_col - 1
  if pos < 1 or pos > #line then return nil end
  if not is_word_char(line:sub(pos, pos)) then return nil end
  local start = pos
  while start > 1 and is_word_char(line:sub(start - 1, start - 1)) do
    start = start - 1
  end
  return line:sub(start, pos)
end

local function utf16_to_byte(line, utf16_col)
  if vim.str_byteindex then
    return vim.str_byteindex(line, utf16_col, true)
  end
  return utf16_col
end

----------------------------------------------------------------------
-- Handler — modeled after blink-cmp-words source:get_completions()
----------------------------------------------------------------------

local empty_result = { isIncomplete = true, items = {} }

--- Handle textDocument/completion.
--- Only the dictionary server provides completion.
--- @param params lsp.CompletionParams
--- @param server_type string
--- @param callback fun(err: table|nil, result: lsp.CompletionList|nil)
function M.handle(params, server_type, callback)
  -- Only dictionary server handles completion
  if server_type ~= 'dictionary' then
    callback(nil, empty_result)
    return
  end

  -- Validate params
  if not params or not params.textDocument or not params.textDocument.uri or not params.position then
    callback(nil, empty_result)
    return
  end

  -- Get buffer and line
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  if bufnr == 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    callback(nil, empty_result)
    return
  end

  local line_idx = params.position.line
  local lines = vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)
  local line = lines[1]
  if not line or #line == 0 then
    callback(nil, empty_result)
    return
  end

  -- Extract prefix (the "keyword" in blink-cmp-words terms)
  local byte_col = utf16_to_byte(line, params.position.character) + 1
  local keyword = get_word_prefix(line, byte_col)
  if not keyword then
    callback(nil, empty_result)
    return
  end

  -- Skip query for short keywords (avoids unnecessary disk I/O)
  if #keyword <= config.dictionary_search_threshold then
    callback(nil, empty_result)
    return
  end

  -- get_word_matches handles exact vs fuzzy internally based on threshold
  local ok, matches = pcall(
    wordnet.get_word_matches,
    keyword,
    config.dictionary_search_threshold
  )

  if not ok then
    vim.notify('[wordnet-lsp] completion error: ' .. tostring(matches), vim.log.levels.WARN)
    callback(nil, empty_result)
    return
  end

  -- get_word_matches always returns a table
  if type(matches) ~= 'table' then
    matches = {}
  end

  -- Build CompletionItems — matches blink-cmp-words item structure
  local items = {}
  for i, word in ipairs(matches) do
    table.insert(items, {
      label = word,
      kind = 1, -- Text
      detail = 'WordNet',
      filterText = keyword, -- original keyword (matches blink-cmp-words)
      insertText = word,
      sortText = string.format('%04d', i), -- preserve WordNet order
    })
  end

  -- Always incomplete: forces re-query on every keystroke
  callback(nil, { isIncomplete = true, items = items })
end

--- Handle completionItem/resolve — adds WordNet definition as documentation.
--- @param item lsp.CompletionItem
--- @param callback fun(err: table|nil, result: lsp.CompletionItem|nil)
function M.resolve(item, callback)
  if not item or not item.label then
    callback(nil, item)
    return
  end

  local ok, definition = pcall(
    wordnet.get_definition_for_word,
    item.label,
    DEFINITION_POINTERS
  )

  if ok and definition and #definition > 0 then
    item.documentation = {
      kind = 'markdown',
      value = definition,
    }
  end

  callback(nil, item)
end

return M
