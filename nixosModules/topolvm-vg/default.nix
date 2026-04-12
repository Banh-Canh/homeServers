{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.customNixOSModules.topolvmVg;
in
{
  options.customNixOSModules.topolvmVg = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable the TopoLVM volume group setup helper script.
      '';
    };
    diskId = mkOption {
      type = types.str;
      description = ''
        Stable disk identifier under /dev/disk/by-id/ to use as the
        physical volume for the TopoLVM volume group.
      '';
      example = "wwn-0x50014ee2b5e1aa70";
    };
    volumeGroupName = mkOption {
      type = types.str;
      default = "topolvm-vg";
      description = ''
        Name of the LVM volume group to create for TopoLVM.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.lvm2
      (pkgs.writeShellScriptBin "topolvm-setup-vg" ''
        set -euo pipefail

        DISK="/dev/disk/by-id/${cfg.diskId}"
        VG_NAME="${cfg.volumeGroupName}"

        if [ "$(id -u)" -ne 0 ]; then
          echo "Error: must run as root"
          exit 1
        fi

        if ! [ -e "$DISK" ]; then
          echo "Error: disk $DISK not found"
          exit 1
        fi

        if vgs "$VG_NAME" &>/dev/null; then
          echo "Volume group '$VG_NAME' already exists:"
          vgs "$VG_NAME"
          exit 0
        fi

        echo "Creating physical volume on $DISK..."
        pvcreate "$DISK"

        echo "Creating volume group '$VG_NAME' on $DISK..."
        vgcreate "$VG_NAME" "$DISK"

        echo "Done."
        vgs "$VG_NAME"
      '')
    ];
  };
}
