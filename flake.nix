{
  description = "CVM-IO - a storage-IO performance enhancing CVM method";

  inputs =
  {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = 
  {
    self
    , nixpkgs-unstable
    , flake-utils
  }:
  (
    flake-utils.lib.eachSystem ["x86_64-linux"]
    (
      system:
      let
        pkgs = nixpkgs-unstable.legacyPackages.${system};
        make-disk-image = import (pkgs.path + "/nixos/lib/make-disk-image.nix");
        selfpkgs = self.packages.x86_64-linux;
      in
      rec {
        packages =
        {
          # SSD preconditioning
          spdk = pkgs.callPackage ./nix/spdk.nix { inherit pkgs; };

          qemu-amd-sev-snp = pkgs.callPackage ./nix/qemu-amd-sev-snp.nix { inherit pkgs; };
          # only need AMD kernel fork on host, not in guest
          # linux-amd-sev-snp = pkgs.callPackage ./nix/linux-amd-sev-snp.nix { inherit pkgs; };
          ovmf-amd-sev-snp = pkgs.callPackage ./nix/ovmf-amd-sev-snp.nix { inherit pkgs; };
          guest-image = make-disk-image
          {
            config = self.nixosConfigurations.native-guest.config;
            inherit (pkgs) lib;
            inherit pkgs;
            format = "qcow2";
            partitionTableType = "hybrid";
            diskSize = 4096;
            OVMF = selfpkgs.ovmf-amd-sev-snp.fd;
            contents =
            [
              {
                source = ./bm/blk-bm.fio;
                target = "/mnt/blk-bm.fio";
              }
              
            ];
          };
        };

        devShells.default = pkgs.mkShell
        {
          name = "benchmark-devshell";
          buildInputs = with pkgs;
          [
            just
            fzf
            # spdk # for nvme_mange -> SSD precondition
          ] ++ 
          (
            with self.packages.${system};
            [
              qemu-amd-sev-snp # patched amd-sev-snp qemu
              spdk # nvme SSD formatting
            ]
          );
        };
      }
    )
  ) //
  {
    nixosConfigurations = let
      pkgs = nixpkgs-unstable.legacyPackages.x86_64-linux;
    in
    {
      native-guest = nixpkgs-unstable.lib.nixosSystem
      {
        system = "x86_64-linux";
        modules =
        [
          (
            import ./nix/native-guest-config.nix
            {
              inherit pkgs;
              inherit (nixpkgs-unstable) lib;
            }
          )
          ./nix/nixos-generators-qcow.nix
        ];
      };
    };
  };
}
