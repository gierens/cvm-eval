{
  description =
    "CVM-Eval -- Evaluation environment for AMD SEV-SNP and Intel TDX";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-2311.url = "github:NixOS/nixpkgs/nixos-23.11";
    flake-utils.url = "github:numtide/flake-utils";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };

  outputs = { self, nixpkgs-unstable, nixpkgs-2311, flake-utils, pre-commit-hooks }:
    (flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        nixpkgs-direct = nixpkgs-unstable;
        pkgs = nixpkgs-unstable.legacyPackages.${system};
        pkgs-2311 = nixpkgs-2311.legacyPackages.${system};
        make-disk-image = import (pkgs.path + "/nixos/lib/make-disk-image.nix");
        selfpkgs = self.packages.x86_64-linux;
        python3 = nixpkgs-unstable.legacyPackages.${system}.python3;
        pre-commit-check = pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nixpkgs-fmt.enable = true;
            black.enable = true;
            clang-format.enable = true;
          };
        };
        #kernel = {
        #  src = ../linux;
        #  version = "6.8.0";
        #  makeFlags = pkgs.linuxPackages_6_8.kernel.makeFlags;
        #  kernelOlder = x: false;
        #};
      in
      rec {
        packages = {
          # SPDK is for SSD preconditioning
          spdk = pkgs.callPackage ./nix/spdk.nix { inherit pkgs; };

          qemu-amd-sev-snp =
            pkgs.callPackage ./nix/qemu-amd-sev-snp.nix { inherit pkgs; };
          ovmf-amd-sev-snp =
            pkgs.callPackage ./nix/ovmf-amd-sev-snp.nix { inherit pkgs; };

          # Note: this does not work yet!
          qemu-tdx =
            pkgs.callPackage ./nix/qemu-tdx.nix { inherit pkgs; };

          ovmf-tdx =
            pkgs.callPackage ./nix/ovmf-tdx.nix { inherit pkgs; };

          # qcow image with Linux kernel
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

          # qcow image with Linux kernel with snp support
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

          # qcow image with Linux kernel with tdx support
          tdx-guest-image = make-disk-image {
            config = self.nixosConfigurations.tdx-guest.config;
            inherit (pkgs) lib;
            inherit pkgs;
            format = "qcow2";
            partitionTableType = "efi";
            installBootLoader = true;
            diskSize = 32768;
            touchEFIVars = true;
          };

          # file system image w/o kernel
          guest-fs = make-disk-image {
            config = self.nixosConfigurations.fs.config;
            inherit (pkgs) lib;
            inherit pkgs;
            format = "qcow2";
            partitionTableType = "none";
            # installBootLoader option set up /sbin/init, etc.
            installBootLoader = true;
            diskSize = 32768;
            contents = [
              {
                source = ./config/phoronix/phoronix-test-suite.xml;
                target = "/etc/phoronix-test-suite.xml";
              }
            ];
          };

          # shell for linux kernel build
          kernel-deps = pkgs.callPackage ./nix/kernel-deps.nix { };

          # WIP: build perf with nix
          #perf = pkgs.callPackage ./nix/perf.nix { kernel = kernel; };

        };

        devShells = {
          default = pkgs.mkShell {
            name = "devshell";
            buildInputs =
              let
                inv-completion = pkgs.writeScriptBin "inv-completion" ''
                  inv --print-completion-script zsh
                '';
              in
              with pkgs;
              [
                python3
                python3.pkgs.invoke
                python3.pkgs.colorama
                python3.pkgs.click
                python3.pkgs.seaborn
                python3.pkgs.pandas
                python3.pkgs.binary
                python3.pkgs.lxml
                python3.pkgs.ipython
                python3.pkgs.psutil

                just
                git
                tig
                fzf
                bpftrace
                gdb
                jq
                bridge-utils
                hwloc
                numactl
                sysstat

                fio
                cryptsetup
                iperf # iperf3
                memtier-benchmark
                wrk
              ] ++ [ inv-completion ]
              ++ pre-commit-check.enabledPackages;
            inherit (pre-commit-check) shellHook;
          };

          # for running benchmarks
          blender = pkgs.callPackage ./benchmarks/application/blender/shell.nix { inherit pkgs; };
          pytorch = pkgs.callPackage ./benchmarks/application/pytorch/shell.nix { inherit pkgs; };
          # 2024-05-30: keras in the latest pkgs has some dependency issues; use pkgs-2311
          tensorflow = pkgs.callPackage ./benchmarks/application/tensorflow/shell.nix { pkgs = pkgs-2311; };
          sqlite = pkgs.callPackage ./benchmarks/application/sqlite/shell.nix { inherit pkgs; };
          network = pkgs.callPackage ./benchmarks/network/shell.nix { inherit pkgs; };
          sev_attestation = pkgs.callPackage ./benchmarks/attestation/sev/shell.nix { inherit pkgs; };
        };

      })) // {
      lib.nixpkgsRev = nixpkgs-unstable.shortRev;

      # nixOS configurations to create a guest image
      nixosConfigurations =
        let
          # 2024-05-30: the latest nixosSystem of unstable seems really unstable?
          # nix stores get easily corrupted when a VM is killed abruptly
          # use nixpkgs-2311 for the time being
          nixosSystem = nixpkgs-2311.lib.nixosSystem;
          pkgs = nixpkgs-unstable.legacyPackages.x86_64-linux;
          # use gcc13 (same as Ubuntu 24.04)
          gcc = pkgs.gcc13;
          selfpkgs = self.packages.x86_64-linux;
          kernelConfig = { config, lib, pkgs, ... }: {
            boot.kernelPackages = pkgs.linuxPackages_6_8;
          };
          # bake in packages for running benchmarks
          extraEnvPackages =
            self.devShells.x86_64-linux.blender.nativeBuildInputs
            ++ self.devShells.x86_64-linux.pytorch.nativeBuildInputs
            ++ self.devShells.x86_64-linux.tensorflow.nativeBuildInputs
            ++ self.devShells.x86_64-linux.sqlite.nativeBuildInputs
            ++ self.devShells.x86_64-linux.network.nativeBuildInputs
            ++ self.devShells.x86_64-linux.sev_attestation.nativeBuildInputs;
          guestConfig = (import ./nix/guest-config.nix { inherit extraEnvPackages; _gcc = gcc; });
        in
        {
          # File system image w/o kernel
          fs = nixosSystem {
            system = "x86_64-linux";
            modules = [
              guestConfig
            ];
          };

          # Normal Linux guest (mainline)
          normal-guest = nixosSystem {
            system = "x86_64-linux";
            modules = [
              guestConfig
              kernelConfig
              ./nix/nixos-generators-qcow.nix
            ];
          };

          # SEV-SNP guest
          snp-guest = nixosSystem {
            system = "x86_64-linux";
            modules = [
              guestConfig
              kernelConfig
              ./nix/snp-guest-config.nix
              ./nix/nixos-generators-qcow.nix
            ];
          };

          # TDX guest
          tdx-guest = nixosSystem {
            system = "x86_64-linux";
            modules = [
              guestConfig
              kernelConfig
              ./nix/tdx-guest-config.nix
              ./nix/nixos-generators-qcow.nix
            ];
          };
        };
    };
}
