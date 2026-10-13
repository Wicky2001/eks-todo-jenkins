# metrics-server: CPU and memory numbers for kubectl top and autoscaling
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.1"

  # don't block terraform apply while the pod starts
  wait = false

  values = [
    <<-EOT
    # allow it on the add-on node group (it has the CriticalAddonsOnly taint)
    tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
        effect: "NoSchedule"

    # the kubelets use self-signed certificates on EKS
    args:
      - --kubelet-insecure-tls
    EOT
  ]
}
