{
  description = "Vim front-end for the email client Himalaya CLI";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, utils, ... }:
    utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs { inherit system; };
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
          plugin = name:
            builtins.trace "${name} rev: ${pkgs.vimPlugins.${name}.src.rev}" pkgs.vimPlugins.${name};
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
        rec {
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
            src = self;
            nvimRequireCheck = "himalaya";
            # buildInputs = with pkgs; [ himalaya ];
            # postPatch = with pkgs; ''
            #   substituteInPlace plugin/himalaya.vim \
            #     --replace "default_executable = 'himalaya'" "default_executable = '${himalaya}/bin/himalaya'"
            # '';
          };

          # nix develop
          devShell = pkgs.mkShell {
            buildInputs = self.packages.${system}.default.buildInputs;
            nativeBuildInputs = with pkgs; [

              # Nix LSP + formatter
              nixd
              nixpkgs-fmt

              # Vim LSP
              nodejs
              nodePackages.vim-language-server

              # Lua LSP
              lua-language-server

              # Linting + formatting
              stylua
              luajitPackages.luacheck
              parallel

              # Testing + coverage
              busted-nlua
              luajitPackages.luacov

              # Demo recording
              vhs
              ffmpeg

              # FZF
              fzf

              # Editors
              ((vim-full.override { }).customize {
                name = "vim";
                vimrcConfig = {
                  inherit customRC;
                  packages.myplugins = {
                    start = with pkgs.vimPlugins; [ fzf-vim ];
                    opt = [ self.packages.${system}.default ];
                  };
                };
              })
              (neovim.override {
                configure = {
                  inherit customRC;
                  packages.myPlugins = {
                    start = plugins [ "telescope-nvim" "fzf-vim" "plenary-nvim" ];
                    opt = [ self.packages.${system}.default ];
                  };
                };
              })
            ];
          };
        });
}
