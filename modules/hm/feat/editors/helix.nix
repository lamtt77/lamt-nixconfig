{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  home.packages =
    let
      lspServers = with pkgs; [
        bash-language-server
        marksman
        nil
        nixd
        typescript-language-server
        rust-analyzer
        tailwindcss-language-server
        vscode-langservers-extracted
        yaml-language-server
      ];

      formatters = with pkgs; [
        prettier
        ruff
        sql-formatter
        taplo
      ];

      languageTools = with pkgs; [
        biome
        clang-tools
        docker-compose-language-service
        dockerfile-language-server
        golangci-lint
        golangci-lint-langserver
        gopls
        gotools
        typescript
      ];
    in
    lspServers ++ formatters ++ languageTools;

  programs.helix = {
    enable = true;
    package = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.helix;
    # defaultEditor = true;

    settings = {
      theme = "gruvbox_community";

      editor = {
        color-modes = true;
        cursorline = true;
        bufferline = "multiple";

        soft-wrap.enable = true;

        auto-save = {
          focus-lost = true;
          after-delay.enable = true;
        };

        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
        };

        file-picker = {
          hidden = false;
          ignore = false;
        };

        indent-guides = {
          character = "┊";
          render = true;
          skip-levels = 1;
        };

        end-of-line-diagnostics = "hint";
        inline-diagnostics.cursor-line = "warning";

        lsp = {
          display-inlay-hints = true;
          display-messages = true;
        };

        statusline = {
          left = [
            "mode"
            "file-name"
            "spinner"
            "read-only-indicator"
            "file-modification-indicator"
          ];
          right = [
            "diagnostics"
            "selections"
            "register"
            "file-type"
            "file-line-ending"
            "position"
          ];
          mode.normal = "";
          mode.insert = "I";
          mode.select = "S";
        };
      };

      keys = {
        normal = {
          C-h = "goto_previous_buffer";
          C-l = "goto_next_buffer";

          space = {
            c = ":buffer-close";
          };
        };

        insert = {
          "C-[" = "normal_mode";
        };

        select = {
          "C-[" = "normal_mode";
          tab = "extend_parent_node_end";
          S-tab = "extend_parent_node_start";
        };
      };
    };

    themes = {
      # https://github.com/helix-editor/helix/blob/master/runtime/themes/gruvbox.toml
      gruvbox_community = {
        inherits = "gruvbox";
        "variable" = "blue1";
        "variable.parameter" = "blue1";
        "function.macro" = "red1";
        "operator" = "orange1";
        "comment" = "gray";
        "constant.builtin" = "orange1";
        "ui.background" = { };
      };
    };

    languages = {
      language-server.biome = {
        command = "biome";
        args = [ "lsp-proxy" ];
      };

      language-server.rust-analyzer.config.check = {
        command = "clippy";
      };

      language-server.yaml-language-server.config.yaml.schemas = {
        kubernetes = "k8s/*.yaml";
      };

      language-server.typescript-language-server.config.tsserver = {
        path = "${pkgs.typescript}/lib/node_modules/typescript/lib/tsserver.js";
      };

      language = [
        {
          name = "css";
          language-servers = [
            "vscode-css-language-server"
            "tailwindcss-ls"
            "biome"
            "gpt"
          ];
          auto-format = true;
        }
        {
          name = "go";
          language-servers = [
            "gopls"
            "golangci-lint-lsp"
            "gpt"
          ];
          formatter = {
            command = "goimports";
          };
          auto-format = true;
        }
        {
          name = "html";
          language-servers = [
            "vscode-html-language-server"
            "tailwindcss-ls"
          ];
          formatter = {
            command = "prettier";
            args = [
              "--stdin-filepath"
              "file.html"
            ];
          };
          auto-format = true;
        }
        {
          name = "javascript";
          language-servers = [
            {
              name = "typescript-language-server";
              except-features = [ "format" ];
            }
            "biome"
            "gpt"
          ];
          auto-format = true;
        }
        {
          name = "json";
          language-servers = [
            {
              name = "vscode-json-language-server";
              except-features = [ "format" ];
            }
            "biome"
          ];
          formatter = {
            command = "biome";
            args = [
              "format"
              "--indent-style"
              "space"
              "--stdin-file-path"
              "file.json"
            ];
          };
          auto-format = true;
        }
        {
          name = "jsonc";
          language-servers = [
            {
              name = "vscode-json-language-server";
              except-features = [ "format" ];
            }
            "biome"
          ];
          formatter = {
            command = "biome";
            args = [
              "format"
              "--indent-style"
              "space"
              "--stdin-file-path"
              "file.jsonc"
            ];
          };
          file-types = [
            "jsonc"
            "hujson"
          ];
          auto-format = true;
        }
        {
          name = "jsx";
          language-servers = [
            {
              name = "typescript-language-server";
              except-features = [ "format" ];
            }
            "tailwindcss-ls"
            "biome"
            "gpt"
          ];
          formatter = {
            command = "biome";
            args = [
              "format"
              "--indent-style"
              "space"
              "--stdin-file-path"
              "file.jsx"
            ];
          };
          auto-format = true;
        }
        {
          name = "markdown";
          language-servers = [ "marksman" ];
          formatter = {
            command = "prettier";
            args = [
              "--stdin-filepath"
              "file.md"
            ];
          };
          auto-format = true;
        }
        {
          name = "nix";
          formatter = {
            command = "alejandra";
          };
          auto-format = true;
        }
        {
          name = "python";
          language-servers = [
            "pylsp"
            "gpt"
          ];
          formatter = {
            command = "sh";
            args = [
              "-c"
              "ruff check --select I --fix - | ruff format --line-length 88 -"
            ];
          };
          auto-format = true;
        }
        {
          name = "rust";
          language-servers = [
            "rust-analyzer"
            "gpt"
          ];
          auto-format = true;
        }
        {
          name = "sql";
          formatter = {
            command = "sql-formatter";
            args = [
              "-l"
              "postgresql"
              "-c"
              "{\"keywordCase\": \"lower\", \"dataTypeCase\": \"lower\", \"functionCase\": \"lower\", \"expressionWidth\": 120, \"tabWidth\": 4}"
            ];
          };
          auto-format = true;
        }
        {
          name = "toml";
          language-servers = [ "taplo" ];
          formatter = {
            command = "taplo";
            args = [
              "fmt"
              "-o"
              "column_width=120"
              "-"
            ];
          };
          auto-format = true;
        }
        {
          name = "tsx";
          language-servers = [
            {
              name = "typescript-language-server";
              except-features = [ "format" ];
            }
            "tailwindcss-ls"
            "biome"
            "gpt"
          ];
          formatter = {
            command = "biome";
            args = [
              "format"
              "--indent-style"
              "space"
              "--stdin-file-path"
              "file.tsx"
            ];
          };
          auto-format = true;
        }
        {
          name = "typescript";
          language-servers = [
            {
              name = "typescript-language-server";
              except-features = [ "format" ];
            }
            "biome"
            "gpt"
          ];
          formatter = {
            command = "biome";
            args = [
              "format"
              "--indent-style"
              "space"
              "--stdin-file-path"
              "file.ts"
            ];
          };
          auto-format = true;
        }
        {
          name = "yaml";
          language-servers = [ "yaml-language-server" ];
          formatter = {
            command = "prettier";
            args = [
              "--stdin-filepath"
              "file.yaml"
            ];
          };
          auto-format = true;
        }
      ];
    };
  };
}
