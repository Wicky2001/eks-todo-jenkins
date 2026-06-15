###############################################################################
# Provider
###############################################################################
terraform {
  backend "s3" {
    bucket = "terraform-backend-state-file-karpenter"
    region = "ap-south-1"
    key    = "karpenter.tfstate"
  }


  /*
  This block download the providers codes 
  Later using the provider block we configure them.
  */
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.5.0"
    }
  }
}


provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]
  profile             = var.aws_profile
}

provider "aws" {
  region  = "us-east-1"
  alias   = "virginia"
  profile = var.aws_profile
}


###############################################################################
# Data Sources
###############################################################################
/* AUTHENTICATION NOTE: 
  We keep the 'aws_ecrpublic_authorization_token' data source even though the 
  Karpenter repo is public. 

  WHY? 
  AWS enforces strict anonymous rate limits on Public ECR. If we don't provide 
  an authentication token, AWS identifies us by our IP address. If we run 
  'terraform apply' multiple times (or run this in a shared CI/CD pipeline), 
  AWS will eventually block us with a '429 Too Many Requests' error.

  Providing the token tells AWS we are a registered customer, which lifts 
  these limits and ensures our deployment remains 100% reliable.
*/
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}



provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

/*
Teach helm how to log in to the EKS cluster
*/
provider "helm" {
  kubernetes = {
    host = module.eks.cluster_endpoint
    #This is the digital ID card of your cluster. It ensures Terraform is talking to your real cluster and not an imposter.
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      /*
      exec block: Instead of using a static, permanent password (which is a bad security practice),
       this block tells Terraform to execute a command on your local machine (aws eks get-token). 
       This generates a temporary, highly secure login token that lasts for only 15 minutes, 
       allowing Terraform to safely authenticate and install Helm charts.
      
      */
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }

  # registries = [{
  #   url      = "oci://public.ecr.aws"
  #   username = data.aws_ecrpublic_authorization_token.token.user_name
  #   password = data.aws_ecrpublic_authorization_token.token.password
  # }]
}



/*
While the helm provider installs packaged software, standard Terraform 
does not have a native way to apply raw Kubernetes YAML files 
(like your NodePool, EC2NodeClass, and your inflate deployment). 
The gavinbunney/kubectl provider acts as a bridge to let you write raw YAML directly 
inside Terraform.

*/
provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}




###############################################################################
# VPC
###############################################################################
module "vpc" {
  # The source code location for the official AWS VPC module
  source = "terraform-aws-modules/vpc/aws"
  # The specific version of the module to ensure consistent deployments
  version = "6.6.1"

  # Name used to identify this VPC in the AWS console
  name = "${var.cluster_name}-vpc"
  # The main IP address range (pool) for the entire VPC
  cidr = "10.0.0.0/16"

  # The three physical AWS data centers (Availability Zones) to distribute your resources across
  azs = ["${var.region}a", "${var.region}b", "${var.region}c"]

  # Private subnets: The "inside of the house." Instances here cannot be reached from the internet, 
  # but they can "look out the window" to download updates via a NAT Gateway.
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  # Public subnets: The "front yard." Instances here have direct access to the public internet, 
  # typically used for public-facing entry points.
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # Intra subnets: The "sealed safe room." These have zero access to the outside internet, 
  # not even for updates. EKS needs these to securely house the network cables (ENIs) 
  # that connect the Kubernetes 'brain' (Control Plane) to your worker nodes, 
  # ensuring that no external traffic can ever reach the control plane infrastructure.
  intra_subnets = ["10.0.104.0/24", "10.0.105.0/24", "10.0.106.0/24"]

  # Enable the NAT Gateway so private instances can reach out to the internet for updates
  enable_nat_gateway = true
  # Use only one NAT Gateway to save costs (instead of one per AZ)
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # Tag for public subnets so the AWS Load Balancer Controller knows where to place public load balancers.
  # This tag acts as a neon sign: 'Hey! This is a public subnet! You are allowed to build internet-facing 
  # load balancers right here.' The value '1' is a hardcoded AWS standard (meaning True). Using 'true', 
  # 'yes', or any other value will cause the AWS controller to ignore these subnets, and your load balancers will fail to create.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  # Tags for private subnets to handle internal traffic and auto-discovery
  private_subnet_tags = {
    # This acts as a 'neon sign' for internal components. It tells AWS: 'If Kubernetes asks for an 
    # internal-only, private load balancer (e.g., for frontend-to-database traffic), put it here.'
    # Like the public tag, the value '1' is a strict requirement for the AWS Load Balancer Controller.
    "kubernetes.io/role/internal-elb" = 1

    # This is the 'discovery' tag for Karpenter. Karpenter is the engine that builds your EC2 worker nodes. 
    # When it needs to launch a new node, it asks AWS: 'Give me subnets with this tag.' Because we only 
    # place this tag on private subnets, Karpenter will automatically and securely launch your 
    # EC2 instances in the private 'safe room', keeping them completely hidden from the public internet.
    "karpenter.sh/discovery" = var.cluster_name
  }
}

###############################################################################
# EKS
###############################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.23.0"

  name               = var.cluster_name
  kubernetes_version = "1.33"

  endpoint_public_access = true
  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true




  compute_config = {
    enabled = false
  }


  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}

    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        env = {
          # This enables the trick to allow more pods on tiny free-tier servers
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  eks_managed_node_groups = {
    karpenter = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.micro"]

      min_size     = 2
      max_size     = 10
      desired_size = 3

      taints = {
        # This Taint aims to keep just EKS Addons and Karpenter running on this MNG
        # The pods that do not tolerate this taint should run on nodes created by Karpenter
        addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
      }
    }
  }






  node_security_group_tags = {
    /*

  1. What does this tag do?
Earlier, we talked about how Karpenter uses the "karpenter.sh/discovery" tag on subnets to act as a neon sign, telling Karpenter: "It is safe to launch EC2 instances in this network."

This block does the exact same thing, but for Security Groups (Firewalls).

When Karpenter launches a new "naked" EC2 worker node, that node needs permission to talk to the EKS Control Plane (the API) and to other worker nodes. The Terraform EKS module automatically creates a perfectly configured "Node Shared Security Group" that has all these correct firewall rules.

By adding node_security_group_tags, you are telling Terraform: "Take that perfectly configured Security Group you just built, and slap a neon 'discovery' tag on it." Later, when Karpenter reads your EC2NodeClass file, it searches AWS for a security group with that tag, finds it, and attaches it to every new EC2 instance it builds.

2. Why is that warning comment there?
The comment is warning you about a very common and dangerous mistake engineers make.

"only tag the security group that Karpenter should utilize... at most, only one security group should have this tag in your account"

The Danger of Multiple Tags:
When Karpenter searches AWS for security groups using that discovery tag, it doesn't just pick one. It will attach EVERY security group it finds with that tag to your new EC2 instance.

The AWS Limit: By default, AWS only allows a maximum of 5 Security Groups to be attached to a single network interface (ENI). If you accidentally tag 6 security groups, Karpenter will try to attach all 6, AWS will throw an error, and Karpenter will completely fail to launch any nodes.

The Security Risk: Imagine you have a highly permissive security group open to the public internet for a specific database experiment, and you accidentally put the karpenter.sh/discovery tag on it. Karpenter will suddenly attach that open firewall to every single worker node it builds, creating a massive security vulnerability.

  */
    "karpenter.sh/discovery" = var.cluster_name
  }
}




###############################################################################
# Karpenter submodule
###############################################################################
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.23.0"

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = true

  # Attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

###############################################################################
# Install Karpenter via helm
###############################################################################
resource "helm_release" "karpenter" {
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.12.1"

  /*
    Why `wait = false` for Karpenter?

    By default, the Helm provider waits until all Kubernetes resources
    are fully deployed and healthy before Terraform continues.

    For Karpenter, this can sometimes cause installation deadlocks because
    the controller needs to register and initialize its admission webhooks
    before it can become fully ready. If Terraform waits for complete
    readiness, the Helm release may time out and fail.

    Setting `wait = false` allows Terraform to submit the Helm chart to
    Kubernetes and continue immediately, letting Karpenter finish its
    startup process asynchronously in the background.
*/
  wait = false

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]
}


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


module "iam_iam-role-for-service-accounts" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.6.1"

  # Updated to match the v6.x variable list
  name                                   = "${var.cluster_name}-aws-lbc"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

  depends_on = [module.eks]
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
    value = module.eks.cluster_name
    },
    {
      name  = "region"
      value = var.region
    },
    {
      name  = "serviceAccount.create"
      value = "false"
    },
    {
      name  = "vpcId"
      value = module.vpc.vpc_id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.iam_iam-role-for-service-accounts.arn
  }]



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
  values           = [file("${path.module}/../../k8s/helm_config/helm-nginx-cofiguration.yaml")]

  depends_on = [helm_release.aws_load_balancer_controller]

}


# resource "helm_release" "ingress-nginx" {
#   name             = "ingress-nginx"
#   repository       = "oci://ghcr.io/nginx/charts/nginx-ingress"
#   chart            = "ingress-nginx"
#   namespace        = "ingress-nginx"
#   create_namespace = true
#   version          = "2.6.0"
#   values           = [file("../../k8s/helm-nginx-cofiguration.yaml")]

#   depends_on = [helm_release.aws_load_balancer_controller]



# }


resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = file("${path.module}/../../k8s/karpenter/karpenter-node-pool.yaml")

  depends_on = [
    kubectl_manifest.karpenter_node_class
  ]
}


###############################################################################
# Apply Karpenter NodeClass YAML via kubectl provider
###############################################################################
resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = file("${path.module}/../../k8s/karpenter/karpenter-node-class.yaml")

  depends_on = [
    helm_release.karpenter
  ]
}

###############################################################################
# Inflate deployment
###############################################################################
resource "kubectl_manifest" "inflate_deployment" {
  yaml_body = file("${path.module}/../../k8s/inflate/inflate-deployment.yaml")


  depends_on = [
    kubectl_manifest.karpenter_node_pool
  ]
}


###############################################################################
# ecr repository for custom app images
###############################################################################

resource "aws_ecr_repository" "frontend" {
  name         = "${var.project_name}-frontend"
  force_delete = true
}

resource "aws_ecr_repository" "backend" {
  name         = "${var.project_name}-backend"
  force_delete = true
}

resource "aws_ecr_repository" "migration" {
  name         = "${var.project_name}-migration"
  force_delete = true
}



###############################################################################
# argo cd
###############################################################################

resource "kubernetes_namespace_v1" "app_namespace" {
  metadata {
    name = "app"
  }

  depends_on = [module.eks]
}


resource "kubernetes_namespace_v1" "argocd_namespace" {
  metadata {
    name = "argocd"
  }

  depends_on = [module.eks]
}

data "http" "argocd_manifest" {
  url = "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
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


  depends_on = [kubernetes_namespace_v1.argocd_namespace, kubectl_manifest.karpenter_node_class]
}

# Patch ArgoCD server service to LoadBalancer
resource "terraform_data" "patch_argocd_service" {
  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]

    command = <<-EOT
      # Update kubeconfig first
      aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}
      
      # Wait a bit for service to be created
      Start-Sleep -Seconds 20
      
      # Patch service to LoadBalancer (escaped double quotes for PowerShell to pass to kubectl safely)
      kubectl patch svc argocd-server -n argocd -p '{\"spec\": {\"type\": \"LoadBalancer\"}}'
    EOT
  }

  depends_on = [kubectl_manifest.argocd]
}



resource "kubectl_manifest" "argocd_project" {
  yaml_body = file("${path.module}/../../k8s/argocd/argocd-project.yaml")

  depends_on = [kubernetes_namespace_v1.app_namespace, kubectl_manifest.argocd]
}

resource "kubectl_manifest" "argocd_application" {
  yaml_body = file("${path.module}/../../k8s/argocd/argocd-app.yaml")

  depends_on = [kubernetes_namespace_v1.app_namespace, kubectl_manifest.argocd_project]
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


  depends_on = [module.eks]

}




###############################################################################
# 1. Create a Security Group specifically for the Backend Pod
###############################################################################
# resource "aws_security_group" "backend_pod_sg" {
#   name        = "${var.cluster_name}-backend-pod-sg"
#   description = "Security Group assigned directly to backend pods"
#   vpc_id      = module.vpc.vpc_id

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = "${var.cluster_name}-backend-pod-sg"
#   }
# }



###############################################################################
# 3. Tell Kubernetes to dynamically apply this SG whenever our backend spins up
###############################################################################
# resource "kubectl_manifest" "backend_network_policy" {
#   yaml_body = <<-YAML
#     apiVersion: vpcresources.k8s.aws/v1beta1
#     kind: SecurityGroupPolicy
#     metadata:
#       name: backend-db-access
#       namespace: default
#     spec:
#       podSelector:
#         matchLabels:
#           app: backend
#       securityGroups:
#         groupIds:
#           - ${aws_security_group.backend_pod_sg.id}
#   YAML
# }





