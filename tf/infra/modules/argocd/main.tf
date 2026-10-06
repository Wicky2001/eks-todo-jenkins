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

# Patch ArgoCD server service to LoadBalancer
# resource "terraform_data" "patch_argocd_service" {
#   provisioner "local-exec" {
#     interpreter = ["PowerShell", "-Command"]

#     command = <<-EOT
#       # Update kubeconfig first
#       aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}

#       # Wait a bit for service to be created
#       Start-Sleep -Seconds 20

#       # Patch service to LoadBalancer (escaped double quotes for PowerShell to pass to kubectl safely)
#       kubectl patch svc argocd-server -n argocd -p '{\"spec\": {\"type\": \"LoadBalancer\"}}'
#     EOT
#   }

#   depends_on = [kubectl_manifest.argocd]
# }



resource "kubectl_manifest" "argocd_project" {
  yaml_body = file("${path.root}/../../k8s/argocd/argocd-project.yaml")

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "argocd_application" {
  yaml_body = file("${path.root}/../../k8s/argocd/argocd-app.yaml")

  depends_on = [helm_release.argocd]
}
