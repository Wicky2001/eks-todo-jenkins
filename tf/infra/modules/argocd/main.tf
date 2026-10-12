# Argo CD
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
}

# https://argocd.jawsight.online
resource "kubectl_manifest" "argocd_ingress" {
  yaml_body = file("${path.root}/../../k8s/argocd/argocd-ingress.yaml")

  depends_on = [helm_release.argocd]
}

# the project and the app that Argo CD keeps in sync with the GitOps repo
resource "kubectl_manifest" "argocd_project" {
  yaml_body = file("${path.root}/../../k8s/argocd/argocd-project.yaml")

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "argocd_application" {
  yaml_body = file("${path.root}/../../k8s/argocd/argocd-app.yaml")

  depends_on = [helm_release.argocd]
}
