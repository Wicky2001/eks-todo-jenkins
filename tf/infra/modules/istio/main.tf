# Istio and the cluster's front door (main-gateway)

# Istio: "base" installs Istio's own resource types, istiod is the control plane.
# istiod also runs the Gateway objects: for each one it creates Envoy pods and a
# LoadBalancer Service (which becomes the NLB).
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.30.5"
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = helm_release.istio_base.namespace
  version    = "1.30.5"

  values = [
    yamlencode({
      tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
    })
  ]

  depends_on = [helm_release.istio_base]
}

# The front door: one Gateway for todo, argocd and grafana.
# One resource per file in k8s/istio.
resource "kubernetes_namespace_v1" "istio_ingress" {
  metadata {
    name = "istio-ingress"
  }
}

# settings for the gateway pods (replicas, tolerations, ...), read by main-gateway
resource "kubectl_manifest" "main_gateway_options" {
  yaml_body = file("${path.root}/../../k8s/istio/main-gateway-options.yaml")

  depends_on = [kubernetes_namespace_v1.istio_ingress]
}

# the Gateway itself: its doors (listeners) and how to build its NLB
resource "kubectl_manifest" "main_gateway" {
  yaml_body = file("${path.root}/../../k8s/istio/main-gateway.yaml")

  depends_on = [helm_release.istiod, kubectl_manifest.main_gateway_options]
}

# http:// to https:// for every site
resource "kubectl_manifest" "http_redirect" {
  yaml_body = file("${path.root}/../../k8s/istio/http-redirect.yaml")

  depends_on = [kubectl_manifest.main_gateway]
}

# HTTPS certificates for the three listeners (cert-manager creates the Secrets)
resource "kubectl_manifest" "todo_certificate" {
  yaml_body = file("${path.root}/../../k8s/istio/todo-certificate.yaml")

  depends_on = [kubectl_manifest.main_gateway]
}

resource "kubectl_manifest" "argocd_certificate" {
  yaml_body = file("${path.root}/../../k8s/istio/argocd-certificate.yaml")

  depends_on = [kubectl_manifest.main_gateway]
}

resource "kubectl_manifest" "grafana_certificate" {
  yaml_body = file("${path.root}/../../k8s/istio/grafana-certificate.yaml")

  depends_on = [kubectl_manifest.main_gateway]
}
