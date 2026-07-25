--- WordNet LSP plugin for Neovim.
--- Two in-process LSP servers:
---   wordnet-dictionary  — completion (word lookup)
---   wordnet-thesaurus   — hover + code actions (synonym/antonym replacement)
---
--- Usage:
---   require('wordnet-lsp').setup({
---     filetypes = { 'text', 'markdown', 'txt' },
---     dictionary = { enabled = true, search_threshold = 3 },
---     thesaurus = {
---       enabled = true,
---       hover = { keymap = nil, use_morphology = true },
---       code_actions = { use_morphology = true, max_results = 100 },
---     },
---   })

local M = {}

local DEFAULT_OPTS = {
  --- If false, servers must be started manually via :WordNetLspStart
  auto_start = true,
  --- Filetypes to auto-attach to when auto_start is true
  filetypes = { 'text', 'markdown', 'txt' },

  --- Dictionary server: word completion
  dictionary = {
    enabled = true,
    --- Min chars to trigger WordNet query. Keywords <= this are skipped.
    search_threshold = 3,
  },

  --- Thesaurus server: hover + code actions
  thesaurus = {
    enabled = true,

    hover = {
      --- Buffer-local keymap for wordnet-only hover (does not replace K).
      --- e.g. '<Leader>wh'. nil = no mapping.
      keymap = nil,
      --- Try lemmatized forms (started → start) when exact lookup fails.
      use_morphology = true,
      --- WordNet pointer symbols to show in definition hover.
      definition_pointers = { '!', '&', '^', '@', '~' },
    },

    code_actions = {
      --- Show lemmatized synonym/antonym options.
      use_morphology = true,
      --- Max replacement candidates in the picker.
      max_results = 100,
      --- Chars below this → exact match; above → fuzzy.
      search_threshold = 3,
      --- Recursive synset traversal depth.
      similarity_depth = 2,
    },
  },
}

--- Track whether the current opts have been configured.
local configured_opts = nil

----------------------------------------------------------------------
-- Server lifecycle
----------------------------------------------------------------------

--- Start WordNet LSP servers for a buffer.
--- @param bufnr integer|nil
--- @param opts table|nil
function M.start(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = vim.tbl_deep_extend('keep', opts or {}, configured_opts or DEFAULT_OPTS)

  local server = require('wordnet-lsp.server')
  local root_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))

  if opts.dictionary.enabled then
    vim.lsp.start({
      name = 'wordnet-dictionary',
      cmd = server.create('dictionary'),
      root_dir = root_dir,
    }, { bufnr = bufnr })
  end

  if opts.thesaurus.enabled then
    vim.lsp.start({
      name = 'wordnet-thesaurus',
      cmd = server.create('thesaurus'),
      root_dir = root_dir,
    }, { bufnr = bufnr })

    -- Buffer-local keymap for wordnet-only hover
    if opts.thesaurus.hover.keymap then
      vim.keymap.set('n', opts.thesaurus.hover.keymap, function()
        local clients = vim.lsp.get_clients({
          name = 'wordnet-thesaurus',
          bufnr = bufnr,
        })
        if #clients == 0 then return end

        local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
        clients[1].request('textDocument/hover', params, function(err, result)
          if err or not result or not result.contents then return end
          vim.lsp.util.open_floating_preview(
            vim.islist(result.contents) and result.contents or { result.contents },
            'markdown',
            { border = 'rounded', max_width = 80 }
          )
        end, bufnr)
      end, { buffer = bufnr, desc = 'WordNet hover' })
    end
  end
end

--- Stop all WordNet LSP clients attached to a buffer.
--- @param bufnr integer|nil
function M.stop(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == 'wordnet-dictionary' or client.name == 'wordnet-thesaurus' then
      client.stop()
    end
  end
end

--- Toggle WordNet LSP servers for a buffer.
--- @param bufnr integer|nil
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == 'wordnet-dictionary' or client.name == 'wordnet-thesaurus' then
      M.stop(bufnr)
      vim.notify('[wordnet-lsp] Stopped', vim.log.levels.INFO)
      return
    end
  end
  M.start(bufnr)
  vim.notify('[wordnet-lsp] Started', vim.log.levels.INFO)
end

----------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------

--- Setup function for lazy.nvim integration.
--- @param opts table|nil
function M.setup(opts)
  configured_opts = vim.tbl_deep_extend('keep', opts or {}, DEFAULT_OPTS)

  -- Forward settings to handlers
  require('wordnet-lsp.handlers.completion').setup({
    dictionary_search_threshold = configured_opts.dictionary.search_threshold,
  })
  require('wordnet-lsp.handlers.hover').setup(configured_opts.thesaurus.hover)
  require('wordnet-lsp.handlers.code_action').setup(configured_opts.thesaurus.code_actions)

  -- Auto-attach
  if configured_opts.auto_start then
    vim.api.nvim_create_autocmd('FileType', {
      pattern = configured_opts.filetypes,
      callback = function(args)
        M.start(args.buf, configured_opts)
      end,
    })
  end

  -- Commands
  vim.api.nvim_create_user_command('WordNetLspStart', function()
    M.start(nil, configured_opts)
  end, { desc = 'Start WordNet LSP servers for current buffer' })

  vim.api.nvim_create_user_command('WordNetLspStop', function()
    M.stop()
  end, { desc = 'Stop WordNet LSP servers for current buffer' })

  vim.api.nvim_create_user_command('WordNetLspToggle', function()
    M.toggle()
  end, { desc = 'Toggle WordNet LSP servers for current buffer' })

  vim.api.nvim_create_user_command('WordNetHover', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local clients = vim.lsp.get_clients({ name = 'wordnet-thesaurus', bufnr = bufnr })
    if #clients == 0 then
      vim.notify('[wordnet-lsp] No thesaurus server attached', vim.log.levels.WARN)
      return
    end
    local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
    clients[1].request('textDocument/hover', params, function(err, result)
      if err or not result or not result.contents then
        vim.notify('[wordnet-lsp] No definition found', vim.log.levels.INFO)
        return
      end
      vim.lsp.util.open_floating_preview(
        vim.islist(result.contents) and result.contents or { result.contents },
        'markdown',
        { border = 'rounded', max_width = 80 }
      )
    end, bufnr)
  end, { desc = 'Show WordNet definition for word under cursor' })

  -- Debug command
  vim.api.nvim_create_user_command('WordNetDebug', function(cmd_opts)
    local word = cmd_opts.args
    if not word or #word == 0 then
      print('[WordNetDebug] Usage: :WordNetDebug <word>')
      return
    end
    local morph = require('wordnet-lsp.morphology')
    local wn = require('wordnet-lsp.wordnet')
    local candidates = morph.get_candidate_lemmas(word)
    print('[WordNetDebug] Candidates for "' .. word .. '": ' .. vim.inspect(candidates))
    local function test_query(label, ptrs)
      print('[WordNetDebug] --- ' .. label .. '---')
      for _, c in ipairs(candidates) do
        local ok, result = pcall(wn.get_similar_words_for_word, c, 3, ptrs, 2)
        if not ok then
          print('  "' .. c .. '" → ERROR: ' .. tostring(result))
        else
          print('  "' .. c .. '" → ' .. #result .. ' results: ' .. vim.inspect({ unpack(result, 1, 5) }))
          if #result > 5 then print('    ... (' .. #result .. ' total)') end
        end
      end
    end
    test_query('Synonyms (&,^)', { '&', '^' })
    test_query('Antonyms (!)', { '!' })
  end, { nargs = 1, desc = 'Debug WordNet queries for a word' })

end

return M
