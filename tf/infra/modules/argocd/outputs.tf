output "argocd_namespace" {
  value = kubernetes_namespace_v1.argocd_namespace.metadata[0].name
}
