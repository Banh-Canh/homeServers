{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.customNixOSModules.kubernetesGitops;
  bootstrap = config.customNixOSModules.kubernetesBootstrap;
  ginx = config.customNixOSModules.ginx;

  ciliumValuesContent = ''
    kubeProxyReplacement: true
    k8sServiceHost: "${cfg.cilium.k8sServiceHost}"
    k8sServicePort: ${toString bootstrap.bindPort}
    socketLB:
      hostNamespaceOnly: true
    envoy:
      enabled: false
    cni:
      exclusive: false
    ipam:
      operator:
        clusterPoolIPv4PodCIDRList:
          - "${bootstrap.podCIDR}"
        clusterPoolIPv4MaskSize: ${toString cfg.cilium.podCIDRMaskSize}
  '';

  ciliumValuesFile = pkgs.writeText "cilium-bootstrap-values.yaml" ciliumValuesContent;
in
{
  options.customNixOSModules.kubernetesGitops = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable Kubernetes gitops bootstrap scripts.";
    };

    cilium = {
      chartVersion = mkOption {
        type = types.str;
        default = "1.18.6";
        description = "Cilium Helm chart version.";
      };
      k8sServiceHost = mkOption {
        type = types.str;
        description = "IP address of the Kubernetes API server for Cilium.";
        example = "10.207.7.2";
      };
      podCIDRMaskSize = mkOption {
        type = types.int;
        default = 23;
        description = "Per-node pod CIDR mask size.";
      };
    };

    flux = {
      clusterPath = mkOption {
        type = types.str;
        description = "Path within the repo for this cluster's manifests.";
        example = "./kubernetes/clusters/homelab";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.kubernetes-helm

      (pkgs.writeShellScriptBin "k8s-bootstrap-cni" ''
        set -euo pipefail

        if [ "$(id -u)" -ne 0 ]; then
          echo "Error: must run as root"
          exit 1
        fi

        export KUBECONFIG="''${KUBECONFIG:-/etc/kubernetes/admin.conf}"

        echo "Adding Cilium Helm repository..."
        ${pkgs.kubernetes-helm}/bin/helm repo add cilium https://helm.cilium.io/ --force-update
        ${pkgs.kubernetes-helm}/bin/helm repo update cilium

        echo "Installing Cilium ${cfg.cilium.chartVersion}..."
        ${pkgs.kubernetes-helm}/bin/helm upgrade --install cilium cilium/cilium \
          --version "${cfg.cilium.chartVersion}" \
          --namespace kube-system \
          --values "${ciliumValuesFile}" \
          --wait \
          --timeout 5m

        echo "Cilium installed. Waiting for pods to be ready..."
        ${pkgs.kubectl}/bin/kubectl wait --for=condition=Ready pods \
          -l app.kubernetes.io/part-of=cilium \
          -n kube-system \
          --timeout=120s

        echo "CNI bootstrap complete."
      '')

      (pkgs.writeShellScriptBin "k8s-bootstrap-flux" ''
        set -euo pipefail

        if [ "$(id -u)" -ne 0 ]; then
          echo "Error: must run as root"
          exit 1
        fi

        export KUBECONFIG="''${KUBECONFIG:-/etc/kubernetes/admin.conf}"

        CLUSTER_PATH="${cfg.flux.clusterPath}"
        CLUSTER_PATH="''${CLUSTER_PATH#./}"

        WORK_DIR=$(mktemp -d)
        trap "rm -rf $WORK_DIR" EXIT

        echo "Cloning ${ginx.repositoryUrl} (${ginx.repositoryBranch})..."
        ${pkgs.git}/bin/git clone --depth 1 --branch "${ginx.repositoryBranch}" \
          "${ginx.repositoryUrl}" "$WORK_DIR/repo"

        echo "Installing Flux Operator..."
        ${pkgs.kubectl}/bin/kubectl apply -k "$WORK_DIR/repo/kubernetes/infrastructure/fluxcd/operator"

        echo "Waiting for Flux Operator to be ready..."
        ${pkgs.kubectl}/bin/kubectl wait --for=condition=Available \
          deployment/flux-operator \
          -n flux-system \
          --timeout=120s

        echo "Applying FluxInstance..."
        ${pkgs.kubectl}/bin/kubectl apply -k "$WORK_DIR/repo/$CLUSTER_PATH/fluxcd"

        echo "Flux bootstrap complete. Flux will now reconcile from:"
        echo "  repo:   ${ginx.repositoryUrl}"
        echo "  branch: ${ginx.repositoryBranch}"
        echo "  path:   ${cfg.flux.clusterPath}"
      '')
    ];
  };
}
