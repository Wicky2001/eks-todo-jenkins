# AWS add-ons that run inside the cluster

###############################################################################
# Load Balancer Controller IAM role
###############################################################################
# IAM role for the AWS Load Balancer Controller (Pod Identity)
module "aws_lb_controller_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "${var.cluster_name}-aws-lb-controller-iam"

  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller-sa"
    }
  }

  tags = {
    Environment = "production"
  }
}

###############################################################################
# AWS Load Balancer Controller
###############################################################################
# Creates the NLB for Services of type LoadBalancer (the Istio gateway Service)
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

  depends_on = [module.aws_lb_controller_pod_identity]
}
