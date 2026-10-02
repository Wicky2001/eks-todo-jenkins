###############################################################################
# argo cd
###############################################################################

resource "kubernetes_namespace_v1" "argocd_namespace" {
  metadata {
    name = "argocd"
  }
}

data "http" "argocd_manifest" {
  url = "https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml"
}

/*
  install argo cd controller
*/
resource "kubectl_manifest" "argocd" {
  for_each = { for doc in split("---", data.http.argocd_manifest.response_body) :
    sha256(doc) => doc if trimspace(doc) != ""
  }

  yaml_body          = each.value
  override_namespace = "argocd"
  server_side_apply  = true
  force_conflicts    = true


  depends_on = [kubernetes_namespace_v1.argocd_namespace]
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

  depends_on = [kubectl_manifest.argocd]
}

resource "kubectl_manifest" "argocd_application" {
  yaml_body = file("${path.root}/../../k8s/argocd/argocd-app.yaml")

  depends_on = [kubectl_manifest.argocd_project]
}
