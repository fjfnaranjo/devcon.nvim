local M = {}

M.setup = function(opts)
	opts = opts or {}

	M.settings = {}

	-- Set or detect CLI
	M.settings.cli = opts.cli
	if not M.settings.cli then
		M.settings.cli = 'docker'
		local podman_v = io.popen("podman -v 2>/dev/null")
		if podman_v:read(1) then
			M.settings.cli = 'podman'
		end
	end

end

M.devcon = function()
	if not M.settings then
		print("Call require('devcon').setup() first.")
	end
end
vim.api.nvim_create_user_command('DevCon', M.devcon, {})

return M
