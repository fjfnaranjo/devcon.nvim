local M = {}

--- Validates devcon plugin options and bootstraps the LSP servers.
M.setup = function(opts)
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
		vim.print("lsp_servers is required by devcon .")
		return
	end

	-- If root_dir is specified at this level, normalize it.
	if opts.root_dir then
		opts.root_dir = vim.fs.normalize(opts.root_dir)
	end

	-- Guess docker/podman arch is not specified.
	s.arch = opts.arch
	if not s.arch then
		local docker_cli_cmd = s.cli .. " info --format '{{ .Server.Architecture }}' 2>/dev/null"
		local docker_shell = io.popen(docker_cli_cmd)
		if docker_shell then
			s.arch = docker_shell:read("*l")
			docker_shell:close()
		end
		if not s.arch then
			local podman_cli_cmd = s.cli .. " info --format '{{ .Host.Arch }}' 2>/dev/null"
			local podman_shell = io.popen(podman_cli_cmd)
			if podman_shell then
				s.arch = podman_shell:read("*l")
				podman_shell:close()
			end
			if s.arch:len()<1 then
				M.settings = nil
				vim.print(
					"Cannot determine container runtime architecture using '"
					.. s.cli .. " info' commands."
				)
				return
			end
		end
	end

	-- For each lspconfig server ...
	for server, sopts in pairs(s.lsp_servers) do
		-- Require root_dir setting.
		if not sopts.root_dir then
			if not opts.root_dir then
				M.settings = nil
				vim.print("root_dir is required by devcon for server '" .. server .. "' setup.")
				return
			else
				sopts.root_dir = opts.root_dir
			end
		else
			sopts.root_dir = vim.fs.normalize(sopts.root_dir)
		end

		-- Take config_lsp function from plugin opts or from server opts.
		if not sopts.config_lsp and opts.config_lsp then
			sopts.config_lsp = opts.config_lsp
		end

		-- Parse or set default template setting.
		if not sopts.template then
			sopts.template = server .. "/alpine/" .. s.arch
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
				local normalized = vim.fs.normalize(dir)
				if not vim.fn.isdirectory(normalized) then
					M.settings = nil
					vim.print(
						"Directory '" .. dir .. "' for server '" .. server
						.. "' does not exists or can not be normalized by VIM."
					)
					return
				end
			end
		else
			sopts.extra_dirs = {}
		end

		-- Parse or set default config setting.
		if not sopts.config then
			sopts.config = sopts.config_lsp() or {}
		end
	end

	-- Writes Dockerfile/Containerfile files from a library of templates.

	-- For each lspconfig server ...
	for _, sopts in pairs(s.lsp_servers) do
		-- Get template contents.
		local template_content = ""
		local plugin_path = debug.getinfo(1, "S").source:match("@(.*/)")
		local arch_path = (
			plugin_path
			.. "../../templates/"
			.. sopts.template
		)
		local arch_template = io.open(arch_path, 'rb')
		if arch_template then
			template_content = arch_template:read("*a")
			arch_template:close()
		else
			local any_path = (
				plugin_path
				.. "../templates/"
				.. sopts.template:match("(.+)/[^/]+$")
				.. "/any"
			)
			local any_template = io.open(any_path, 'rb')
			if any_template then
				template_content = any_template:read("*a")
				any_template:close()
			else
				vim.print(
					"Cannot read template file. Tried: "
					.. arch_path .. " and " .. any_path .. " ."
				)
				return
			end
		end

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

	-- Issues a docker/podman build command for each LSP container.
	local silent = true

	-- Check if the proper containerfiles are available.
	for _, soptst in pairs(s.lsp_servers) do
		if not vim.uv.fs_stat(soptst.containerfile) then
			vim.print("containerfile " .. soptst.containerfile .. " doesn't exists.")
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

	-- Requires and call 'lspconfig'[SERVER].setup() for each of the
	-- configured (SERVER)s.
	--
	-- This is the core function of the plugin. Normal lspconfig cmd's
	-- are transformed to docker/podman run commands here. Also, the
	-- proper volumes are added here.

	-- Check image exists for all configured servers.
	for _, soptst in pairs(s.lsp_servers) do
		local full_image_name = soptst.devcon_image .. ":" .. soptst.devcon_tag
		local test_image = os.execute(s.cli .. " image inspect " .. full_image_name .. " 2>/dev/null")
		if test_image ~= 0 then
			vim.print("Image " .. full_image_name .. " doesn't exists.")
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
