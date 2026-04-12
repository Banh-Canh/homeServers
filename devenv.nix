let
  sources = import ./npins;
  inherit (sources) hephaestus;
  hephaestusSources = import (hephaestus + "/npins");

  kubernetesBootstrapModule = import ./nixosModules/kubernetes-bootstrap {
    inherit pkgs lib;
    config = {
      customNixOSModules.kubernetesBootstrap.enable = true; # Enable to get the derivations
    };
  };

  k8sScripts = kubernetesBootstrapModule.config.environment.systemPackages;
in
{
  pkgs,
  lib,
  ...
}:
{
  imports = [ "${hephaestusSources.nixbook}/devenvModules/devenv.nix" ];

  packages =
    with pkgs;
    [
      jq
      yq-go
      colmena
      npins
    ]
    ++ k8sScripts; # Add the k8s bootstrap scripts here

  env.PATH = lib.mkForce "$PATH"; # No longer need to add $PWD/scripts since they are in packages

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
