args:
let
  sources = import ../../npins;
  hephaestusPath = sources.hephaestus;
  # Get the current directory's name
  currentDir = builtins.toString ./.;
  hostname = builtins.baseNameOf currentDir;
  # Import the base configuration from hephaestus with the dynamic hostname
  # profilesPath points to this repo's profiles directory
  base = import (hephaestusPath + "/base.nix") (
    args
    // {
      inherit hostname hephaestusPath;
      profilesPath = ../../profiles;
    }
  );
in
base
