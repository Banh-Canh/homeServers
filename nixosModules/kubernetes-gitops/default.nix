{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.customNixOSModules.kubernetesGitops;

  ciliumValuesContent = ''
    kubeProxyReplacement: true
    k8sServiceHost: "${cfg.cilium.k8sServiceHost}"
    k8sServicePort: ${toString cfg.cilium.k8sServicePort}
    socketLB:
      hostNamespaceOnly: true
    envoy:
      enabled: false
    cni:
      exclusive: false
    ipam:
      operator:
        clusterPoolIPv4PodCIDRList:
          - "${cfg.cilium.podCIDR}"
        clusterPoolIPv4MaskSize: ${toString cfg.cilium.podCIDRMaskSize}
  '';

  ciliumValuesFile = pkgs.writeText "cilium-bootstrap-values.yaml" ciliumValuesContent;

  fluxInstanceContent = ''
    apiVersion: fluxcd.controlplane.io/v1
    kind: FluxInstance
    metadata:
      name: flux
      namespace: flux-system
    spec:
      distribution:
        version: "2.x"
        registry: "ghcr.io/fluxcd"
      components:
        - source-controller
        - kustomize-controller
        - helm-controller
        - notification-controller
      cluster:
        type: kubernetes
        multitenant: false
        networkPolicy: true
        domain: "${cfg.flux.clusterDomain}"
      kustomize:
        patches:
          - target:
              kind: Deployment
              name: "(kustomize-controller|helm-controller)"
            patch: |
              - op: add
                path: /spec/template/spec/containers/0/args/-
                value: --concurrent=42
      sync:
        kind: GitRepository
        url: "${cfg.flux.repositoryUrl}"
        ref: "refs/heads/${cfg.flux.repositoryBranch}"
        path: "${cfg.flux.clusterPath}"
        interval: "1m"
  '';

  fluxInstanceFile = pkgs.writeText "flux-instance.yaml" fluxInstanceContent;

  fluxOperatorUrl = "https://github.com/controlplaneio-fluxcd/flux-operator/releases/download/${cfg.flux.operatorVersion}/install.yaml";
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
      k8sServicePort = mkOption {
        type = types.int;
        default = 6443;
        description = "Port of the Kubernetes API server for Cilium.";
      };
      podCIDR = mkOption {
        type = types.str;
        default = "10.244.0.0/16";
        description = "Pod network CIDR.";
      };
      podCIDRMaskSize = mkOption {
        type = types.int;
        default = 23;
        description = "Per-node pod CIDR mask size.";
      };
    };

    flux = {
      operatorVersion = mkOption {
        type = types.str;
        default = "v0.40.0";
        description = "Flux Operator release version.";
      };
      repositoryUrl = mkOption {
        type = types.str;
        description = "Git repository URL for Flux to sync.";
        example = "https://github.com/Banh-Canh/homeServers.git";
      };
      repositoryBranch = mkOption {
        type = types.str;
        default = "main";
        description = "Git branch for Flux to sync.";
      };
      clusterPath = mkOption {
        type = types.str;
        description = "Path within the repo for this cluster's manifests.";
        example = "./kubernetes/clusters/homelab";
      };
      clusterDomain = mkOption {
        type = types.str;
        default = "cluster.local";
        description = "Kubernetes cluster domain.";
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

        echo "Installing Flux Operator ${cfg.flux.operatorVersion}..."
        ${pkgs.kubectl}/bin/kubectl apply -f "${fluxOperatorUrl}"

        echo "Waiting for Flux Operator to be ready..."
        ${pkgs.kubectl}/bin/kubectl wait --for=condition=Available \
          deployment/flux-operator \
          -n flux-system \
          --timeout=120s

        echo "Applying FluxInstance..."
        ${pkgs.kubectl}/bin/kubectl apply -f "${fluxInstanceFile}"

        echo "Flux bootstrap complete. Flux will now reconcile from:"
        echo "  repo:   ${cfg.flux.repositoryUrl}"
        echo "  branch: ${cfg.flux.repositoryBranch}"
        echo "  path:   ${cfg.flux.clusterPath}"
      '')
    ];
  };
}
