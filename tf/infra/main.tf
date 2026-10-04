###############################################################################
# Provider
###############################################################################
terraform {
  backend "s3" {
    bucket  = "todo-cluster-terraform-state-677501681528"
    region  = "us-east-1"
    key     = "todo-cluster.tfstate"
    profile = "terraform-user"

    use_lockfile = true
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
  region  = var.region
  profile = var.aws_profile
}

###############################################################################
# Data Sources
###############################################################################
data "aws_caller_identity" "current" {}



provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", var.aws_profile]
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
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", var.aws_profile]
    }
  }
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
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--profile", var.aws_profile]
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

module "argocd" {
  source = "./modules/argocd"


}

module "monitoring" {
  source = "./modules/monitoring"

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
