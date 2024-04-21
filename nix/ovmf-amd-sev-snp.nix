{ pkgs }:

with pkgs;
OVMF.fd.overrideAttrs (old: {
  # use fetchFromGitHub to specify the exact commit
  ## src = fetchFromGitHub
  ## {
  ##   owner = "AMDESE";
  ##   repo = "ovmf";
  ##   rev = "80318fcdf1bccf5d503197825d62a157efd27c4b";
  ##   sha256 = "sha256-L/X1uESu6m8a+8ir+E2HkxiazA9iyfcfeySxRJkt+2s=";
  ##   fetchSubmodules = true;
  ## };
  # we use a forked version as sometimes AMDESE's version is foce-pushed and
  # it's hard to track the changes in that case
  src = fetchFromGitHub {
    owner = "mmisono";
    repo = "edk2";
    # branch "snp-latest-20231110"
    rev = "80318fcdf1bccf5d503197825d62a157efd27c4b";
    sha256 = "sha256-L/X1uESu6m8a+8ir+E2HkxiazA9iyfcfeySxRJkt+2s=";
    fetchSubmodules = true;
  };
  patches = (old.patches or []) ++ [
    # to record boot events
    ./patches/ovmf-event-record.patch
  ];
})
