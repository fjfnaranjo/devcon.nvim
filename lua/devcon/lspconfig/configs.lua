local function lsp_cmd_init(cli, root_dir)
	return {
		cli,
		"run",
		"--rm",
		"-i",
		"-v",
		root_dir .. ':' .. root_dir,
		"-w",
		root_dir
	}
end

local function lsp_cmd_add_dir(lsp_cmd, extra_dir)
	table.insert(lsp_cmd, "-v")
	table.insert(lsp_cmd, extra_dir .. ':' .. extra_dir)
end

local function lsp_cmd_add_image(lsp_cmd, sopts)
	local full_image_name = sopts.devcon_image .. ":" .. sopts.devcon_tag
	table.insert(lsp_cmd, full_image_name)
end

local function lsp_cmd_builder(s, sopts)
	local lsp_cmd = lsp_cmd_init(s.cli, sopts.root_dir)
	for _, extra_dir in pairs(sopts.extra_dirs) do
		lsp_cmd_add_dir(lsp_cmd, extra_dir)
	end
	lsp_cmd_add_image(lsp_cmd, sopts)
	return lsp_cmd
end

local function lsp_setup(s, server, sopts, lsp_config)
	local lsp_cmd = lsp_cmd_builder(s, sopts)
	lsp_config['cmd'] = lsp_cmd
	require 'lspconfig'[server].setup(lsp_config)
end

return {
	lsp_cmd_init = lsp_cmd_init,
	lsp_cmd_add_dir = lsp_cmd_add_dir,
	lsp_cmd_add_image = lsp_cmd_add_image,
	lsp_cmd_builder = lsp_cmd_builder,
	lsp_setup = lsp_setup
}
