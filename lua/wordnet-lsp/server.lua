--- In-process LSP server for WordNet.
--- Supports two server types:
---   "dictionary"  — completion only (word lookup)
---   "thesaurus"   — hover + code actions (synonym/antonym replacement)
---
--- Implements the vim.lsp.rpc.PublicClient interface.

local M = {}

--- Create the LSP server function for vim.lsp.start's cmd parameter.
--- @param server_type string "dictionary" or "thesaurus"
--- @return fun(dispatchers: vim.lsp.rpc.Dispatchers): vim.lsp.rpc.PublicClient
function M.create(server_type)
  --- The actual server function passed as `cmd` to vim.lsp.start.
  --- @param dispatchers vim.lsp.rpc.Dispatchers
  --- @return vim.lsp.rpc.PublicClient
  return function(dispatchers)
    local id = 0
    local closing = false

    return {
      request = function(method, params, callback)
        id = id + 1

        if method == 'initialize' then
          -- Build capabilities based on server type
          local capabilities = {
            textDocumentSync = 1, -- Full sync
            positionEncoding = 'utf-16',
          }

          -- Dictionary gets completion only
          if server_type == 'dictionary' then
            capabilities.completionProvider = {
              triggerCharacters = {},
              resolveProvider = true,
            }
          end

          -- Thesaurus gets hover, definition, references
          if server_type == 'thesaurus' then
            capabilities.hoverProvider = true
            capabilities.codeActionProvider = true
            capabilities.executeCommandProvider = {
              commands = { 'wordnet-lsp.open-picker' },
            }
          end

          callback(nil, { capabilities = capabilities }, id)

        elseif method == 'textDocument/completion' then
          local handler = require('wordnet-lsp.handlers.completion')
          handler.handle(params, server_type, function(err, result)
            callback(err, result, id)
          end)

        elseif method == 'completionItem/resolve' then
          local handler = require('wordnet-lsp.handlers.completion')
          handler.resolve(params, function(err, result)
            callback(err, result, id)
          end)

        elseif method == 'textDocument/hover' then
          local handler = require('wordnet-lsp.handlers.hover')
          handler.handle(params, function(err, result)
            callback(err, result, id)
          end)

        elseif method == 'textDocument/codeAction' then
          local handler = require('wordnet-lsp.handlers.code_action')
          handler.handle(params, function(err, result)
            callback(err, result, id)
          end)

      elseif method == 'workspace/executeCommand' then
          local handler = require('wordnet-lsp.handlers.code_action')
          handler.execute_command(params, function(err, result)
            callback(err, result, id)
          end)

      elseif method == 'shutdown' then
        callback(nil, nil, id)

        else
          -- Unknown method
          callback({
            code = -32601,
            message = 'Method not found: ' .. method,
          }, nil, id)
        end

        return true, id
      end,

      notify = function(method)
        if method == 'exit' then
          closing = true
          dispatchers.on_exit(0, 15)
        elseif method == 'initialized' then
          -- Client is ready — no action needed
        end
        return true
      end,

      is_closing = function()
        return closing
      end,

      terminate = function()
        closing = true
      end,
    }
  end
end

return M
