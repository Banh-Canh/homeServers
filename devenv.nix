let
  sources = import ./npins;
  inherit (sources) hephaestus;
  hephaestusSources = import (hephaestus + "/npins");
in
{
  pkgs,
  lib,
  ...
}:
{
  imports = [ "${hephaestusSources.nixbook}/devenvModules/devenv.nix" ];

  packages = with pkgs; [
    jq
    yq-go
    colmena
    npins
  ];

  env.PATH = lib.mkForce "$PWD/scripts:$PATH";

  scripts = {
    update-gojo.description = "Deploy NixOS configuration to gojo via Colmena";
    update-gojo.exec = ''
      colmena apply --on @home
    '';
    build-iso.description = "Build bootable NixOS installation ISO image using hephaestus";
    build-iso.exec = ''
      HEPHAESTUS=$(nix-instantiate --eval -E '(import ./npins).hephaestus.outPath' | tr -d '"')
      nix-build "$HEPHAESTUS/default.nix" -A buildIso \
        --argstr repoUrl "https://github.com/Banh-Canh/homeServers" \
        "$@"
    '';
  };

  enterShell = ''
    echo ""
    echo "homeServers development environment loaded"
    echo ""
    echo "Available scripts:"
    echo ""
    echo "  update-gojo  - Deploy NixOS configuration to gojo via Colmena"
    echo "  build-iso    - Build bootable NixOS installation ISO image"
    echo "                 Example: build-iso --argstr bootloader grub --argstr partition root-grub --argstr disk /dev/disk/by-id/ata-XXXX --argstr cloud gojo"
    echo ""
  '';
}
