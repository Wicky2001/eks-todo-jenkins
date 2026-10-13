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

# kubectl provider: applies plain YAML files (NodePool, Ingresses, ...)
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

module "addons" {
  source = "./modules/addons"

  cluster_name = module.eks.cluster_name
  region       = var.region
  vpc_id       = module.vpc.vpc_id

  letsencrypt_email = var.letsencrypt_email

  depends_on = [module.eks]
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
}

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = "app"
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

# Modules with an Ingress wait for addons: the ingress-nginx webhook and cert-manager
# have to be running before an Ingress can be created.
module "argocd" {
  source = "./modules/argocd"

  # log in with GitHub
  github_org           = var.github_org
  github_client_id     = var.argocd_github_client_id
  github_client_secret = var.argocd_github_client_secret

  depends_on = [module.addons]
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
  depends_on = [module.addons, module.logging]
}

module "logging" {
  source = "./modules/logging"

  # Elasticsearch needs the EBS CSI driver (eks addons) and Karpenter nodes to run on
  depends_on = [module.addons, module.karpenter]
}

module "tracing" {
  source = "./modules/tracing"

  # uses the ECK operator and the elasticsearch-sc storage class from logging
  depends_on = [module.logging]
}
