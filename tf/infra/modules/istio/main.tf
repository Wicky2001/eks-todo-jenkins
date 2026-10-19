# Istio in ambient mode, and the cluster's front door (main-gateway)

###############################################################################
# Chart and image settings
###############################################################################
# Istio moved its charts here; the old istio-release.storage.googleapis.com is being shut down.
# Images come from Docker Hub, because the charts' default registry is being retired too.
locals {
  istio_charts  = "https://blob.istio.io/istio-release/charts"
  istio_version = "1.30.5"
  istio_images  = "docker.io/istio"
}

###############################################################################
# Istio base
###############################################################################
# Istio's own resource types (PeerAuthentication, AuthorizationPolicy, ...)
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = local.istio_charts
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
  version          = local.istio_version
}

###############################################################################
# istiod
###############################################################################
# istiod: the brain. Watches Services, sends member lists to ztunnel and Envoy, and
# gives every mesh pod an ID certificate. It also runs the Gateway objects: for each
# one it creates Envoy pods and a LoadBalancer Service (which becomes the NLB).
resource "helm_release" "istiod" {
  name       = "istiod"
  repository = local.istio_charts
  chart      = "istiod"
  namespace  = helm_release.istio_base.namespace
  version    = local.istio_version

  values = [
    yamlencode({
      profile     = "ambient"
      global      = { hub = local.istio_images }
      tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
    })
  ]

  depends_on = [helm_release.istio_base]
}

###############################################################################
# istio-cni
###############################################################################
# istio-cni (DaemonSet, one per node): when a pod starts in a mesh namespace, it adds
# the redirect rule inside the pod and gives ztunnel a key to the pod's network.
# It already runs on every node and skips kube-system by default.
resource "helm_release" "istio_cni" {
  name       = "istio-cni"
  repository = local.istio_charts
  chart      = "cni"
  namespace  = helm_release.istio_base.namespace
  version    = local.istio_version

  values = [
    yamlencode({
      profile = "ambient"
      global  = { hub = local.istio_images }
    })
  ]

  depends_on = [helm_release.istiod]
}

###############################################################################
# ztunnel
###############################################################################
# ztunnel (DaemonSet, one per node): opens sockets inside every mesh pod on its node
# and carries pod-to-pod traffic through encrypted mTLS tunnels
resource "helm_release" "ztunnel" {
  name       = "ztunnel"
  repository = local.istio_charts
  chart      = "ztunnel"
  namespace  = helm_release.istio_base.namespace
  version    = local.istio_version

  values = [
    yamlencode({
      hub = local.istio_images
    })
  ]

  depends_on = [helm_release.istio_cni]
}

###############################################################################
# Gateway namespace
###############################################################################
# The front door: one Gateway for todo, argocd and grafana.
# One resource per file in k8s/istio.
resource "kubernetes_namespace_v1" "istio_ingress" {
  metadata {
    name = "istio-ingress"
  }
}

###############################################################################
# Gateway pod settings
###############################################################################
# settings for the gateway pods (replicas, tolerations, ...), read by main-gateway
resource "kubectl_manifest" "main_gateway_options" {
  yaml_body = file("${path.root}/../../k8s/istio/main-gateway-options.yaml")

  depends_on = [kubernetes_namespace_v1.istio_ingress]
}

###############################################################################
# Main gateway
###############################################################################
# the Gateway itself: its doors (listeners) and how to build its NLB
resource "kubectl_manifest" "main_gateway" {
  yaml_body = file("${path.root}/../../k8s/istio/main-gateway.yaml")

  depends_on = [helm_release.istiod, kubectl_manifest.main_gateway_options]
}

###############################################################################
# HTTP to HTTPS redirect
###############################################################################
# http:// to https:// for every site
resource "kubectl_manifest" "http_redirect" {
  yaml_body = file("${path.root}/../../k8s/istio/http-redirect.yaml")

  depends_on = [kubectl_manifest.main_gateway]
}

###############################################################################
# todo certificate
###############################################################################
# HTTPS certificates for the three listeners (cert-manager creates the Secrets)
resource "kubectl_manifest" "todo_certificate" {
  yaml_body = file("${path.root}/../../k8s/istio/todo-certificate.yaml")

  depends_on = [kubectl_manifest.main_gateway]
}

###############################################################################
# argocd certificate
###############################################################################
# Certificate for argocd.jawsight.online.
resource "kubectl_manifest" "argocd_certificate" {
  yaml_body = file("${path.root}/../../k8s/istio/argocd-certificate.yaml")

  depends_on = [kubectl_manifest.main_gateway]
}

###############################################################################
# grafana certificate
###############################################################################
# Certificate for grafana.jawsight.online.
resource "kubectl_manifest" "grafana_certificate" {
  yaml_body = file("${path.root}/../../k8s/istio/grafana-certificate.yaml")

  depends_on = [kubectl_manifest.main_gateway]
}
