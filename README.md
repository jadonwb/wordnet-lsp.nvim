# wordnet-lsp.nvim

An in-process LSP server for Neovim that provides WordNet-powered
word completions, definitions, synonyms, and antonyms.

https://github.com/jadonwb/wordnet-lsp.nvim

## Features

Two independent LSP servers attach to your buffers:

| Server | Provides |
|---|---|
| `wordnet-dictionary` | **Word completion** — suggestions as you type |
| `wordnet-thesaurus` | **Hover** — definition + relations on `K`<br>**Code actions** — browse and replace with synonyms/antonyms |

## Installation

### lazy.nvim

```lua
{
  'jadonwb/wordnet-lsp.nvim',
  config = function()
    require('wordnet-lsp').setup()
  end,
}
```

## Default Configuration

```lua
require('wordnet-lsp').setup({

  -- ── Startup ──────────────────────────────────
  --- If false, use :WordNetLspStart / :WordNetLspToggle manually.
  auto_start = true,
  --- Filetypes to auto-attach to.
  filetypes = { 'text', 'markdown', 'txt' },

  -- ── Dictionary server (word completion) ─────
  dictionary = {
    enabled = true,
    --- Min chars before querying WordNet. Keywords <= this are skipped.
    --- Lower = triggers sooner (more noise, slightly slower).
    --- Higher = triggers later (less noise, faster).
    search_threshold = 3,
  },

  -- ── Thesaurus server (hover + code actions) ──
  thesaurus = {
    enabled = true,

    hover = {
      --- Buffer-local keymap for wordnet-only hover.
      --- Does not replace K. nil = no separate mapping.
      keymap = nil, -- e.g. '<Leader>wh'
      --- Try lemmatized forms (started → start) when exact lookup fails.
      use_morphology = true,
      --- WordNet pointer symbols shown in the definition popup.
      definition_pointers = { '!', '&', '^', '@', '~' },
    },

    code_actions = {
      --- Show lemmatized synonym/antonym options.
      --- e.g. "start" (from "started").
      use_morphology = true,
      --- Max replacement candidates in the picker.
      max_results = 100,
      --- chars below → exact match, above → fuzzy match.
      search_threshold = 3,
      --- Recursive synset traversal depth. Higher = more results, slower.
      similarity_depth = 2,
    },
  },
})
```

### Pointer symbols reference

| Symbol | Meaning |
|---|---|
| `!` | Antonym (lexical opposite) |
| `&` | Similar to |
| `^` | Also see |
| `@` | Hypernym (X is a kind of Y) |
| `~` | Hyponym (Y is a kind of X) |
| `@i` | Instance Hypernym |
| `~i` | Instance Hyponym |
| `*` | Entailment |
| `>` | Cause |
| `+` | Derivationally related form |

## Commands

| Command | Action |
|---|---|
| `:WordNetLspStart` | Attach servers to current buffer |
| `:WordNetLspStop` | Detach from current buffer |
| `:WordNetLspToggle` | Toggle on/off |
| `:WordNetHover` | WordNet-only definition hover |
| `:WordNetDebug <word>` | Show raw WordNet query results for debugging |

## Roadmap / Stretch Goals

- [ ] **Advanced picker integration** — Telescope / snacks.picker source with
      definition preview while browsing synonyms/antonyms.
- [ ] **In-memory WordNet index** — load the 7 MB index at startup for
      zero-disk-I/O completion (currently uses disk-based binary search).
- [ ] **Multi-word selection** — handle phrases and compound words in code
      actions and hover.
- [ ] **Custom completion icons** — register WordNet-specific
      `CompletionItemKind` with Nerd Font icons and highlight colors
      (like the reference blink-cmp-words plugin).
- [ ] **Virtual text preview** — show a synonym preview inline while
      browsing code actions.

## Credits

- **WordNet 3.0** — Princeton University "About WordNet."
  https://wordnet.princeton.edu/
- **fzy** — fuzzy string matching library (bundled, pure Lua implementation).
  https://github.com/romgrk/fzy-lua
- **blink-cmp-words** — reference plugin and WordNet engine design.
  https://github.com/archie-judd/blink-cmp-words

## License

Plugin code: **MIT** — see [LICENSE](./LICENSE).  
WordNet 3.0 data files (`data/`): Copyright 2006 by Princeton University.  
Used under the WordNet License.
