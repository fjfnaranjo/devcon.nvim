local M = {}

M.setup = function()
	print("DevCon setup!")
end

M.devcon = function()
	print("DevCon!")
end
vim.api.nvim_create_user_command('DevCon', M.devcon, {})

return M
