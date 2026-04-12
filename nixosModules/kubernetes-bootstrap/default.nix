{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.customNixOSModules.kubernetesBootstrap;
in
{
  options.customNixOSModules.kubernetesBootstrap = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable Kubernetes bootstrap scripts.
      '';
    };
    podCIDR = mkOption {
      type = types.str;
      default = "10.244.0.0/16";
      description = ''
        The Pod Network CIDR to use for Kubernetes.
      '';
    };
    kubernetesVersion = mkOption {
      type = types.str;
      default = config.customNixOSModules.kubernetes.version.kubeadm; # Rely on the other module's version
      description = ''
        The Kubernetes version to use for kubeadm init.
      '';
    };

    dnsDomain = mkOption {
      type = types.str;
      default = "cluster.local";
      description = ''
        The DNS domain for Kubernetes services.
      '';
    };

    serviceSubnet = mkOption {
      type = types.str;
      default = "10.96.0.0/12";
      description = ''
        The Service Network CIDR for Kubernetes.
      '';
    };

    advertiseAddress = mkOption {
      type = types.str;
      default = "";
      description = ''
        The IP address the API Server advertises to other cluster members.
        Leave empty for kubeadm to auto-detect.
      '';
    };

    bindPort = mkOption {
      type = types.int;
      default = 6443;
      description = ''
        The port for the API Server to bind to.
      '';
    };

    clusterName = mkOption {
      type = types.str;
      default = "kubernetes";
      description = ''
        The name of the Kubernetes cluster.
      '';
    };
  };

  config = mkIf cfg.enable (
    let
      # Dynamically generated kubeadm configuration YAML
      # This content is not an option itself, but generated from other options.
      generatedKubeadmConfigYamlContent = ''
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: InitConfiguration
        localAPIEndpoint:
          advertiseAddress: "${cfg.advertiseAddress}"
          bindPort: ${toString cfg.bindPort}
        nodeRegistration:
          name: "${config.networking.hostName}"
          taints: []
        ---
        apiVersion: kubeadm.k8s.io/v1beta3
        kind: ClusterConfiguration
        kubernetesVersion: "${cfg.kubernetesVersion}"
        networking:
          podSubnet: "${cfg.podCIDR}"
          serviceSubnet: "${cfg.serviceSubnet}"
          dnsDomain: "${cfg.dnsDomain}"
        clusterName: "${cfg.clusterName}" # Use the configurable clusterName
      '';

      kubeadmConfigStorePath = pkgs.writeText "kubeadm-init-config.yaml" generatedKubeadmConfigYamlContent;
    in
    {
      environment.etc."kubeadm-init-config.yaml".source = kubeadmConfigStorePath;

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "k8s-init-controlplane" ''
          #!/usr/bin/env bash
          set -euo pipefail

          KUBEADM_CONFIG_FILE="${kubeadmConfigStorePath}"

          echo "Initializing control plane using config file: $KUBEADM_CONFIG_FILE"

          kubeadm init --config "$KUBEADM_CONFIG_FILE"

          mkdir -p "$HOME/.kube"
          cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"

          echo "Control plane initialized." # Removed reference to k8s-install-cni
        '')
      ];
    }
  );
}
