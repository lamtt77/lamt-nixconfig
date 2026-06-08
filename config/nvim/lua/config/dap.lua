-- DAP (Debug Adapter Protocol) Configuration
local dap_languages = {
  rust = {
    configurations = {
      {
        name = "Launch",
        type = "codelldb",
        request = "launch",
        program = function()
          -- Get default path from Cargo.toml or directory name
          local function get_default_binary()
            local cargo_toml = vim.fn.getcwd() .. "/Cargo.toml"
            if vim.fn.filereadable(cargo_toml) == 1 then
              for _, line in ipairs(vim.fn.readfile(cargo_toml)) do
                local name = line:match('name%s*=%s*"([^"]+)"')
                if name then
                  return vim.fn.getcwd() .. "/target/debug/" .. name
                end
              end
            end
            -- Fallback to directory name
            return vim.fn.getcwd() .. "/target/debug/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
          end

          local default_path = get_default_binary()
          local program_path = vim.fn.input("Path to executable: ", default_path, "file")

          -- Validate binary exists
          if vim.fn.filereadable(program_path) == 0 then
            vim.notify("Binary not found: " .. program_path, vim.log.levels.ERROR)
            return default_path -- Return default even if invalid, let user try again
          end

          return program_path
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
        args = {},
      },
      {
        name = "Debug test",
        type = "codelldb",
        request = "launch",
        program = function()
          return vim.fn.input("Path to test executable: ", vim.fn.getcwd() .. "/target/debug/deps/", "file")
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
        args = {},
      },
    },
  },
	go = {
		configurations = {
			{
				type = "delve",
				name = "Debug current file",
				request = "launch",
				program = "${file}",
				cwd = "${fileDirname}",
				outputMode = "remote",
			},
			{
				type = "delve",
				name = "Debug package",
				request = "launch",
				program = "${fileDirname}",
				cwd = "${fileDirname}",
				outputMode = "remote",
			},
			{
				type = "delve",
				name = "Debug test",
				request = "launch",
				mode = "test",
				program = "${fileDirname}",
				cwd = "${fileDirname}",
				outputMode = "remote",
			},
			{
				type = "delve",
				name = "Debug test (go.mod)",
				request = "launch",
				mode = "test",
				program = "${file}",
				cwd = "${fileDirname}",
				outputMode = "remote",
			},
			{
				type = "delve",
				name = "Debug (manual entry)",
				request = "launch",
				program = function()
					return vim.fn.input('Path to Go file or directory: ', vim.fn.getcwd() .. '/', 'file')
				end,
				outputMode = "remote",
			},
		},
	},
	javascript = {
		configurations = {
			{
				name = "Launch",
				type = "pwa-node",
				request = "launch",
				program = "${file}",
				cwd = vim.fn.getcwd(),
				sourceMaps = true,
				console = "integratedTerminal",
			},
			{
				name = "Attach",
				type = "pwa-node",
				request = "attach",
				processId = function()
					return require("dap.utils").pick_process()
				end,
				cwd = vim.fn.getcwd(),
				sourceMaps = true,
				console = "integratedTerminal",
			},
		},
	},
	typescript = { configurations = {} }, -- Will be set to JS configs
	python = {
		configurations = {
			{
				type = "python",
				request = "launch",
				name = "Launch current file",
				program = "${file}",
				console = "integratedTerminal",
				cwd = "${workspaceFolder}",
				env = { PYTHONPATH = "${workspaceFolder}" },
			},
			{
				type = "python",
				request = "launch",
				name = "Launch with arguments",
				program = "${file}",
				args = function()
					local args = vim.fn.input("Arguments: ")
					return vim.split(args, " ")
				end,
				console = "integratedTerminal",
				cwd = "${workspaceFolder}",
			},
		},
	},
	c = {
		configurations = {
			{
				name = "Launch",
				type = "lldb",
				request = "launch",
				program = function()
					return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
				end,
				cwd = "${fileDirname}",
				stopOnEntry = false,
				args = {},
				sourceLanguages = { "c" },
				outputMode = "remote",
			},
			{
				name = "Attach",
				type = "lldb",
				request = "attach",
				pid = function()
					return require("dap.utils").pick_process()
				end,
				cwd = "${fileDirname}",
				sourceLanguages = { "c" },
				outputMode = "remote",
			},
		},
	},
	cpp = {
		configurations = {
			{
				name = "Launch",
				type = "lldb",
				request = "launch",
				program = function()
					return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
				end,
				cwd = "${fileDirname}",
				stopOnEntry = false,
				args = {},
				sourceLanguages = { "cpp" },
				outputMode = "remote",
			},
			{
				name = "Attach",
				type = "lldb",
				request = "attach",
				pid = function()
					return require("dap.utils").pick_process()
				end,
				cwd = "${fileDirname}",
				sourceLanguages = { "cpp" },
				outputMode = "remote",
			},
		},
	},
  swift = {
    configurations = {
      {
        name = "Launch",
        type = "codelldb",
        request = "launch",
        program = function()
          return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
        args = {},
      },
      {
        name = "Attach",
        type = "codelldb",
        request = "attach",
        pid = function()
          return require("dap.utils").pick_process()
        end,
        cwd = "${workspaceFolder}",
      },
    },
  },
	zig = {
		configurations = {
			{
				name = "Launch",
				type = "lldb",
				request = "launch",
				program = function()
					return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
				end,
				cwd = "${workspaceFolder}",
				stopOnEntry = false,
				args = {},
			},
			{
				name = "Attach",
				type = "lldb",
				request = "attach",
				pid = function()
					return require("dap.utils").pick_process()
				end,
				cwd = "${workspaceFolder}",
			},
		},
	},
}
dap_languages.typescript.configurations = dap_languages.javascript.configurations

return {
	-- DAP (Debug Adapter Protocol) debugging
	{
		"mfussenegger/nvim-dap",
		event = "VeryLazy",
		dependencies = {
			"rcarriga/nvim-dap-ui",
			"theHamsta/nvim-dap-virtual-text",
			"nvim-neotest/nvim-nio",
		},
		keys = {
			{
				"<leader>db",
				function()
					require("dap").toggle_breakpoint()
				end,
				desc = "Toggle breakpoint",
			},
			{
				"<leader>dB",
				function()
					require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
				end,
				desc = "Set conditional breakpoint",
			},
			{
				"<leader>dc",
				function()
					require("dap").continue()
				end,
				desc = "Continue/start debugging",
			},
			{
				"<leader>dd",
				function()
					require("dapui").toggle()
				end,
				desc = "Toggle DAP UI",
			},
			{
				"<leader>dt",
				function()
					require("dap").terminate()
				end,
				desc = "Terminate debugging",
			},
			{
				"<leader>do",
				function()
					require("dap").step_over()
				end,
				desc = "Step over",
			},
			{
				"<leader>di",
				function()
					require("dap").step_into()
				end,
				desc = "Step into",
			},
			{
				"<leader>dO",
				function()
					require("dap").step_out()
				end,
				desc = "Step out",
			},
			{
				"<leader>dr",
				function()
					require("dap").restart()
				end,
				desc = "Restart debugging",
			},
			{
				"<leader>dR",
				function()
					require("dap").run_last()
				end,
				desc = "Run last configuration",
			},
			{
				"<leader>dl",
				function()
					local dap = require("dap")
					local configs = dap.configurations[vim.bo.filetype]
					if not configs or not configs[1] then
						vim.notify("No debug configuration available for " .. vim.bo.filetype, vim.log.levels.WARN)
						return
					end
					dap.run(configs[1])
				end,
				desc = "Launch default configuration",
			},
			{
				"<leader>dL",
				function()
					require("telescope").extensions.dap.configurations({})
				end,
				desc = "Select debug configuration",
			},
		},
		config = function()
			local dap = require("dap")
			local dapui = require("dapui")
			local dap_virtual_text = require("nvim-dap-virtual-text")

			-- DAP Virtual Text setup
			dap_virtual_text.setup({
				enabled = true,
				enabled_commands = true,
				highlight_changed_variables = true,
				highlight_new_as_changed = false,
				show_stop_reason = true,
				commented = false,
				only_first_definition = true,
				all_references = false,
				filter_references_pattern = "<module",
				virt_text_pos = "eol",
				all_frames = false,
				virt_lines = false,
				virt_text_win_col = nil,
			})

			-- DAP UI setup
			dapui.setup({
				icons = { expanded = "▾", collapsed = "▸", current_frame = "▸" },
				mappings = {
					expand = { "<CR>", "<2-LeftMouse>" },
					open = "o",
					remove = "d",
					edit = "e",
					repl = "r",
					toggle = "t",
				},
				element_mappings = {},
				expand_lines = vim.fn.has("nvim-0.7") == 1,
				layouts = {
					{
						elements = {
							{ id = "scopes", size = 0.25 },
							{ id = "breakpoints", size = 0.25 },
							{ id = "stacks", size = 0.25 },
							{ id = "watches", size = 0.25 },
						},
						size = 40,
						position = "left",
					},
					{
						elements = {
							{ id = "repl", size = 0.5 },
							{ id = "console", size = 0.5 },
						},
						size = 0.25,
						position = "bottom",
					},
				},
				controls = {
					enabled = true,
					icons = {
						pause = "",
						play = "",
						step_into = "",
						step_over = "",
						step_out = "",
						step_back = "",
						run_last = "↻",
						terminate = "□",
					},
				},
				floating = {
					max_height = nil,
					max_width = nil,
					border = "rounded",
					mappings = {
						close = { "q", "<Esc>" },
					},
				},
				windows = { indent = 1 },
				render = {
					max_type_length = nil,
					max_value_lines = 100,
				},
			})

			-- DAP UI auto-open/close
			dap.listeners.after.event_initialized["dapui_config"] = function()
				dapui.open()
			end
			dap.listeners.before.event_terminated["dapui_config"] = function()
				dapui.close()
			end
			dap.listeners.before.event_exited["dapui_config"] = function()
				dapui.close()
			end

			-- Add error handling and logging
			dap.listeners.after.event_stopped["dap_error_handler"] = function(_session, body)
				if body.reason == "exception" then
					vim.notify("Debug exception: " .. (body.description or "Unknown error"), vim.log.levels.ERROR)
				end
			end

			dap.listeners.after.event_output["dap_output_handler"] = function(_session, body)
				if body.category == "stderr" then
					vim.notify("Debug stderr: " .. body.output, vim.log.levels.WARN)
				end
			end

			-- Log process events for debugging
			dap.listeners.after.event_process["dap_process_logger"] = function(_session, body)
				vim.notify(
					string.format("Debug process: %s (PID: %s)", body.name, body.systemProcessId or "unknown"),
					vim.log.levels.INFO
				)
			end

			dap.listeners.after.event_exited["dap_exit_logger"] = function(_session, body)
				local exit_code = body.exitCode or "unknown"
				local msg = string.format("Debug process exited with code: %s", exit_code)
				if exit_code ~= 0 then
					vim.notify(msg, vim.log.levels.WARN)
				else
					vim.notify(msg, vim.log.levels.INFO)
				end
			end

			-- DAP signs
			vim.fn.sign_define("DapBreakpoint", { text = "🔴", texthl = "", linehl = "", numhl = "" })
			vim.fn.sign_define("DapBreakpointCondition", { text = "🟡", texthl = "", linehl = "", numhl = "" })
			vim.fn.sign_define("DapLogPoint", { text = "🔵", texthl = "", linehl = "", numhl = "" })
			vim.fn.sign_define("DapStopped", { text = "▶️", texthl = "", linehl = "", numhl = "" })
			vim.fn.sign_define("DapBreakpointRejected", { text = "🚫", texthl = "", linehl = "", numhl = "" })

			-- Apply unified DAP configurations
			for lang, config in pairs(dap_languages) do
				if config.configurations then
					dap.configurations[lang] = config.configurations
				end
			end

			-- Manual setup for pwa-node adapter (vscode-js-debug via Nix)
			dap.adapters["pwa-node"] = {
				type = "server",
				host = "localhost",
				port = "${port}",
				executable = {
					command = "js-debug",
					args = { "${port}" },
				},
			}

			-- LLDB adapter (for C/C++/Zig via Nix)
			dap.adapters.lldb = {
				type = "executable",
				command = "lldb-dap",
				name = "lldb",
			}

			-- CodeLLDB adapter (for Rust/Swift via Nix)
			dap.adapters.codelldb = {
				type = "server",
				port = "${port}",
				executable = {
					command = "codelldb",
					args = { "--port", "${port}" },
				},
			}

			-- Python adapter (debugpy via Nix)
			dap.adapters.python = {
				type = "executable",
				command = "python3",
				args = { "-m", "debugpy.adapter" },
			}

			-- Go adapter (delve via Nix)
			dap.adapters.delve = {
				type = "server",
				port = "${port}",
				executable = {
					command = "dlv",
					args = { "dap", "-l", "127.0.0.1:${port}" },
				},
			}
		end,
	},

	-- Language-specific DAP adapters
	-- Lua debugging
	{
		"jbyuki/one-small-step-for-vimkind",
		event = "VeryLazy",
		dependencies = { "mfussenegger/nvim-dap" },
		config = function()
			local dap = require("dap")
			-- Only set up Lua debugging when actually needed
			dap.adapters.nlua = function(callback, config)
				-- Defer connection until debugging starts
				vim.defer_fn(function()
					callback({
						type = "server",
						host = config.host or "127.0.0.1",
						port = config.port or 8086,
					})
				end, 100)
			end
			dap.configurations.lua = {
				{
					type = "nlua",
					request = "attach",
					name = "Attach to running Neovim instance",
					host = function()
						local value = vim.fn.input("Host [127.0.0.1]: ")
						return value ~= "" and value or "127.0.0.1"
					end,
					port = function()
						local val = tonumber(vim.fn.input("Port [8086]: "))
						return val and val or 8086
					end,
				},
			}
		end,
	},

	-- Telescope DAP integration
	{
		"nvim-telescope/telescope-dap.nvim",
		event = "VeryLazy",
		dependencies = { "mfussenegger/nvim-dap", "nvim-telescope/telescope.nvim" },
		config = function()
			require("telescope").load_extension("dap")
		end,
	},

}
