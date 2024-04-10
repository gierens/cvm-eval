{
  description =
    "CVM-Eval -- Evaluation environment for AMD SEV-SNP and Intel TDX";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixpkgs-2311.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs-mic92.url = "github:mic92/nixpkgs/spdk";
    flake-utils.url = "github:numtide/flake-utils";
    # debug build inputs
    kernelSrc.url = "path:/home/robert/repos/github.com/TUM_DSE/CVM_eval/src/linux";
    kernelSrc.flake = false;
  };

  outputs = { self, nixpkgs-unstable, nixpkgs-stable, nixpkgs-2311
    , nixpkgs-mic92, flake-utils, kernelSrc }:
    (flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        nixpkgs-direct = nixpkgs-unstable;
        pkgs = nixpkgs-unstable.legacyPackages.${system};
        stablepkgs = nixpkgs-stable.legacyPackages.${system};
        pkgs-2311 = nixpkgs-2311.legacyPackages.${system};
        mic92pkgs = nixpkgs-mic92.legacyPackages.${system};
        make-disk-image = import (pkgs.path + "/nixos/lib/make-disk-image.nix");
        selfpkgs = self.packages.x86_64-linux;
        python3 = nixpkgs-unstable.legacyPackages.${system}.python3;
      in rec {
        packages = {
          # SPDK is for SSD preconditioning
          # use forked version as the current upstream version has some issues
          # (TODO: check if the issues are fixed)
          spdk = let pkgs = mic92pkgs;
          in pkgs.callPackage ./nix/spdk.nix { inherit pkgs; };

          qemu-amd-sev-snp =
            pkgs.callPackage ./nix/qemu-amd-sev-snp.nix { inherit pkgs; };
          ovmf-amd-sev-snp =
            pkgs.callPackage ./nix/ovmf-amd-sev-snp.nix { inherit pkgs; };

          normal-guest-image = make-disk-image {
            config = self.nixosConfigurations.normal-guest.config;
            inherit (pkgs) lib;
            inherit pkgs;
            format = "qcow2";
            partitionTableType = "efi";
            installBootLoader = true;
            diskSize = 32768;
            touchEFIVars = true;
          };

          snp-guest-image = make-disk-image {
            config = self.nixosConfigurations.snp-guest.config;
            inherit (pkgs) lib;
            inherit pkgs;
            format = "qcow2";
            partitionTableType = "efi";
            installBootLoader = true;
            diskSize = 32768;
            touchEFIVars = true;
          };
        };

        devShells = {
          default = pkgs.mkShell {
            name = "devshell";
            buildInputs = let
              inv-completion = pkgs.writeScriptBin "inv-completion" ''
                inv --print-completion-script zsh
              '';
            in with pkgs;
            [
              # tasks
              python3
              python3.pkgs.invoke
              python3.pkgs.colorama
              just
              fzf
              # add again once upstreamed
              # spdk # for nvme_mange -> SSD precondition
              fio
              cryptsetup
              # bpftrace
              linux.dev
              gdb
              # trace-cmd
              jq

              gfortran

              # clang-format
              libclang.python
              clang-tools

              # plot
              python3.pkgs.click
              python3.pkgs.seaborn
              python3.pkgs.pandas
              python3.pkgs.binary
              python3.pkgs.lxml
            ] ++ ([ inv-completion ]);
          };
        };

      })) // {
        # nixOS configurations to create a guest image with kernel
        nixosConfigurations = let
          pkgs = nixpkgs-unstable.legacyPackages.x86_64-linux;
          selfpkgs = self.packages.x86_64-linux;
          kernelConfig = { config, lib, pkgs, ... }: {
            boot.kernelPackages = pkgs.linuxPackages_6_6;
          };
        in {
          # Normal Linux guest (mainline)
          normal-guest = nixpkgs-unstable.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./nix/guest-config.nix
              kernelConfig
              ./nix/nixos-generators-qcow.nix
            ];
          };

          # SEV-SNP guest
          snp-guest = nixpkgs-unstable.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./nix/guest-config.nix
              kernelConfig
              ./nix/snp-guest-config.nix
              ./nix/nixos-generators-qcow.nix
            ];
          };
        };
      };
}
