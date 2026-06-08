return {
	-- Custom screenshot integration
	{
		dir = vim.fn.stdpath("config") .. "/plugins/screenshot.nvim",
		name = "screenshot.nvim",
		event = "VeryLazy",
		config = function()
			require("screenshot").setup({
				local_screenshot_dir = "./images",
				global_screenshot_dir = vim.fn.stdpath("data") .. "/screenshots",
				keymaps = {
					interactive = "<leader>is", -- Take interactive screenshot image (local)
					fullscreen = "<leader>if", -- Take fullscreen screenshot image (local)
					interactive_global = "<leader>iS", -- Take interactive screenshot image (global)
					fullscreen_global = "<leader>iF", -- Take fullscreen screenshot image (global)
					check = "<leader>ic", -- Check screenshot image tool availability
					directory = "<leader>id", -- Open screenshot image directory
				},
			})
		end,
	},

	-- Inline image display with image.nvim
	{
		"3rd/image.nvim",
		build = false, -- Disable luarocks build to avoid dependency issues
		ft = { "markdown", "vimwiki", "norg" }, -- Only load for specific filetypes
		config = function()
			-- Check if image plugin is available
			local image_available, image = pcall(require, "image")
			if not image_available then
				vim.notify("image.nvim plugin not available, skipping image display setup", vim.log.levels.WARN)
				return
			end

			image.setup({
				backend = "kitty", -- Use Kitty graphics protocol (recommended)
				processor = "magick_cli", -- Use CLI ImageMagick (works with Nix ImageMagick)
				integrations = {
					markdown = {
						enabled = true,
						clear_in_insert_mode = false,
						download_remote_images = true,
						only_render_image_at_cursor = false,
						floating_windows = false,
						filetypes = { "markdown", "vimwiki" },
						resolve_image_path = function(document_path, image_path, fallback)
							-- Handle Hugo static images (absolute path /images/...)
							if image_path:sub(1, 8) == "/images/" then
								-- Try to find the project root (where blog/ is)
								local project_root = vim.fn.getcwd()
								-- Assuming we are in the root of lamt-nixconfig or inside blog/
								local possible_paths = {
									project_root .. "/blog/static" .. image_path,
									project_root .. "/static" .. image_path,
								}

								for _, path in ipairs(possible_paths) do
									if vim.fn.filereadable(path) == 1 then
										return path
									end
								end
							end

							return fallback(document_path, image_path)
						end,
					},
					neorg = {
						enabled = true,
						filetypes = { "norg" },
					},
					html = {
						enabled = false,
					},
					css = {
						enabled = false,
					},
				},
				max_width = nil,
				max_height = nil,
				max_width_window_percentage = nil,
				max_height_window_percentage = 50,
				window_overlap_clear_enabled = false,
				window_overlap_clear_ft_ignore = {
					"cmp_menu",
					"cmp_docs",
					"snacks_notif",
					"scrollview",
					"scrollview_sign",
				},
				editor_only_render_when_focused = false,
				hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif", "*.svg" },
				tmux_show_only_in_active_window = true,
			})

			-- Helper function to safely call image methods
			local function safe_image_call(method_name, ...)
				local success, result = pcall(function(...)
					if image and type(image[method_name]) == "function" then
						return image[method_name](...)
					else
						return false
					end
				end, ...)

				if not success then
					-- Silently ignore errors - the plugin will handle rendering internally
					return false
				end
				return result
			end

			-- Minimal "first load" insurance
			-- Only triggers once when entering a buffer to ensure kitty graphics are flushed
			vim.api.nvim_create_autocmd({ "BufWinEnter" }, {
				pattern = { "*.md", "*.markdown", "*.norg" },
				callback = function()
					vim.defer_fn(function()
						-- If image plugin is loaded, force a render pass
						if package.loaded["image"] then
							pcall(require("image").render)
						end
					end, 300)
				end,
			})

			-- Global toggle function (accessible to plugins)
			_G.toggle_image_display = function()
				if not image then
					return
				end

				-- The plugin API might change, so we wrap this safely
				local is_enabled = safe_image_call("is_enabled")

				if is_enabled then
					safe_image_call("disable")
					vim.notify("Image display disabled", vim.log.levels.INFO)
				else
					safe_image_call("enable")
					vim.defer_fn(function()
						safe_image_call("render")
					end, 100)
					vim.notify("Image display enabled", vim.log.levels.INFO)
				end
			end

			-- Add toggle keymap
			vim.keymap.set("n", "<leader>ti", function()
				if _G.toggle_image_display then
					_G.toggle_image_display()
				else
					vim.notify("Image display toggle not available", vim.log.levels.WARN)
				end
			end, { desc = "Toggle inline image display" })
		end,
	},
}
