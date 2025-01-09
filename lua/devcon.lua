local M = {}

--- Prepares paths for usage as docker/podman volumes.
local function normalize_path(path)
	-- If path is a function, let it pass.
	if type(path) == 'function' then
		return path
	end

	-- Make path absolute if it is not.
	if path:sub(1, 1) ~= "/" then
		local pwd_cmd = io.popen("pwd")
		if not pwd_cmd then
			M.settings = nil
			vim.print(
				"Error calling 'pwd' to create an absolute path for "
				.. path .. " ."
			)
			return
		else
			local podman_cmd_read = pwd_cmd:read("*l")
			pwd_cmd:close()
			path = (
				podman_cmd_read
				.. "/"
				.. path
			)
		end
	end

	-- Force path to be a "realpath".
	local realpath_cmd = io.popen("realpath " .. path)
	if not realpath_cmd then
		M.settings = nil
		vim.print(
			"Error calling 'realpath' to create an real path from "
			.. path .. " ."
		)
		return
	end
	path = realpath_cmd:read("*l")
	realpath_cmd:close()

	return path
end

--- Validates devcon plugin options and bootstraps the plugin.
M.setup = function(opts)
	-- Defaults and aliases.
	opts = opts or {}
	local s = {}
	M.settings = s

	-- Parse, detect or set default the container runtime command.
	s.cli = opts.cli
	if not s.cli then
		s.cli = 'docker'
		local podman_v = io.popen("podman -v 2>/dev/null")
		if podman_v then
			local podman_v_read = podman_v:read(1) == "p" or false
			podman_v:close()
			if podman_v_read then
				s.cli = 'podman'
			end
		end
	end

	-- Require lsp_servers setting.
	s.lsp_servers = opts.lsp_servers
	if not opts.lsp_servers or type(opts.lsp_servers) ~= 'table' then
		M.settings = nil
		vim.print("lsp_servers is required by devcon.setup() .")
		return
	end

	-- Parse or set default chained commands setting.
	s.chain_write = opts.chain_write or false
	s.chain_build = opts.chain_build or false
	s.chain_setup = opts.chain_setup or false
	s.setup_on_load = opts.setup_on_load or true

	-- If root_dir is specified at this level, filter it.
	if opts.root_dir then
		opts.root_dir = normalize_path(opts.root_dir)
	end

	-- For each lspconfig server ...
	for server, sopts in pairs(s.lsp_servers) do
		-- Require root_dir setting.
		if not sopts.root_dir then
			if not opts.root_dir then
				M.settings = nil
				vim.print("root_dir is required for server '" .. server .. "' int devcon.setup() .")
				return
			else
				sopts.root_dir = opts.root_dir
			end
		else
			sopts.root_dir = normalize_path(sopts.root_dir)
		end

		-- Take config_lsp function from root or from here.
		if not sopts.config_lsp and opts.config_lsp then
			sopts.config_lsp = opts.config_lsp
		end

		-- Parse or set default template setting.
		if not sopts.template then
			sopts.template = "alpine/" .. server
		end

		-- Parse or set default devcon_image setting.
		local project_dir_name = sopts.root_dir:gsub('.*%/', '')
		if not sopts.devcon_image then
			sopts.devcon_image = project_dir_name
		end

		-- Parse or set default devcon_tag setting.
		if not sopts.devcon_tag then
			sopts.devcon_tag = 'devcon'
		end

		-- Parse or set default containerfile setting.
		if not sopts.containerfile then
			sopts.containerfile = 'Dockerfile.' .. server .. '.devcon'
		end

		-- Check each dir in extra_dirs setting exists.
		if sopts.extra_dirs then
			for _, dir in pairs(sopts.extra_dirs) do
				local s_realpath_cmd = io.popen("realpath " .. dir)
				if not s_realpath_cmd then
					M.settings = nil
					vim.print("Error calling 'realpath' to create an real path.")
					return
				end
				local s_realpath = s_realpath_cmd:read("*l")
				s_realpath_cmd:close()
				local test_dir = os.execute("test -d " .. s_realpath)
				if test_dir ~= 0 then
					M.settings = nil
					vim.print("Directory '" .. dir .. "' for server '" .. server .. "' does not exists.")
					return
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

--- Writes Dockerfile/Containerfile files from a library of templates.
M.devconwrite = function()
	-- Require and alias M.settings .
	if not M.settings then
		vim.print("Call require('devcon').setup() first.")
		return
	end
	local s = M.settings

	-- For each lspconfig server ...
	for _, sopts in pairs(s.lsp_servers) do
		-- Get template contents.
		local plugin_path = debug.getinfo(1, "S").source:match("@(.*/)")
		local template_path = (
			plugin_path
			.. "../templates/"
			.. sopts.template
		)
		local template = io.open(template_path, 'rb')
		if not template then
			vim.print("Cannot read template file " .. template_path)
			return
		end
		local template_content = template:read("*a")
		template:close()

		-- Write containerfile.
		template_content, _ = template_content:gsub(
			'{{[ ]*base_image|([^ ]*)[ ]*}}',
			sopts.base_image or '%1'
		)
		template_content, _ = template_content:gsub(
			'{{[ ]*base_tag|([^ ]*)[ ]*}}',
			sopts.base_tag or '%1'
		)
		local template_file = io.open(sopts.containerfile, 'wb')
		if not template_file then
			vim.print("Cannot open containerfile to write " .. sopts.containerfile)
			return
		end
		template_file:write(template_content)
		template_file:close()
	end

	-- Chain call to other devcon commands.
	if s.chain_build then
		M.devconbuild(true)
	end
end

--- Issues a docker/podman build command for each LSP container.
---
--- @param silent boolean Don't show build buffer contents.
M.devconbuild = function(silent)
	-- Require and alias M.settings .
	if not M.settings then
		vim.print("Call require('devcon').setup() first.")
		return
	end
	local s = M.settings

	-- Check if the proper containerfiles are available.
	for _, soptst in pairs(s.lsp_servers) do
		local test_containerfile = os.execute("test -e " .. soptst.containerfile)
		if test_containerfile ~= 0 then
			vim.print("containerfile " .. soptst.containerfile .. " doesn't exists. Maybe try :DevConWrite first.")
			return
		end
	end

	-- For each server create terminal windows for the build commands.
	local last_win = 0
	for server, sopts in pairs(s.lsp_servers) do
		-- Prepare the build command.
		local full_image_name =
				sopts.devcon_image .. ":" .. sopts.devcon_tag
		local cmd = {
			s.cli, "build",
			"-t", full_image_name,
			"-f", sopts.containerfile,
			"."
		}

		-- Issue the command in newly created buffers and windows.
		local b = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(b, "devcon." .. server)
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

--- Requires and call 'lspconfig'[SERVER].setup() for each of the
--- configured (SERVER)s.
---
--- This is the core function of the plugin. Normal lspconfig cmd's
--- are transformed to docker/podman run commands here. Also, the
--- proper volumes are added here.
M.devconsetup = function()
	-- Require and alias M.settings .
	if not M.settings then
		vim.print("Call require('devcon').setup() first.")
		return
	end
	local s = M.settings

	-- Check image exists for all configured servers.
	for _, soptst in pairs(s.lsp_servers) do
		local full_image_name = soptst.devcon_image .. ":" .. soptst.devcon_tag
		local test_image = os.execute(s.cli .. " image inspect " .. full_image_name .. " 2>/dev/null")
		if test_image ~= 0 then
			vim.print(
				"Image " .. full_image_name .. " doesn't exists."
				.. "Maybe try :DevConBuild first."
			)
			return
		end
	end

	-- Call LSP config for each configured server.
	for server, sopts in pairs(s.lsp_servers) do
		local full_image_name = sopts.devcon_image .. ":" .. sopts.devcon_tag

		-- Build docker/podman run command.
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

		-- When calculating each server config, try to use a default
		-- configurer if specified or use passover.
		local lsp_config = {}
		local config_lsp = function(x) return x end
		if type(sopts.config_lsp) == "function" then
			config_lsp = sopts.config_lsp
		end
		local sopts_config = {}
		if sopts.config then
			sopts_config = sopts.config
		end
		lsp_config = config_lsp(sopts_config)

		-- Always populate config with root_dir if missing.
		if not lsp_config.root_dir then
			lsp_config['root_dir'] = sopts.root_dir
		end

		lsp_config['cmd'] = lsp_cmd
		require 'lspconfig'[server].setup(lsp_config)
	end
end

return M
