# common nixos guest configuration

{ pkgs, lib, modulesPath, ... }:

let
  keys = map (key: "${builtins.getEnv "HOME"}/.ssh/${key}") [
    "id_rsa.pub"
    "id_ecdsa.pub"
    "id_ed25519.pub"
  ];
  test-dmcrypt = pkgs.writeScriptBin "test-dmcrypt" ''
    #!/usr/bin/env bash
    set -u
    yes "" | ${pkgs.cryptsetup}/bin/cryptsetup luksOpen /dev/vda target
    echo "hello" > /dev/mapper/target
  '';
in {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  nix.extraOptions =
  ''
    experimental-features = nix-command flakes
  '';
  nix.package = pkgs.nixFlakes;

  # slows things down
  systemd.services.systemd-networkd-wait-online.enable = false;

  # override defaults from nixpkgs/modules/virtualization/container-config.nix
  # to enable cryptsetup
  services.udev.enable = lib.mkForce true;
  services.lvm.enable = lib.mkForce true;

  # login with empty password
  users.extraUsers.root.initialHashedPassword = "";
  services.openssh.enable = true;

  users.users.root.openssh.authorizedKeys.keyFiles =
    lib.filter builtins.pathExists keys;
  networking.firewall.enable = false;

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  system.stateVersion = "23.11";

  # host-file sharing
  fileSystems."/share" = {
    device = "share";
    fsType = "9p";
    options = [ "trans=virtio" "nofail" "msize=104857600" ];
  };

  users.users.root.openssh.authorizedKeys.keys =
    [ (builtins.readFile ./ssh_key.pub) ];

  services.getty.helpLine = ''
    Log in as "root" with an empty password.
    If you are connect via serial console:
    Type Ctrl-a c to switch to the qemu console
    and `quit` to stop the VM.
  '';

  services.getty.autologinUser = lib.mkDefault "root";

  documentation.doc.enable = false;
  documentation.man.enable = false;
  documentation.nixos.enable = false;
  documentation.info.enable = false;
  programs.bash.enableCompletion = false;
  programs.command-not-found.enable = false;

  environment.systemPackages = with pkgs; [
    devmem2
    bpftrace
    tmux
    vim
    fio
    cryptsetup
    lvm2
    test-dmcrypt

    phoronix-test-suite
    unzip
  ];

  boot.loader.grub.enable = false;
  boot.initrd.enable = false;
  boot.isContainer = true;
  boot.loader.initScript.enable = true;
}
