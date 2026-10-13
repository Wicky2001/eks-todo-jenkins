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

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}

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

module "vpc" {
  source = "./modules/vpc"

  cluster_name = var.cluster_name
  region       = var.region
}

module "eks" {
  source = "./modules/eks"

  cluster_name    = var.cluster_name
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  intra_subnets   = module.vpc.intra_subnets
}

module "karpenter" {
  source = "./modules/karpenter"

  cluster_name     = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
}

# Cluster add-ons, one module each. EKS-managed add-ons (CoreDNS, EBS CSI, ...) are in the eks module.

# AWS Load Balancer Controller: turns LoadBalancer Services into NLBs
module "aws_addons" {
  source = "./modules/aws-addons"

  cluster_name = module.eks.cluster_name
  region       = var.region
  vpc_id       = module.vpc.vpc_id

  depends_on = [module.eks]
}

module "metrics_server" {
  source = "./modules/metrics-server"

  depends_on = [module.eks]
}

module "sealed_secrets" {
  source = "./modules/sealed-secrets"

  depends_on = [module.eks]
}

# Gateway API CRDs (Gateway, HTTPRoute, ...). Not built into Kubernetes.
module "gateway_api_crds" {
  source = "./modules/gateway-api-crds"

  depends_on = [module.eks]
}

# cert-manager writes temporary HTTPRoutes for the Let's Encrypt check,
# so the Gateway API CRDs must exist before it starts
module "cert_manager" {
  source = "./modules/cert-manager"

  letsencrypt_email = var.letsencrypt_email

  depends_on = [module.gateway_api_crds]
}

# Istio + main-gateway (the front door). The gateway needs cert-manager for its
# certificates and the AWS Load Balancer Controller for its NLB.
module "istio" {
  source = "./modules/istio"

  depends_on = [module.gateway_api_crds, module.cert_manager, module.aws_addons]
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
}

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

module "rds" {
  source = "./modules/rds"

  cluster_name           = module.eks.cluster_name
  region                 = var.region
  vpc_id                 = module.vpc.vpc_id
  private_subnets        = module.vpc.private_subnets
  node_security_group_id = module.eks.node_security_group_id
  app_namespace          = kubernetes_namespace_v1.app.metadata[0].name
}

# Modules with an HTTPRoute wait for main-gateway (in the istio module).
module "argocd" {
  source = "./modules/argocd"

  # log in with GitHub
  github_org           = var.github_org
  github_client_id     = var.argocd_github_client_id
  github_client_secret = var.argocd_github_client_secret

  depends_on = [module.istio]
}

module "monitoring" {
  source = "./modules/monitoring"

  # Grafana reads logs as grafana-user, created in the logging module
  grafana_es_password = module.logging.grafana_es_password

  # log in with GitHub
  github_org           = var.github_org
  github_client_id     = var.grafana_github_client_id
  github_client_secret = var.grafana_github_client_secret

  # also waits for logging, so the Elasticsearch CA copy exists before Grafana starts
  depends_on = [module.istio, module.logging]
}

module "logging" {
  source = "./modules/logging"

  # trust-manager needs cert-manager. Elasticsearch needs the EBS CSI driver
  # (eks module) and Karpenter nodes to run on.
  depends_on = [module.cert_manager, module.karpenter]
}

module "tracing" {
  source = "./modules/tracing"

  # uses the ECK operator and the elasticsearch-sc storage class from logging.
  # Waits for istio too, because its namespace joins the mesh.
  depends_on = [module.logging, module.istio]
}
