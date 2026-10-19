###############################################################################
# Terraform settings
###############################################################################
# Provider versions, and where the state is kept.
terraform {
  # State is kept in S3 (bucket created by tf/statebucket). use_lockfile stops two
  # applies from running at the same time.
  backend "s3" {
    bucket  = "todo-cluster-terraform-state-677501681528"
    region  = "us-east-1"
    key     = "todo-cluster.tfstate"
    profile = "terraform-user"

    use_lockfile = true
  }

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

###############################################################################
# AWS provider
###############################################################################
# Uses the terraform-user profile from ~/.aws/credentials.
provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

###############################################################################
# Current AWS account
###############################################################################
# Gives the account ID (see the account_id output).
data "aws_caller_identity" "current" {}

###############################################################################
# Kubernetes provider
###############################################################################
# The kubernetes, helm and kubectl providers log in to the cluster with a short-lived
# token from `aws eks get-token` (needs the AWS CLI on this machine). The CA certificate
# makes sure we are talking to our own cluster.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", var.aws_profile]
  }
}

###############################################################################
# Helm provider
###############################################################################
# Logs in to the cluster the same way as the kubernetes provider.
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", var.aws_profile]
    }
  }
}

###############################################################################
# kubectl provider
###############################################################################
# kubectl provider: applies plain YAML files (NodePool, HTTPRoutes, ...)
provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", var.aws_profile]
  }
}

###############################################################################
# VPC
###############################################################################
# Public, private and intra subnets in two zones, and one NAT gateway.
module "vpc" {
  source = "./modules/vpc"

  cluster_name = var.cluster_name
  region       = var.region
}

###############################################################################
# EKS cluster
###############################################################################
# The cluster, the add-on node group and the EKS managed add-ons.
module "eks" {
  source = "./modules/eks"

  cluster_name    = var.cluster_name
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  intra_subnets   = module.vpc.intra_subnets
}

###############################################################################
# Karpenter
###############################################################################
# Starts and removes worker nodes for the pods.
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name     = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
}

# Cluster add-ons, one module each. EKS-managed add-ons (CoreDNS, EBS CSI, ...) are in the eks module.

###############################################################################
# AWS Load Balancer Controller
###############################################################################
# AWS Load Balancer Controller: turns LoadBalancer Services into NLBs
module "aws_addons" {
  source = "./modules/aws-addons"

  cluster_name = module.eks.cluster_name
  region       = var.region
  vpc_id       = module.vpc.vpc_id

  depends_on = [module.eks]
}

###############################################################################
# metrics-server
###############################################################################
# CPU and memory numbers for kubectl top and the HPAs.
module "metrics_server" {
  source = "./modules/metrics-server"

  depends_on = [module.eks]
}

###############################################################################
# Sealed Secrets
###############################################################################
# Turns SealedSecret objects into normal Secrets (nothing uses it right now).
module "sealed_secrets" {
  source = "./modules/sealed-secrets"

  depends_on = [module.eks]
}

###############################################################################
# Gateway API CRDs
###############################################################################
# Gateway API CRDs (Gateway, HTTPRoute, ...). Not built into Kubernetes.
module "gateway_api_crds" {
  source = "./modules/gateway-api-crds"

  depends_on = [module.eks]
}

###############################################################################
# cert-manager
###############################################################################
# cert-manager writes temporary HTTPRoutes for the Let's Encrypt check,
# so the Gateway API CRDs must exist before it starts
module "cert_manager" {
  source = "./modules/cert-manager"

  letsencrypt_email = var.letsencrypt_email

  depends_on = [module.gateway_api_crds]
}

###############################################################################
# Istio
###############################################################################
# Istio + main-gateway (the front door). The gateway needs cert-manager for its
# certificates and the AWS Load Balancer Controller for its NLB.
module "istio" {
  source = "./modules/istio"

  depends_on = [module.gateway_api_crds, module.cert_manager, module.aws_addons]
}

###############################################################################
# ECR repositories
###############################################################################
# Where Jenkins pushes the frontend, backend and migration images.
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
}

###############################################################################
# App namespace
###############################################################################
# The todo app runs here. Argo CD deploys into it.
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = "app"
    # join the Istio mesh (ambient mode): pod-to-pod traffic gets mTLS
    labels = {
      "istio.io/dataplane-mode" = "ambient"
    }
  }

  depends_on = [module.eks]
}

###############################################################################
# RDS database
###############################################################################
# PostgreSQL for the backend, with IAM login instead of a password.
module "rds" {
  source = "./modules/rds"

  cluster_name           = module.eks.cluster_name
  region                 = var.region
  vpc_id                 = module.vpc.vpc_id
  private_subnets        = module.vpc.private_subnets
  node_security_group_id = module.eks.node_security_group_id
  app_namespace          = kubernetes_namespace_v1.app.metadata[0].name
}

###############################################################################
# Argo CD
###############################################################################
# Installs Argo CD and the bootstrap app.
# Modules with an HTTPRoute wait for main-gateway (in the istio module).
module "argocd" {
  source = "./modules/argocd"

  # log in with GitHub
  github_org           = var.github_org
  github_client_id     = var.argocd_github_client_id
  github_client_secret = var.argocd_github_client_secret

  # The bootstrap app creates the monitoring, logging and tracing cards, so first Terraform
  # creates what those cards need: their namespaces and operators (observability_base)
  # and ESO with the passwords in AWS Secrets Manager (secrets).
  depends_on = [module.istio, module.observability_base, module.secrets]
}

###############################################################################
# Observability base
###############################################################################
# Namespaces for monitoring, logging and tracing, and the ECK and trust-manager operators.
# The stacks themselves are installed by Argo CD.
module "observability_base" {
  source = "./modules/observability-base"

  # trust-manager needs cert-manager, the operators need Karpenter nodes to run on, and
  # two of the namespaces join the mesh (istio)
  depends_on = [module.cert_manager, module.karpenter, module.istio]
}

###############################################################################
# Secrets
###############################################################################
# Passwords in AWS Secrets Manager, and ESO (External Secrets Operator), which copies them
# into Kubernetes Secrets for the stacks (ExternalSecrets in the GitOps repo)
module "secrets" {
  source = "./modules/secrets"

  cluster_name = module.eks.cluster_name
  region       = var.region

  github_org                   = var.github_org
  grafana_github_client_id     = var.grafana_github_client_id
  grafana_github_client_secret = var.grafana_github_client_secret

  # Alertmanager sends alert emails with this Gmail app password
  alert_email_password = var.alert_email_password

  # ESO runs on Karpenter nodes
  depends_on = [module.eks, module.karpenter]
}
