# cert-manager: gets Let's Encrypt certificates for the gateway and renews them
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.18.2"

  values = [
    yamlencode({
      # installs the Certificate, ClusterIssuer, ... resource types
      crds = { enabled = true }

      # lets cert-manager answer the Let's Encrypt check with an HTTPRoute.
      # The Gateway API types must exist before cert-manager starts.
      config = {
        apiVersion       = "controller.config.cert-manager.io/v1alpha1"
        kind             = "ControllerConfiguration"
        enableGatewayAPI = true
      }

      tolerations     = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
      webhook         = { tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }] }
      cainjector      = { tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }] }
      startupapicheck = { tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }] }
    })
  ]
}

# Let's Encrypt issuers. templatefile fills in your email (from terraform.tfvars).

# staging: for testing, browsers don't trust it
resource "kubectl_manifest" "letsencrypt_staging" {
  yaml_body = templatefile("${path.root}/../../k8s/cert-manager/letsencrypt-staging.yaml", { email = var.letsencrypt_email })

  depends_on = [helm_release.cert_manager]
}

# prod: real, trusted certificates
resource "kubectl_manifest" "letsencrypt_prod" {
  yaml_body = templatefile("${path.root}/../../k8s/cert-manager/letsencrypt-prod.yaml", { email = var.letsencrypt_email })

  depends_on = [helm_release.cert_manager]
}
