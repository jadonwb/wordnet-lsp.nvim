--- textDocument/hover handler.
--- Shows WordNet definition in a floating window when hovering over a word.

local wordnet = require('wordnet-lsp.wordnet')
local morphology = require('wordnet-lsp.morphology')

local M = {}

--- Configurable options (set via M.setup).
local config = {
  use_morphology = true,
  definition_pointers = { '!', '&', '^', '@', '~', '@i', '~i' },
}

--- Apply user configuration.
--- @param opts table|nil
function M.setup(opts)
  if opts then
    config = vim.tbl_deep_extend('keep', opts, config)
  end
end

--- Pointer symbols to include in the definition display.
---   !  = Antonym    &  = Similar to    ^  = Also see
---   @  = Hypernym   ~  = Hyponym
---   @i = Instance Hypernym   ~i = Instance Hyponym
--- Convert a file:// URI to a buffer number.
--- @param uri string
--- @return integer|nil
local function buf_from_uri(uri)
  local bufnr = vim.uri_to_bufnr(uri)
  if bufnr == 0 then return nil end
  return bufnr
end

--- Extract the word at a given byte position in a line of text.
--- Uses alphanumeric plus hyphens and apostrophes as word characters.
--- @param line string The line content
--- @param col integer Byte position (1-indexed)
--- @return string|nil The extracted word, or nil if no word found
local function get_word_at_col(line, col)
  if not line or #line == 0 then return nil end
  if col < 1 or col > #line then return nil end

  -- Word characters: alphanumeric, underscore, hyphen, apostrophe
  local is_word_char = function(c)
    return c:match('[%w\'-]') ~= nil
  end

  -- If cursor is not on a word character, try adjacent positions
  if not is_word_char(line:sub(col, col)) then
    -- Try one char left, then one char right
    if col > 1 and is_word_char(line:sub(col - 1, col - 1)) then
      col = col - 1
    elseif col < #line and is_word_char(line:sub(col + 1, col + 1)) then
      col = col + 1
    else
      return nil
    end
  end

  -- Scan left to find word start
  local start = col
  while start > 1 and is_word_char(line:sub(start - 1, start - 1)) do
    start = start - 1
  end

  -- Scan right to find word end
  local finish = col
  while finish < #line and is_word_char(line:sub(finish + 1, finish + 1)) do
    finish = finish + 1
  end

  if start <= finish then
    return line:sub(start, finish)
  end
  return nil
end

--- Handle hover request.
--- Extract the word under cursor, query WordNet for its definition,
--- and return it as a markdown hover.
--- @param params lsp.HoverParams
--- @param callback fun(err: table|nil, result: lsp.Hover|nil)
function M.handle(params, callback)
  -- Validate params (defensive guard against malformed input)
  if not params or not params.textDocument or not params.textDocument.uri or not params.position then
    callback(nil, nil)
    return
  end

  -- Get the buffer
  local bufnr = buf_from_uri(params.textDocument.uri)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    callback(nil, nil)
    return
  end

  -- Get the line content at cursor position
  local line_idx = params.position.line
  local lines = vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)
  local line = lines[1]
  if not line or #line == 0 then
    callback(nil, nil)
    return
  end

  -- Extract the word at the cursor position.
  -- LSP position.character is a 0-indexed UTF-16 code unit offset.
  -- Convert to byte offset for Lua string indexing (1-indexed).
  -- For ASCII text these are identical; for multi-byte UTF-8 they differ.
  local byte_col
  if vim.str_byteindex then
    byte_col = vim.str_byteindex(line, params.position.character, true) + 1
  else
    -- Fallback for older Neovim: assume ASCII (correct for English text)
    byte_col = params.position.character + 1
  end
  local word = get_word_at_col(line, byte_col)
  if not word or #word == 0 then
    callback(nil, nil)
    return
  end

  -- Generate candidate lemmas if morphology is enabled, otherwise exact word only.
  local candidates
  if config.use_morphology then
    candidates = morphology.get_candidate_lemmas(word)
  else
    candidates = { word:lower() }
  end

  for _, candidate in ipairs(candidates) do
    local ok, definition = pcall(
      wordnet.get_definition_for_word,
      candidate,
      config.definition_pointers
    )

    if not ok then
      -- Internal error in WordNet engine — log for debugging
      vim.notify('[wordnet-lsp] hover error: ' .. tostring(definition), vim.log.levels.WARN)
      break
    end

    if definition and #definition > 0 then
      -- Found a definition — return it as markdown hover
      callback(nil, {
        contents = {
          kind = 'markdown',
          value = definition,
        },
      })
      return
    end
  end

  -- No definition found for any candidate — return empty
  callback(nil, nil)
end

return M
