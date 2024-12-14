local M = {}

M.setup = function(opts)
	-- .setup() for devcon.
	--
	-- Validates some devcon options and bootstraps the plugin.

	-- Defaults and aliases.
	opts = opts or {}
	local s = {}
	M.settings = s

	-- Parse, detect or set default the container runtime command.
	s.cli = opts.cli
	if not s.cli then
		s.cli = 'docker'
		local podman_v = io.popen("podman -v 2>/dev/null")
		local podman_v_read = podman_v and podman_v:read(1) == "p" or false
		if podman_v_read then
			s.cli = 'podman'
		end
	end

	-- Require lsp_servers setting.
	if opts.lsp_servers then
		s.lsp_servers = opts.lsp_servers
	else
		M.settings = nil
		error("lsp_servers is required by devcon.setup() .")
	end

	-- Parse or set default chained commands setting.
	s.chain_write = opts.chain_write or false
	s.chain_build = opts.chain_build or false
	s.chain_setup = opts.chain_setup or false
	s.setup_on_load = opts.setup_on_load or true

	-- For each lspconfig server ...
	for server, sopts in pairs(s.lsp_servers) do
		-- Require root_dir setting.
		if not sopts.root_dir then
			M.settings = nil
			error("root_dir is required for server '" .. server .. "' int devcon.setup() .")
		end

		-- Make root_dir absolute if it is not.
		if sopts.root_dir:sub(1, 1) ~= "/" then
			local pwd_cmd = io.popen("pwd")
			if not pwd_cmd then
				M.settings = nil
				error("Error calling 'pwd' to create an absolute path.")
			else
				local podman_cmd_read = pwd_cmd:read("*l")
				sopts.root_dir = (
					podman_cmd_read
					.. "/"
					.. sopts.root_dir
				)
			end
		end

		-- Force root_dir to be a "realpath".
		local realpath_cmd = io.popen("realpath " .. sopts.root_dir)
		if not realpath_cmd then
			M.settings = nil
			error("Error calling 'realpath' to create an real path.")
		end
		sopts.root_dir = realpath_cmd:read("*l")

		-- Parse or set default template setting.
		if not sopts.template then
			sopts.template = "alpine/" .. server
		end

		-- Parse or set default base_image setting.
		if not sopts.base_image then
			local project_dir_name = sopts.root_dir:gsub('.*%/', '')
			sopts.base_image = project_dir_name
		end

		-- Parse or set default base_tag setting.
		if not sopts.base_tag then
			s.base_tag = 'latest'
		end

		-- Parse or set default containerfile setting.
		if not sopts.containerfile then
			sopts.containerfile = 'Dockerfile.' .. server .. '.devcon'
		end

		-- Parse or set default devcon_tag setting.
		if not sopts.devcon_tag then
			sopts.devcon_tag = 'devcon'
		end

		-- Check each dir in extra_dirs setting exists.
		if sopts.extra_dirs then
			for _, dir in pairs(sopts.extra_dirs) do
				local s_realpath_cmd = io.popen("realpath " .. dir)
				if not s_realpath_cmd then
					M.settings = nil
					error("Error calling 'realpath' to create an real path.")
				end
				local s_realpath = s_realpath_cmd:read("*l")
				local test_dir = os.execute("test -d " .. s_realpath)
				if test_dir ~= 0 then
					M.settings = nil
					error("Directory '" .. dir .. "' for server '" .. server .. "' does not exists.")
				end
			end
		else
			sopts.extra_dirs = {}
		end

		-- Parse or set default config setting.
		if not sopts.config then
			sopts.config = {}
		end
	end

	-- Create Neovim user commands.
	vim.api.nvim_create_user_command('DevConWrite', M.devconwrite, {})
	vim.api.nvim_create_user_command('DevConBuild', M.devconbuild, {})
	vim.api.nvim_create_user_command('DevConSetup', M.devconsetup, {})

	-- Chain calls to other devcon commands.
	if s.chain_write then
		M.devconwrite()
	elseif s.setup_on_load then
		M.devconsetup()
	end
end

M.devconwrite = function()
	-- Write Dockerfile/Containerfile files from a library of templates.

	-- Require and alias M.settings .
	if not M.settings then
		error("Call require('devcon').setup() first.")
	end
	local s = M.settings

	-- TODO: Create the files ...

	-- Chain call to other devcon commands.
	if s.chain_build then
		M.devconbuild(true)
	end
end

M.devconbuild = function(silent)
	-- Issue a docker/podman build command for each LSP container.

	-- Require and alias M.settings .
	if not M.settings then
		error("Call require('devcon').setup() first.")
	end
	local s = M.settings

	-- Check if the proper containerfiles are available.
	for _, soptst in pairs(s.lsp_servers) do
		local test_containerfile = os.execute("test -e " .. soptst.containerfile)
		if test_containerfile ~= 0 then
			error("containerfile " .. soptst.containerfile .. " doesn't exists. Maybe try :DevConWrite first.")
		end
	end

	-- For each server create terminal windows for the build commands.
	local last_win = 0
	for _, sopts in pairs(s.lsp_servers) do
		-- Prepare the build command.
		local full_image_name =
				sopts.base_image .. ":" .. sopts.devcon_tag
		local cmd = {
			s.cli, "build",
			"-t", full_image_name,
			"-f", sopts.containerfile,
			"."
		}

		-- Issue the command in newly created buffers and windows.
		local b = vim.api.nvim_create_buf(silent, true)
		local c = vim.api.nvim_open_term(b, {})
		if not silent and last_win == 0 then
			last_win = vim.api.nvim_open_win(b, true, {
				vertical = true,
				win = last_win,
				style = 'minimal'
			})
		else
			if not silent then
				last_win = vim.api.nvim_open_win(b, false, {
					win = last_win,
					style = 'minimal'
				})
			end
		end
		vim.system(cmd, {
			stdout = function(_, data)
				vim.schedule(function()
					vim.api.nvim_chan_send(c, data or "")
				end)
			end,
			stderr = function(_, data)
				vim.schedule(function()
					vim.api.nvim_chan_send(c, data or "")
				end)
			end
		}, function(obj)
			vim.schedule(function()
				vim.api.nvim_chan_send(c, obj.stdout or "")
				vim.api.nvim_chan_send(c, obj.stderr or "")
			end)
		end)
	end

	-- Chain call to other devcon commands.
	if s.chain_setup then
		M.devconsetup()
	end
end

M.devconsetup = function()
	-- Require and call 'lspconfig'[SERVER].setup() for each of the
	-- configured (SERVER)s.
	--
	-- This is the core function of the plugin. Normal lspconfig cmd's
	-- are transformed to docker/podman run commands here. Also, the
	-- proper volumes are added here.

	-- Require and alias M.settings .
	if not M.settings then
		error("Call require('devcon').setup() first.")
	end
	local s = M.settings

	-- Check image exists for all configured servers
	for _, soptst in pairs(s.lsp_servers) do
		local full_image_name = soptst.base_image .. ":" .. soptst.devcon_tag
		local test_image = os.execute(s.cli .. " image exists " .. full_image_name)
		if test_image ~= 0 then
			error(
				"Image " .. full_image_name .. " doesn't exists."
				.. "Maybe try :DevConBuild first."
			)
		end
	end

	-- Call LSP config for each configured server.
	for server, sopts in pairs(s.lsp_servers) do
		local full_image_name = sopts.base_image .. ":" .. sopts.devcon_tag

		local lsp_cmd = {
			s.cli,
			"run",
			"--rm",
			"-i",
			"-v",
			sopts.root_dir .. ':' .. sopts.root_dir,
			"-w",
			sopts.root_dir
		}
		for _, extra_dir in pairs(sopts.extra_dirs) do
			table.insert(lsp_cmd, "-v")
			table.insert(lsp_cmd, extra_dir .. ':' .. extra_dir)
		end
		table.insert(lsp_cmd, full_image_name)
		local lsp_config = sopts.config
		lsp_config['root_dir'] = sopts.root_dir
		lsp_config['cmd'] = lsp_cmd

		require 'lspconfig'[server].setup(lsp_config)
	end
end

return M
