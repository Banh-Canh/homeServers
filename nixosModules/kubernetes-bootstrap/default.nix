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
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "k8s-init-controlplane" ''
        #!/usr/bin/env bash
        set -euo pipefail

        POD_CIDR="${cfg.podCIDR}"
        KUBERNETES_VERSION="${cfg.kubernetesVersion}"

        echo "Initializing control plane with pod-cidr: $POD_CIDR"

        kubeadm init \
            --pod-network-cidr="$POD_CIDR" \
            --service-cidr=10.96.0.0/12 \
            --kubernetes-version="$KUBERNETES_VERSION"

        mkdir -p "$HOME/.kube"
        cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"

        echo "Control plane initialized. Run 'k8s-install-cni' next."
      '')

      (pkgs.writeShellScriptBin "k8s-install-cni" ''
        #!/usr/bin/env bash
        set -euo pipefail

        export KUBECONFIG="''${KUBECONFIG:-$HOME/.kube/config}"
        POD_CIDR="${cfg.podCIDR}"

        echo "Installing Flannel CNI with pod-cidr: $POD_CIDR"
        kubectl apply -f "https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"

        echo "CNI installed. Checking nodes..."
        kubectl get nodes
      '')

      (pkgs.writeShellScriptBin "k8s-join-worker" ''
        #!/usr/bin/env bash
        set -euo pipefail

        if [[ -z "''${1:-}" ]]; then
            echo "Usage: k8s-join-worker <join-command>"
            echo ""
            echo "Get the join command from the control plane:"
            echo "  kubeadm token create --print-join-command"
            exit 1
        fi

        echo "Running: $1"
        eval "$1"
        echo "Worker node joined."
      '')
    ];
  };
}
