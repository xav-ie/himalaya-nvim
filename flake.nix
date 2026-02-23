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
          customRC = ''
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
              --endpoint-url "$endpoint" --exclude "*" --include "*.mp4" \
              --content-type "video/mp4"
            echo "Done. Files available at https://himalaya-nvim.xav.ie/"
          '';

          # nix run .#gen-docs
          packages.gen-docs = pkgs.writeShellScriptBin "gen-docs" ''
            set -euo pipefail
            ${pkgs.lib.getExe pkgs.neovim} --headless -l scripts/gen-docs.lua
          '';

          # nix run .#build-demo
          packages.build-demo = pkgs.writeShellScriptBin "build-demo" ''
            set -euo pipefail
            process_tape() {
              tape="$1"
              name="$(basename "$tape" .tape)"
              ${pkgs.lib.getExe pkgs.vhs} "$tape" -o "demo/$name.mp4"
              ${pkgs.lib.getExe pkgs.ffmpeg} -loglevel error -i "demo/$name.mp4" \
                -vf "unsharp=5:5:0.8:5:5:0.8, eq=saturation=1.2" \
                -vcodec libx264 -crf 28 -an -preset veryslow -y "demo/$name-out.mp4"
              mv "demo/$name-out.mp4" "demo/$name.mp4"
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
            # postPatch = with pkgs; ''
            #   substituteInPlace plugin/himalaya.vim \
            #     --replace "default_executable = 'himalaya'" "default_executable = '${himalaya}/bin/himalaya'"
            # '';
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
              vhs
              ffmpeg
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
