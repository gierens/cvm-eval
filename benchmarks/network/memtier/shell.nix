let
  # 23.11
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/9ddcaffecdf098822d944d4147dd8da30b4e6843.tar.gz";
  pkgs = import nixpkgs { config = { }; overlays = [ ]; };
in
pkgs.mkShell {
  buildInputs = [
    pkgs.memtier-benchmark
    pkgs.redis
    pkgs.memcached
    pkgs.just
  ];
  # nix-shell ./path/to/shell.nix automatically cd's into the directory
  shellHook = ''cd "${toString ./.}"'';
}
