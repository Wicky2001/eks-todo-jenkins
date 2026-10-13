# Argo CD
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  values = [
    file("${path.root}/../../k8s/argocd/helm-values.yaml"),
    templatefile("${path.root}/../../k8s/argocd/argocd-github-sso.yaml", {
      github_org = var.github_org
      client_id  = var.github_client_id
    })
  ]
}

# GitHub OAuth App secret for Dex. Argo CD only reads Secrets that carry the
# part-of: argocd label.
resource "kubernetes_secret_v1" "argocd_github_oauth" {
  metadata {
    name      = "argocd-github-oauth"
    namespace = helm_release.argocd.namespace
    labels = {
      "app.kubernetes.io/part-of" = "argocd"
    }
  }
  data = {
    clientSecret = var.github_client_secret
  }
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
