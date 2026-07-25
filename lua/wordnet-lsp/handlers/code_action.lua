--- textDocument/codeAction handler.
--- Provides code actions that open a picker to browse and select
--- synonym or antonym replacements for the word under cursor.
---
--- Uses vim.ui.select() for the picker, which delegates to the user's
--- configured picker (Telescope, snacks.picker, fzf-lua, or built-in).
--- For preview support (definition while browsing), a future version
--- can integrate directly with Telescope or snacks.picker APIs.

local wordnet = require('wordnet-lsp.wordnet')
local morphology = require('wordnet-lsp.morphology')

local M = {}

--- Default configuration.
local config = {
  --- Show lemmatized synonym/antonym options (e.g. "start" for "started").
  use_morphology = true,

  --- Maximum replacement candidates to show in the picker.
  max_results = 100,

  --- Depth for recursive synset traversal (higher = more results, slower).
  similarity_depth = 2,

  --- Fuzzy search threshold for initial word lookup.
  search_threshold = 3,
}

--- Pointer types for similar words and antonyms.
local SIMILAR_POINTERS = { '&', '^' } -- Similar to, Also see
local ANTONYM_POINTERS = { '!' }       -- Antonym (lexical opposite)

--- Apply user configuration.
--- @param opts table|nil
function M.setup(opts)
  if opts then
    config = vim.tbl_deep_extend('keep', opts, config)
  end
end

----------------------------------------------------------------------
-- Word extraction (shares logic with hover handler)
----------------------------------------------------------------------

local function is_word_char(c)
  return c:match('[%w\'-]') ~= nil
end

local function get_word_at_col(line, col)
  if not line or #line == 0 then return nil end
  if col < 1 or col > #line then return nil end

  if not is_word_char(line:sub(col, col)) then
    if col > 1 and is_word_char(line:sub(col - 1, col - 1)) then
      col = col - 1
    elseif col < #line and is_word_char(line:sub(col + 1, col + 1)) then
      col = col + 1
    else
      return nil
    end
  end

  local start = col
  while start > 1 and is_word_char(line:sub(start - 1, start - 1)) do
    start = start - 1
  end

  local finish = col
  while finish < #line and is_word_char(line:sub(finish + 1, finish + 1)) do
    finish = finish + 1
  end

  if start <= finish then
    return line:sub(start, finish), start, finish
  end
  return nil
end

local function utf16_to_byte(line, utf16_col)
  if vim.str_byteindex then
    return vim.str_byteindex(line, utf16_col, true)
  end
  return utf16_col
end

local function get_word_and_range(params)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  if bufnr == 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local line_idx = params.range.start.line
  local lines = vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)
  local line = lines[1]
  if not line or #line == 0 then
    return nil
  end

  local start_char = params.range.start.character
  local end_char = params.range['end'].character

  if start_char ~= end_char or params.range.start.line ~= params.range['end'].line then
    local byte_start = utf16_to_byte(line, start_char) + 1
    local byte_end = utf16_to_byte(line, end_char)
    if byte_start < 1 then byte_start = 1 end
    if byte_end > #line then byte_end = #line end
    local word = line:sub(byte_start, byte_end)
    if word and #word > 0 and word:match('[%w]') then
      return word, {
        start = { line = line_idx, character = start_char },
        ['end'] = { line = line_idx, character = end_char },
      }
    end
    return nil
  end

  local byte_col = utf16_to_byte(line, start_char) + 1
  local word, byte_start, byte_finish = get_word_at_col(line, byte_col)
  if not word then
    return nil
  end

  return word, {
    start = { line = line_idx, character = byte_start - 1 },
    ['end'] = { line = line_idx, character = byte_finish },
  }
end

----------------------------------------------------------------------
-- WordNet queries
----------------------------------------------------------------------

--- Query WordNet for the exact word only (first morphological candidate).
--- @return string[]|nil
local function query_exact(word, pointers)
  local candidates = morphology.get_candidate_lemmas(word)
  -- Only use the first candidate (the exact word, or primary irregular form)
  local candidate = candidates[1]
  if not candidate then return nil end

  local ok, result = pcall(
    wordnet.get_similar_words_for_word,
    candidate,
    config.search_threshold,
    pointers,
    config.similarity_depth
  )
  if ok and type(result) == 'table' and #result > 0 then
    return result
  end
  return nil
end

--- Query WordNet for the lemmatized (base) form of the word only.
--- Uses the first morphological variant (e.g. "start" for "started").
--- Returns nil if the word has no lemmatized form.
--- @return string[]|nil
local function query_lemmatized(word, pointers)
  local candidates = morphology.get_candidate_lemmas(word)
  -- Need at least 2 candidates: [1] = exact word, [2] = lemmatized form
  if #candidates < 2 then return nil end
  local lemma = candidates[2]

  local ok, result = pcall(
    wordnet.get_similar_words_for_word,
    lemma,
    config.search_threshold,
    pointers,
    config.similarity_depth
  )
  if ok and type(result) == 'table' and #result > 0 then
    return result
  end
  return nil
end

--- Get synonyms and antonyms for a word.
--- @param word string The word to look up
--- @param merged boolean If true, merge results from all lemmatized forms
--- @return string[]|nil synonyms, string[]|nil antonyms
local function get_replacements(word, merged)
  local query_fn = merged and query_lemmatized or query_exact
  local synonyms = query_fn(word, SIMILAR_POINTERS)
  local with_antonyms = query_fn(word, ANTONYM_POINTERS)

  if not synonyms and not with_antonyms then
    return nil, nil
  end

  -- Compute antonyms by subtracting synonyms from the combined list.
  -- get_similar_words_for_word always includes the synset's own words
  -- (the synonyms) regardless of pointer filter. The ! pointer adds
  -- antonym words on top. Subtracting leaves only true antonyms.
  local antonyms = nil
  if with_antonyms then
    -- Build a lookup set from synonyms (case-insensitive)
    local syn_set = {}
    if synonyms then
      for _, w in ipairs(synonyms) do
        syn_set[w:lower()] = true
      end
    end

    -- Collect words from with_antonyms that are NOT in the synonym set
    local ant_list = {}
    for _, w in ipairs(with_antonyms) do
      if not syn_set[w:lower()] then
        table.insert(ant_list, w)
      end
    end

    if #ant_list > 0 then
      antonyms = ant_list
    end
  end

  return synonyms, antonyms
end

----------------------------------------------------------------------
-- Picker and code actions
----------------------------------------------------------------------

local function apply_replacement(uri, range, new_text)
  local bufnr = vim.uri_to_bufnr(uri)
  if bufnr == 0 then return end
  vim.lsp.util.apply_text_edits({
    { range = range, newText = new_text },
  }, bufnr, 'utf-16')
end

--- Open a picker with replacement candidates.
--- Uses vim.ui.select() which delegates to the user's configured UI
--- (Telescope, snacks.picker, fzf-lua, or built-in selector).
--- For preview support, see the module docstring.
local function open_replacement_picker(words, original_word, range, uri, label)
  if not words or #words == 0 then
    vim.notify(
      '[wordnet-lsp] No ' .. label .. ' found for "' .. original_word .. '"',
      vim.log.levels.INFO
    )
    return
  end

  -- Remove the original word from suggestions
  local items = {}
  for _, w in ipairs(words) do
    if w:lower() ~= original_word:lower() then
      table.insert(items, w)
    end
  end

  if #items == 0 then
    vim.notify(
      '[wordnet-lsp] No ' .. label .. ' found for "' .. original_word .. '"',
      vim.log.levels.INFO
    )
    return
  end

  -- Limit results
  if #items > config.max_results then
    items = { unpack(items, 1, config.max_results) }
  end

  vim.ui.select(items, {
    prompt = 'Replace "' .. original_word .. '" with (' .. label .. '):',
    format_item = function(item)
      return item
    end,
  }, function(choice)
    if choice then
      apply_replacement(uri, range, choice)
    end
  end)
end

--- Build a code action that opens a picker via workspace/executeCommand.
local function build_picker_action(title, words, original_word, range, uri, label)
  return {
    title = title,
    kind = 'refactor.rewrite',
    command = {
      title = title,
      command = 'wordnet-lsp.open-picker',
      arguments = { words, original_word, range, uri, label },
    },
  }
end

----------------------------------------------------------------------
-- Handlers
----------------------------------------------------------------------

--- Handle textDocument/codeAction request.
--- @param params lsp.CodeActionParams
--- @param callback fun(err: table|nil, result: lsp.CodeAction[]|nil)
function M.handle(params, callback)
  if not params or not params.textDocument or not params.textDocument.uri then
    callback(nil, nil)
    return
  end
  if not params.range or not params.range.start or not params.range['end'] then
    callback(nil, nil)
    return
  end

  local word, range = get_word_and_range(params)
  if not word then
    callback(nil, nil)
    return
  end

  local actions = {}

  -- Exact form: synonyms and antonyms
  local exact_syn, exact_ant = get_replacements(word, false)

  if exact_syn and #exact_syn > 0 then
    table.insert(actions, build_picker_action(
      'Browse synonyms for "' .. word .. '"...',
      exact_syn, word, range, params.textDocument.uri, 'synonyms'
    ))
  end
  if exact_ant and #exact_ant > 0 then
    table.insert(actions, build_picker_action(
      'Browse antonyms for "' .. word .. '"...',
      exact_ant, word, range, params.textDocument.uri, 'antonyms'
    ))
  end

  -- Lemmatized form (only shown when use_morphology is enabled)
  if config.use_morphology then
    local candidates = morphology.get_candidate_lemmas(word)
    local lemma = #candidates > 1 and candidates[2] or word
    local merged_syn, merged_ant = get_replacements(word, true)

    if merged_syn and #merged_syn > 0 then
      table.insert(actions, build_picker_action(
        'Browse synonyms for "' .. lemma .. '" (from "' .. word .. '")...',
        merged_syn, lemma, range, params.textDocument.uri,
        'synonyms'
      ))
    end
    if merged_ant and #merged_ant > 0 then
      table.insert(actions, build_picker_action(
        'Browse antonyms for "' .. lemma .. '" (from "' .. word .. '")...',
        merged_ant, lemma, range, params.textDocument.uri,
        'antonyms'
      ))
    end
  end

  callback(nil, actions)
end

--- Handle workspace/executeCommand.
--- Called by the client when a code action with a command is selected.
--- @param params { command: string, arguments: any[] }
--- @param callback fun(err: table|nil, result: any|nil)
function M.execute_command(params, callback)
  if params.command == 'wordnet-lsp.open-picker' then
    local args = params.arguments or {}
    open_replacement_picker(args[1], args[2], args[3], args[4], args[5])
    callback(nil, nil)
  else
    callback({ code = -32601, message = 'Unknown command: ' .. params.command }, nil)
  end
end

return M
