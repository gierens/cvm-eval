{ buildFHSUserEnv
, lib
, getopt
, elfutils
, ncurses
, openssl
, zlib
, flex
, bison
, binutils
, gcc
, gnumake
, bc
, perl
, hostname
, cpio
, pkg-config
, pahole
, runScript ? ''bash -c''
}:
buildFHSUserEnv {
  name = "linux-kernel-build";
  targetPkgs = pkgs: ([
    getopt
    flex
    bison
    binutils
    gcc
    gnumake
    bc
    perl
    hostname
    cpio
    pkg-config
    pahole # BTF
  ] ++ map lib.getDev [
    elfutils
    ncurses
    openssl
    zlib
  ]);
  profile = ''
    export hardeningDisable=all
  '';

  inherit runScript;
}
