local M = {}

M.devconsetup = function()
	-- Calls lspconfig.server.setup() for each of the configured servers
	--
	-- This is the core function of the plugin. Normal lspconfig cmd's
	-- are transformed to docker/podman run commands here.

	-- Require and alias M.settings
	if not M.settings then
		error("Call require('devcon').setup() first.")
	end
	local s = M.settings

	-- For each configured server ...
	for server, sopts in pairs(s.lsp_servers) do
		--- ... checks that the image is already available ...
		local full_image_name = sopts.base_image .. ":" .. sopts.devcon_tag
		local test_image = os.execute(s.cli .. " image exists " .. full_image_name)
		if test_image ~= 0 then
			error(
				"Image " .. full_image_name .. " doesn't exists."
				.. "Maybe try :DevConBuild first."
			)
		end

		-- ... and build LSP config to call setup()
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
vim.api.nvim_create_user_command('DevConSetup', M.devconsetup, {})

M.setup = function(opts)
	-- .setup() for devcon
	--
	-- Mainly validates devcon options.

	-- Defaults and aliases
	opts = opts or {}
	local s = {}
	M.settings = s

	-- Parse or default/detect CLI
	s.cli = opts.cli
	if not s.cli then
		s.cli = 'docker'
		local podman_v = io.popen("podman -v 2>/dev/null")
		if podman_v:read(1) then
			s.cli = 'podman'
		end
	end

	-- Require lsp_servers
	if opts.lsp_servers then
		s.lsp_servers = opts.lsp_servers
	else
		M.settings = nil
		error("lsp_servers is required by devcon.setup() .")
	end

	-- For each lspconfig server
	for server, sopts in pairs(s.lsp_servers) do
		-- Require root_dir
		if not sopts.root_dir then
			M.settings = nil
			error("root_dir is required for server '" .. server .. "' int devcon.setup() .")
		end

		-- Make root_dir absolute if it is not
		if sopts.root_dir:sub(1, 1) ~= "/" then
			local pwd_cmd = io.popen("pwd")
			sopts.root_dir = (
				pwd_cmd:read("*l")
				.. "/"
				.. sopts.root_dir
			)
		end

		-- Force root_dir to be a "realpath"
		sopts.root_dir = io.popen("realpath " .. sopts.root_dir):read("*l")

		-- Parse or default template
		if not sopts.template then
			sopts.template = "alpine/" .. server
		end

		-- Parse or default base_image
		if not sopts.base_image then
			local project_dir_name = sopts.root_dir:gsub('.*%/', '')
			sopts.base_image = project_dir_name
		end

		-- Parse or default base_tag
		if not sopts.base_tag then
			s.base_tag = 'latest'
		end

		-- Parse or default containerfile
		if not sopts.containerfile then
			sopts.containerfile = 'Dockerfile.' .. server .. '.devcon'
		end

		-- Parse or default devcon_tag
		if not sopts.devcon_tag then
			sopts.devcon_tag = 'devcon'
		end

		-- Process extra_dirs
		if sopts.extra_dirs then
			for _, dir in pairs(sopts.extra_dirs) do
				local realpath = io.popen("realpath " .. dir):read("*l")
				local test_dir = os.execute("test -d " .. realpath)
				if test_dir ~= 0 then
					M.settings = nil
					error("Directory '" .. dir .. "' for server '" .. server .. "' does not exists.")
				end
			end
		else
			sopts.extra_dirs = {}
		end

		-- Parse or default config
		if not sopts.config then
			sopts.config = {}
		end
	end

	-- Call lspconfig.setups after devcon.setup
	M.devconsetup()
end

M.devconwrite = function()
	-- Writes the Dockerfile/Containerfile from a library of templates

	-- Require and alias M.settings
	if not M.settings then
		error("Call require('devcon').setup() first.")
	end
	local s = M.settings

	-- TODO: Create the files ...
end
vim.api.nvim_create_user_command('DevConWrite', M.devconwrite, {})

M.devconbuild = function()
	-- Issues a docker/podman build command for the LSP containers

	-- Require and alias M.settings
	if not M.settings then
		error("Call require('devcon').setup() first.")
	end
	local s = M.settings

	-- For each server we crate windows with the stdout of the command
	local last_win = 0
	for _, sopts in pairs(s.lsp_servers) do
		-- But first, we make sure that the Containerfile is available
		local test_containerfile = os.execute("test -e " .. sopts.containerfile)
		if test_containerfile ~= 0 then
			error("containerfile " .. sopts.containerfile .. " doesn't exists. Maybe try :DevConWrite first.")
		end

		-- Prepares the build command
		local full_image_name =
				sopts.base_image .. ":" .. sopts.devcon_tag
		local cmd = {
			s.cli, "build",
			"-t", full_image_name,
			"-f", sopts.containerfile,
			"."
		}

		-- Issues the command in new buffers/windows
		local b = vim.api.nvim_create_buf(false, true)
		local c = vim.api.nvim_open_term(b, {})
		if last_win == 0 then
			last_win = vim.api.nvim_open_win(b, true, {
				vertical = true,
				win = last_win,
				style = 'minimal'
			})
		else
			last_win = vim.api.nvim_open_win(b, false, {
				win = last_win,
				style = 'minimal'
			})
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
end
vim.api.nvim_create_user_command('DevConBuild', M.devconbuild, {})

return M
