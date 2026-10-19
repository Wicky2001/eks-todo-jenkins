# Argo CD

###############################################################################
# Argo CD namespace
###############################################################################
# created here instead of by Helm, so it can carry the mesh label
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
    # join the Istio mesh (ambient mode): gateway -> argocd-server and the traffic
    # between the Argo CD parts get mTLS
    labels = {
      "istio.io/dataplane-mode" = "ambient"
    }
  }
}

###############################################################################
# Argo CD
###############################################################################
# The Argo CD chart, with the values and GitHub login from k8s/argocd/install.
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [
    file("${path.root}/../../k8s/argocd/install/helm-values.yaml"),
    templatefile("${path.root}/../../k8s/argocd/install/argocd-github-sso.yaml", {
      github_org = var.github_org
      client_id  = var.github_client_id
    })
  ]
}

###############################################################################
# GitHub login secret
###############################################################################
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

###############################################################################
# Argo CD route
###############################################################################
# https://argocd.jawsight.online (an HTTPRoute on main-gateway)
resource "kubectl_manifest" "argocd_route" {
  yaml_body = file("${path.root}/../../k8s/argocd/install/argocd-route.yaml")

  depends_on = [helm_release.argocd]
}

###############################################################################
# Bootstrap project
###############################################################################
# Bootstrap: the only Argo CD project and app Terraform creates (k8s/argocd/bootstrap).
# The bootstrap app reads the GitOps repo's argocd/ folder and creates everything else
# from Git: the apps and platform projects, and the backend, frontend, monitoring,
# logging and tracing cards.
resource "kubectl_manifest" "bootstrap_project" {
  yaml_body = file("${path.root}/../../k8s/argocd/bootstrap/bootstrap-project.yaml")

  depends_on = [helm_release.argocd]
}

###############################################################################
# Bootstrap app
###############################################################################
# wait = true: on destroy, wait until Argo CD has deleted the cards and what they deployed
resource "kubectl_manifest" "bootstrap_app" {
  yaml_body = file("${path.root}/../../k8s/argocd/bootstrap/bootstrap-app.yaml")
  wait      = true

  depends_on = [kubectl_manifest.bootstrap_project]
}
