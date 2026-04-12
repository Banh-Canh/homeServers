{
  config,
  pkgs,
  lib,
  sources,
  hephaestusPath,
  ...
}:
let
  overrides = {
    customHomeManagerModules = { };
    imports = [ ./fastfetchConfig.nix ];
  };
in
{
  boot = {
    initrd = {
      availableKernelModules = [
        "ehci_pci"
        "ata_piix"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      kernelModules = [
        "dm_snapshot"
        "dm-thin-pool"
      ];
    };
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];
    kernelParams = [ "elevator=none" ];
    loader.grub = {
      enable = true;
      # After install, replace with stable id from `ls -l /dev/disk/by-id/ | grep -v part`
      devices = [ "/dev/disk/by-id/wwn-0x5001b448be9efd29" ];
    };
  };
  fileSystems."/" = {
    device = "/dev/disk/by-label/ROOT";
    fsType = "ext4";
    options = [
      "noatime"
      "nodiratime"
      "discard"
    ];
  };
  swapDevices = [ ];
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  customNixOSModules = {
    networkManager.enable = true;
    kubernetesBootstrap = {
      enable = true;
      # Explicitly setting defaults for clarity
      podCIDR = "10.244.0.0/16";
      kubernetesVersion = config.customNixOSModules.kubernetes.version.kubeadm;
      dnsDomain = "banh-canh.local";
      serviceSubnet = "10.96.0.0/16";
      advertiseAddress = ""; # Leave empty for kubeadm auto-detect
      bindPort = 6443;
      clusterName = "banh-canh";
    };
    kubernetes = {
      enable = true;
      version = {
        kubeadm = "v1.35.3";
        kubelet = "v1.35.3";
      };
    };
    caCertificates = {
      didactiklabs.enable = true;
    };
    ginx = {
      enable = true;
      repositoryUrl = "https://github.com/Banh-Canh/homeServers"; # TODO: Update with your actual remote URL
      repositoryBranch = "main";
    };
    kubernetesGitops = {
      enable = true;
      cilium.k8sServiceHost = "10.207.7.2";
      flux.clusterPath = "./kubernetes/clusters/homelab";
    };
    topolvmVg = {
      enable = true;
      diskId = "ata-ST2000DM008-2FR102_ZFL3WLE1"; # Run: ls -l /dev/disk/by-id/ | grep sda
      volumeGroupName = "topolvm-vg";
    };
  };

  imports = [
    ../../nixosModules/networkManager.nix
    ../../nixosModules/kubernetes-bootstrap # Import the new module
    ../../nixosModules/kubernetes-gitops
    ../../nixosModules/topolvm-vg
    (import ../../users/homelab {
      inherit
        config
        pkgs
        lib
        sources
        hephaestusPath
        overrides
        ;
    })
  ];
}
