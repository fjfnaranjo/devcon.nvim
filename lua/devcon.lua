local core = require("devcon/core")

local function setup(opts)
	-- Automatically setup LSPs.
	if not opts.lazy then
		core.setup(opts)
	else
		-- Alternatively, create a Neovim user command to setup the LSPs manually.
		vim.api.nvim_create_user_command("DevConSetup", function()
			core.setup(opts)
		end, {})
	end
end

return { setup = setup }
