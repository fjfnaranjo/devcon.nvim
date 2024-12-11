local M = {}

M.setup = function(opts)
	opts = opts or {}
	local s = {}
	M.settings = s

	-- Require root_dir
	if opts.root_dir then
		s.root_dir = opts.root_dir
	else
		M.settings = nil
		error("root_dir is required by devcon.setup() .")
	end

	-- Make root_dir absolute if it is not
	if s.root_dir:sub(1, 1) ~= "/" then
		local pwd_cmd = io.popen("pwd")
		s.root_dir = (
			pwd_cmd:read("*l")
			.. "/"
			.. s.root_dir
		)
	end

	-- Force root_dir to be a "realpath"
	s.root_dir = io.popen("realpath " .. s.root_dir):read("*l")

	-- Parse or default base_image
	if opts.base_image then
		s.base_image = opts.base_image
	else
		local project_name = s.root_dir:gsub('.*%/', '')
		s.base_image = project_name
	end

	-- Parse or default base_tag
	if opts.base_tag then
		s.base_tag = opts.base_tag
	else
		s.base_tag = 'latest'
	end

	-- Process extra_dirs
	s.extra_dirs = {}
	if opts.extra_dirs then
		for _, dir in ipairs(opts.extra_dirs) do
			local realpath = io.popen("realpath " .. dir):read("*l")
			local test_dir = os.execute("test -d " .. realpath)
			if test_dir == 0 then
				table.insert(s.extra_dirs, realpath)
			else
				M.settings = nil
				error("Directory '" .. dir .. "' does not exists.")
			end
		end
	end

	-- Parse or default containerfile
	if opts.containerfile then
		s.containerfile = opts.containerfile
	else
		s.containerfile = 'Dockerfile.devcon'
	end

	-- Parse or default devcon_tag
	if opts.devcon_tag then
		s.devcon_tag = opts.devcon_tag
	else
		s.devcon_tag = 'devcon'
	end

	-- Parse or default lsp_servers
	if opts.lsp_servers then
		s.lsp_servers = opts.lsp_servers
	else
		M.settings = nil
		error("lsp_servers is required by devcon.setup() .")
	end

	-- Set or detect CLI
	s.cli = opts.cli
	if not s.cli then
		s.cli = 'docker'
		local podman_v = io.popen("podman -v 2>/dev/null")
		if podman_v:read(1) then
			s.cli = 'podman'
		end
	end

	-- Setup LSP servers
	local lsp_cmd = {
		s.cli,
		"run",
		"--rm",
		"-i",
		"-v",
		s.root_dir .. ':' .. s.root_dir,
		"-w",
		s.root_dir
	}
	for _, extra_dir in ipairs(s.extra_dirs) do
		table.insert(lsp_cmd, "-v")
		table.insert(lsp_cmd, extra_dir .. ':' .. extra_dir)
	end
	table.insert(lsp_cmd, s.base_image .. ":" .. s.devcon_tag)

	for lsp_server in pairs(s.lsp_servers) do
		local lsp_extra_args = s.lsp_servers[lsp_server]
		local lsp_setup = {
			root_dir = s.root_dir,
			cmd = lsp_cmd
		}
		for k, v in pairs(lsp_extra_args) do lsp_setup[k] = v end
		require 'lspconfig'[lsp_server].setup(lsp_setup)
	end
end

M.devconwrite = function()
	if not M.settings then
		error("Call require('devcon').setup() first.")
	end
end
vim.api.nvim_create_user_command('DevConWrite', M.devconwrite, {})

return M
