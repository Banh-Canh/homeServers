let
  sources = import ./npins;
  inherit (sources) hephaestus;
  hephaestusSources = import (hephaestus + "/npins");
  pkgs = import hephaestusSources.nixpkgs {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = true;
    };
    overlays = [
      (import (hephaestus + "/overlays/kubernetes.nix"))
      (import (hephaestus + "/overlays/nixbook-compat.nix"))
    ];
  };
  createConfiguration = parent: {
    networking.hostName = parent.hostName;
    deployment = {
      buildOnTarget = true;
      allowLocalDeployment = true;
      targetUser = builtins.getEnv "USER";
      targetHost = parent.host;
      inherit (parent) tags;
    };
    imports = [ ./profiles/${parent.hostName}/configuration.nix ];
  };
in
{
  meta = {
    nixpkgs = pkgs;
  };
  gojo = createConfiguration {
    hostName = "gojo";
    host = "gojo";
    tags = [
      "home"
      "baremetal"
    ];
  };
}
