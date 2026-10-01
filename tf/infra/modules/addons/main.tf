###############################################################################
# Install Metrics Server Addon via helm
###############################################################################
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.1"

  # wait = false stops Terraform from freezing if the cluster is busy
  wait = false

  # We pass the custom settings directly to the app here
  values = [
    <<-EOT
    # 1. The VIP Key to let it sit on your reserved t3.small nodes
    tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
        effect: "NoSchedule"

    # 2. Stops it from crashing due to AWS self-signed security certificates
    args:
      - --kubelet-insecure-tls
    EOT
  ]
}








# module "iam_iam-role-for-service-accounts" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
#   version = "6.6.1"

#   # Updated to match the v6.x variable list
#   name                                   = "${var.cluster_name}-aws-lbc"
#   attach_load_balancer_controller_policy = true

#   oidc_providers = {
#     main = {
#       provider_arn               = module.eks.oidc_provider_arn
#       namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
#     }
#   }
# }

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"


  values = [
    yamlencode({
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]

  set = [{
    name  = "clusterName"
    value = var.cluster_name
    },
    {
      name  = "region"
      value = var.region
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller-sa"
    },
  ]

}

###############################################################################
# Install nginx ingress controller via helm, using a custom values.yaml file for configuration
###############################################################################

resource "helm_release" "ingress-nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.15.1"
  values           = [file("${path.root}/../../k8s/helm_config/helm-nginx-cofiguration.yaml")]

  depends_on = [helm_release.aws_load_balancer_controller]

}

###############################################################################
# Install Sealed Secrets Controller via helm
###############################################################################

resource "helm_release" "sealed_secrets" {
  name             = "sealed-secrets"
  chart            = "https://github.com/bitnami-labs/sealed-secrets/releases/download/helm-v2.15.3/sealed-secrets-2.15.3.tgz"
  namespace        = "kube-system"
  create_namespace = false

  values = [
    yamlencode({
      fullnameOverride = "sealed-secrets-controller"

      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]

}
