# devcon.nvim

> ⚠⚠ This project has been archived in favor of
> [safer](https://github.com/fjfnaranjo/safer).
> It uses a different strategy to achieve a similar result.

> ⚠ This is currently a work in progress. I still have to improve the
> documentation and add support for more LSP servers.

DevCon adds an extra support layer to Neovim for running LSP servers in
containers.

```
 | Neovim's |   |    Optional    |   |        |   | Container |
 |   LSP    |-->| nvim-lspconfig |-->| DevCon |-->|  runtime  |
 |  client  |   |  (recommended) |   |        |   |    CLI    |
```

## Enable LSP server management

To use DevCon, you may want to enable project scoped settings support
using `set exrc` (or any other option).

```lua
require('devcon').setup({
  lsp_servers = {
    lua_ls = {
      root_dir = '/some/path/lua/project',
    }
  }
})
```

Check the full documentation in [the docs](doc/devcon.txt).
