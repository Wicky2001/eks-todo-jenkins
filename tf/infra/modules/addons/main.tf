# metrics-server: CPU and memory numbers for kubectl top and autoscaling
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.1"

  # don't block terraform apply while the pod starts
  wait = false

  values = [
    <<-EOT
    # allow it on the add-on node group (it has the CriticalAddonsOnly taint)
    tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
        effect: "NoSchedule"

    # the kubelets use self-signed certificates on EKS
    args:
      - --kubelet-insecure-tls
    EOT
  ]
}

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

# Creates the NLB for Services of type LoadBalancer (the ingress-nginx Service)
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

# ingress-nginx: routes requests from the NLB to the apps (values in k8s/ingress-nginx)
resource "helm_release" "ingress-nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.15.1"
  values           = [file("${path.root}/../../k8s/ingress-nginx/helm-values.yaml")]

  depends_on = [helm_release.aws_load_balancer_controller]
}

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

# cert-manager: gets Let's Encrypt certificates for the Ingresses and renews them
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.18.2"

  values = [
    yamlencode({
      # installs the Certificate, ClusterIssuer, ... resource types
      crds = { enabled = true }

      tolerations     = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
      webhook         = { tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }] }
      cainjector      = { tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }] }
      startupapicheck = { tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }] }
    })
  ]

  depends_on = [helm_release.ingress-nginx]
}

# Let's Encrypt issuers: staging for testing, prod for real certificates
resource "kubectl_manifest" "cluster_issuers" {
  for_each = { for i, doc in split("---", templatefile("${path.root}/../../k8s/cert-manager/cluster-issuers.yaml", { email = var.letsencrypt_email })) : i => doc if trimspace(doc) != "" }

  yaml_body = each.value

  depends_on = [helm_release.cert_manager]
}
