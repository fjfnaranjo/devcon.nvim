# devcon.nvim

> ⚠ This is currently a work in progress. I still have to improve the
> documentation and add support for more LSP servers.

DevCon adds a simple support layer to Neovim for running LSP servers in
containers.

```
 | Neovim's |    |           |    |        |    | Container |
 |   LSP    |--->| lspconfig |--->| DevCon |--->|  runtime  |
 |  client  |    |           |    |        |    |    CLI    |
```

To use DevCon, first enable project scoped settings support using
`set exrc` (or any other option). Also, ideally, wrap your `on_attache`,
`capabilities` and other common LSP settings in a Lua config file so you
can use a function like this:

```lua
local mylspcfg = require('my_global_lsp_config')

require('devcon').setup({
  lsp_servers = {
    lua_ls = {
      root_dir = '/some/path/lua/project',
      config = mylspcfg.default_lsp_config({
        root_dir = '/some/path/lua/project'
      })
    }
  }
})
```

And that's it. Now, you have full support to generate a containerfile
with the command `DevConWrite`, build an image with `DevConBuild` and
inject the LSP config with `DevConSetup` to run the LSP inside the
container. You can also let the plugin calling this functions for you
:) .

Check the full documentation in [the docs](doc/devcon.txt).
