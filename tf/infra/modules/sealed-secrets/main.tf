# sealed-secrets: decrypts SealedSecret objects into normal Secrets inside the cluster
resource "helm_release" "sealed_secrets" {
  name             = "sealed-secrets"
  chart            = "https://github.com/bitnami-labs/sealed-secrets/releases/download/helm-v2.15.3/sealed-secrets-2.15.3.tgz"
  namespace        = "kube-system"
  create_namespace = false

  values = [
    yamlencode({
      fullnameOverride = "sealed-secrets-controller"

      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]
}
