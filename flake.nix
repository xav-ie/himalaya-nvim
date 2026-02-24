{
  description = "Vim front-end for the email client Himalaya CLI";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      imports = [ inputs.treefmt-nix.flakeModule ];

      perSystem =
        {
          pkgs,
          self',
          system,
          ...
        }:
        let
          svgoConfig =
            pkgs.writeText "svgo.config.mjs" # js
              ''
                export default {
                  plugins: [
                    {
                      name: "preset-default",
                      params: {
                        overrides: {
                          // Don't remove "hidden" elements — animation states are off-screen
                          removeHiddenElems: false,
                        },
                      },
                    },
                  ],
                };
              '';
          vhs-svg = pkgs.buildGoModule {
            pname = "vhs";
            version = "0.11.1-svg-fix";
            src = pkgs.fetchFromGitHub {
              owner = "xav-ie";
              repo = "vhs";
              rev = "f2cac8b473cb9aa81c112deb47a6fc014c9220b0";
              hash = "sha256-+/vuK83dY9Jq4w91a19kBBhBVGnB8cw6aUT99A5Y3L4=";
            };
            vendorHash = "sha256-WiCSn84cr42yQFgg36H/NrVsfiBA/ZDAGd0WmC6LAa4=";
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postInstall = ''
              wrapProgram $out/bin/vhs \
                --prefix PATH : ${
                  pkgs.lib.makeBinPath [
                    pkgs.ttyd
                    pkgs.ffmpeg
                    pkgs.fontconfig
                  ]
                }
            '';
            meta.mainProgram = "vhs";
          };
          busted-nlua = pkgs.luajitPackages.busted.overrideAttrs (oa: {
            propagatedBuildInputs = oa.propagatedBuildInputs ++ [
              pkgs.luajitPackages.nlua
            ];
            nativeBuildInputs = oa.nativeBuildInputs ++ [
              pkgs.makeWrapper
            ];
            postInstall = (oa.postInstall or "") + ''
              wrapProgram $out/bin/busted --add-flags "--lua=nlua"
            '';
          });
          plugin =
            name: builtins.trace "${name} rev: ${pkgs.vimPlugins.${name}.src.rev}" pkgs.vimPlugins.${name};
          plugins = map plugin;
          customRC = # vim
            ''
              syntax on
              filetype plugin on

              packadd! himalaya

              " native, fzf or telescope
              let g:himalaya_folder_picker = 'telescope'
              let g:himalaya_folder_picker_telescope_preview = v:false
              let g:himalaya_complete_contact_cmd = 'echo test@localhost'
            '';
        in
        {
          treefmt = {
            projectRootFile = "flake.nix";
            programs.stylua.enable = true;
            programs.nixfmt.enable = true;
          };

          # nix run .#upload-demo
          # Requires: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY env vars
          # (R2 S3-compatible credentials from Cloudflare dashboard)
          packages.upload-demo = pkgs.writeShellScriptBin "upload-demo" ''
            set -euo pipefail
            bucket="''${R2_BUCKET:-himalaya-nvim}"
            endpoint="https://946b8d18ae9ef27fc85597e7716a1641.r2.cloudflarestorage.com"
            ${pkgs.lib.getExe pkgs.awscli2} s3 sync demo/ "s3://$bucket/" \
              --endpoint-url "$endpoint" --exclude "*" --include "*.svg" \
              --content-type "image/svg+xml"
            ${pkgs.lib.getExe pkgs.awscli2} s3 sync demo/ "s3://$bucket/" \
              --endpoint-url "$endpoint" --exclude "*" --include "*.mp4" \
              --content-type "video/mp4"
            ${pkgs.lib.getExe pkgs.awscli2} s3 sync demo/ "s3://$bucket/" \
              --endpoint-url "$endpoint" --exclude "*" --include "*.png" \
              --content-type "image/png"
            echo "Done. Files available at https://himalaya-nvim.xav.ie/"
          '';

          # nix run .#gen-docs
          packages.gen-docs = pkgs.writeShellScriptBin "gen-docs" ''
            set -euo pipefail
            ${pkgs.lib.getExe pkgs.neovim} --headless -l scripts/gen-docs.lua
          '';

          # nix run .#build-demo
          packages.build-demo =
            let
              pyftsubset = pkgs.python3Packages.fonttools.overridePythonAttrs (old: {
                dependencies = (old.dependencies or [ ]) ++ [ pkgs.python3Packages.brotli ];
              });
              fontSubsetPath = pkgs.lib.makeBinPath [
                pyftsubset
                pkgs.fontconfig
              ];
            in
            pkgs.writeShellScriptBin "build-demo" ''
              set -euo pipefail
              process_tape() {
                tape="$1"
                name="$(basename "$tape" .tape)"
                ${pkgs.lib.getExe vhs-svg} "$tape"
                ${pkgs.lib.getExe pkgs.ffmpeg} -loglevel error -i "demo/$name.mp4" \
                  -vf "unsharp=5:5:0.8:5:5:0.8, eq=saturation=1.2" \
                  -vcodec libx264 -crf 28 -an -preset veryslow -y "demo/$name-out.mp4"
                mv "demo/$name-out.mp4" "demo/$name.mp4"
                # Extract a screenshot from the middle of the video
                duration=$(${pkgs.lib.getExe pkgs.ffmpeg} -i "demo/$name.mp4" 2>&1 | grep -oP 'Duration: \K[0-9:.]+' || echo "0")
                mid=$(echo "$duration" | ${pkgs.lib.getExe pkgs.gawk} -F: '{print ($1*3600 + $2*60 + $3) / 2}')
                ${pkgs.lib.getExe pkgs.ffmpeg} -loglevel error -ss "$mid" -i "demo/$name.mp4" \
                  -frames:v 1 -y "demo/$name.png"
                # ${pkgs.lib.getExe pkgs.svgo} \
                #   --config ${svgoConfig} \
                #   --input "demo/$name.svg" --output "demo/$name.svg"
              }
              export -f process_tape
              ${pkgs.lib.getExe pkgs.parallel} --tagstring '[{/.}]' --line-buffer \
                process_tape ::: demo/*.tape
            '';

          # nix build
          packages.default = pkgs.vimUtils.buildVimPlugin {
            name = "himalaya";
            namePrefix = "";
            src = inputs.self;
            nvimRequireCheck = "himalaya";
            # buildInputs = with pkgs; [ himalaya ];
            # postPatch =
            #  with pkgs; # sh
            #  ''
            #    substituteInPlace plugin/himalaya.vim \
            #      --replace "default_executable = 'himalaya'" "default_executable = '${himalaya}/bin/himalaya'"
            #  '';
          };

          # nix develop
          devShells.default = pkgs.mkShell {
            buildInputs = self'.packages.default.buildInputs;
            nativeBuildInputs = with pkgs; [

              # Nix LSP
              nixd

              # Vim LSP
              nodejs
              nodePackages.vim-language-server

              # Lua LSP
              lua-language-server

              # Linting
              luajitPackages.luacheck
              parallel

              # Testing + coverage
              busted-nlua
              luajitPackages.luacov

              # Demo recording + upload
              vhs-svg
              ffmpeg
              svgo
              awscli2

              # FZF
              fzf

              # Editors
              ((vim-full.override { }).customize {
                name = "vim";
                vimrcConfig = {
                  inherit customRC;
                  packages.myplugins = {
                    start = with pkgs.vimPlugins; [ fzf-vim ];
                    opt = [ self'.packages.default ];
                  };
                };
              })
              (neovim.override {
                configure = {
                  inherit customRC;
                  packages.myPlugins = {
                    start = plugins [
                      "telescope-nvim"
                      "fzf-vim"
                      "plenary-nvim"
                    ];
                    opt = [ self'.packages.default ];
                  };
                };
              })
            ];
          };
        };
    };
}
