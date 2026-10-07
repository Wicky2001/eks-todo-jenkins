###############################################################################
# Install Argo CD controller
###############################################################################
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
}

###############################################################################
# Argo CD UI over HTTPS at argocd.jawsight.online (ingress-nginx + cert-manager)
###############################################################################
resource "kubectl_manifest" "argocd_ingress" {
  yaml_body = file("${path.root}/../../k8s/argocd/argocd-ingress.yaml")

  depends_on = [helm_release.argocd]
}




###############################################################################
# Argo CD Project
###############################################################################
resource "kubectl_manifest" "argocd_project" {
  yaml_body = file("${path.root}/../../k8s/argocd/argocd-project.yaml")

  depends_on = [helm_release.argocd]
}


###############################################################################
# Argo CD Application files
###############################################################################
resource "kubectl_manifest" "argocd_application" {
  yaml_body = file("${path.root}/../../k8s/argocd/argocd-app.yaml")

  depends_on = [helm_release.argocd]
}
