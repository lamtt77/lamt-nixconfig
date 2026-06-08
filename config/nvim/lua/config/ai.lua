-- Helper function to get secrets from pass or environment variables
local secret_cache = {} -- Cache: {secret_ref: {value, timestamp}}
local CACHE_TTL = 300 -- 5 minutes TTL

local function get_secret(secret_ref)
	-- Check cache first
	if secret_cache[secret_ref] then
		local cached = secret_cache[secret_ref]
		if os.time() - cached.timestamp < CACHE_TTL then
			return cached.value
		else
			secret_cache[secret_ref] = nil -- Expired, remove
		end
	end

	local secret = nil

	if secret_ref:match("^pass://") then
		-- SECURITY: Properly escape the path to prevent injection
		local path = secret_ref:gsub("^pass://", "")

		-- Use vim.system (NVIM 0.10+) for better control/timeout
		local obj = vim.system({ "pass", "show", path }, { text = true, timeout = 5000 }):wait()
		if obj.code == 0 then
			secret = obj.stdout:gsub("\n+$", "")
			if secret == "" then secret = nil end
		end
	else
		-- Fallback to environment variable
		secret = os.getenv(secret_ref)
	end

	-- Cache the result (including nil for failed lookups)
	secret_cache[secret_ref] = {
		value = secret,
		timestamp = os.time(),
	}

	return secret
end

-- Centralized secret management for Avante
local function initialize_secrets()
	local secrets = {
		GEMINI_API_KEY = "pass://ai/GEMINI_API_KEY",
		ANTHROPIC_API_KEY = "pass://ai/ANTHROPIC_API_KEY",
		XAI_API_KEY = "pass://ai/XAI_API_KEY",
		-- Add other secrets here as needed
		-- OPENAI_API_KEY = "pass://ai/OPENAI_API_KEY",
	}

	for env_name, secret_ref in pairs(secrets) do
		local secret = get_secret(secret_ref)
		if secret then
			vim.env["AVANTE_" .. env_name] = secret
		end
	end
end

-- Initialize Avante secrets lazily on first use
local secrets_initialized = false
local function ensure_secrets()
	if not secrets_initialized then
		initialize_secrets()
		secrets_initialized = true
	end
end

-- Global versions for testing
_G.get_secret = get_secret
_G.ensure_secrets = ensure_secrets

return {
	-- GitHub Copilot Lua
	{
		"zbirenbaum/copilot.lua",
		cmd = "Copilot",
		event = "InsertEnter",
		config = function()
			require("copilot").setup({
				suggestion = { enabled = false },
				panel = {
					enabled = true,
					auto_refresh = true,
					keymap = {
						jump_prev = "[[",
						jump_next = "]]",
						accept = "<CR>",
						refresh = "gr",
						open = "<M-Space>",
					},
				},
			})
		end,
	},

	-- opencode AI assistant integration
	{
		"NickvanDyke/opencode.nvim",
		dependencies = {
			-- Recommended for better prompt input
			{ "folke/snacks.nvim", lazy = false, priority = 1000, opts = { input = { enabled = true } } },
		},
		config = function()
			-- Opencode global configuration
			vim.g.opencode_opts = {
				port = 11434, -- Fixed port for opencode server to fix select() connectivity
				window = {
					position = "right", -- Force opencode to open on the right side
					width = 80, -- Set a reasonable width
				},
				terminal = {
					cmd = "opencode",
				},
				-- See lua/opencode/config.lua for available options
			}
		end,
		keys = {
			-- Recommended keymaps for opencode integration
			{
				"<leader>oA",
				function()
					require("opencode").ask()
				end,
				desc = "Ask opencode",
			},
			{
				"<leader>oa",
				function()
					require("opencode").ask("@cursor: ")
				end,
				desc = "Ask opencode about this",
				mode = "n",
			},
			{
				"<leader>oa",
				function()
					require("opencode").ask("@selection: ")
				end,
				desc = "Ask opencode about selection",
				mode = "v",
			},
			{
				"<leader>ot",
				function()
					require("opencode").toggle()
				end,
				desc = "Toggle embedded opencode",
			},
			{
				"<leader>on",
				function()
					require("opencode").command("session_new")
				end,
				desc = "New session",
			},
			{
				"<leader>oy",
				function()
					require("opencode").command("messages_copy")
				end,
				desc = "Copy last message",
			},
			{
				"<C-M-v>",
				function()
					require("opencode").command("messages_half_page_up")
				end,
				desc = "Scroll messages up",
			},
			{
				"<C-M-S-v>",
				function()
					require("opencode").command("messages_half_page_down")
				end,
				desc = "Scroll messages down",
			},
			{
				"<leader>op",
				function()
					require("opencode").select()
				end,
				desc = "Select prompt",
				mode = { "n", "v" },
			},
			-- Example: keymap for custom prompt
			{
				"<leader>oe",
				function()
					require("opencode").prompt("Explain @cursor and its context")
				end,
				desc = "Explain code near cursor",
			},
		},
	},

	-- Avante AI assistant
	{
		"yetone/avante.nvim",
		build = vim.fn.has("win32") ~= 0
				and "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false"
			or "make",
		cmd = { "AvanteToggle", "AvanteAsk", "AvanteEdit" },
		version = false, -- Never set this value to "*"! Never!
		config = function(_, opts)
			-- Initialize secrets when Avante is actually loaded
			ensure_secrets()
			require("avante").setup(opts)
		end,
		---@module 'avante.config'
		---@type table
		opts = {
			instructions_file = "avante.md",
			provider = "gemini",
			selector = {
				provider = "telescope",
			},
			providers = {
				gemini = {
					-- API key is set via AVANTE_GEMINI_API_KEY environment variable
					timeout = 30000,
				},
				copilot = {
					timeout = 30000,
				},
				claude = {
					endpoint = "https://api.anthropic.com",
					model = "claude-sonnet-4-20250514",
					timeout = 30000, -- Timeout in milliseconds
					extra_request_body = {
						temperature = 0.75,
						max_tokens = 20480,
					},
				},
				moonshot = {
					endpoint = "https://api.moonshot.ai/v1",
					model = "kimi-k2-0711-preview",
					timeout = 30000, -- Timeout in milliseconds
					extra_request_body = {
						temperature = 0.75,
						max_tokens = 32768,
					},
				},
			},
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			"nvim-telescope/telescope.nvim",
			"saghen/blink.cmp",
			"nvim-tree/nvim-web-devicons",
			"zbirenbaum/copilot.lua",
		},
	},

	-- Avante keybindings (defined separately to ensure plugin is loaded)
	{
		"yetone/avante.nvim",
		keys = {
			{ "<leader>at", "<cmd>AvanteToggle<CR>", desc = "Toggle Avante" },
			{ "<leader>aa", "<cmd>AvanteAsk<CR>", desc = "Avante ask", mode = { "n", "v" } },
			{ "<leader>ae", "<cmd>AvanteEdit<CR>", desc = "Avante edit", mode = { "n", "v" } },
		},
	},
}
