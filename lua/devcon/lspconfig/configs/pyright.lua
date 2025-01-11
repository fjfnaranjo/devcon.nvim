local generic_config = require('devcon/lspconfig/configs')

local function lsp_setup(s, server, sopts, lsp_config)
	if lsp_config.pythonpath then
		table.insert(sopts.extra_dirs, lsp_config.pythonpath)
	end
	local lsp_cmd = generic_config.lsp_cmd_builder(s, sopts)
	lsp_config['cmd'] = lsp_cmd
	require'lspconfig'.pyright.setup(lsp_config)
	--if lsp_config.pythonpath then
	--	vim.cmd('PyrightSetPythonPath ' .. lsp_config.pythonpath)
	--end
end

return { lsp_setup = lsp_setup }
