###############################################################################
# VPC Outputs
###############################################################################

output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs used by EKS worker nodes"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs used for Load Balancers"
  value       = module.vpc.public_subnets
}

output "intra_subnets" {
  description = "Intra subnet IDs used by EKS control plane"
  value       = module.vpc.intra_subnets
}


###############################################################################
# EKS Outputs
###############################################################################

output "cluster_name" {
  description = "EKS Cluster Name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint URL for Kubernetes API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS Kubernetes version"
  value       = module.eks.cluster_version
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN used for IAM Roles for Service Accounts"
  value       = module.eks.oidc_provider_arn
}

output "cluster_certificate_authority_data" {
  description = "Cluster CA certificate"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}


###############################################################################
# Kubectl Connection Command
###############################################################################

output "configure_kubectl" {
  description = "Command to configure kubectl locally"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}


###############################################################################
# Managed Node Group Outputs
###############################################################################

output "eks_managed_node_groups" {
  description = "EKS Managed Node Group details"
  value       = module.eks.eks_managed_node_groups
}


###############################################################################
# Karpenter Outputs
###############################################################################

output "karpenter_node_role_name" {
  description = "IAM role used by Karpenter created nodes"
  value       = module.karpenter.node_iam_role_name
}


output "karpenter_node_role_arn" {
  description = "IAM role ARN used by Karpenter nodes"
  value       = module.karpenter.node_iam_role_arn
}


output "karpenter_service_account" {
  description = "Karpenter service account name"
  value       = module.karpenter.service_account
}


output "karpenter_interruption_queue" {
  description = "Karpenter interruption SQS queue name"
  value       = module.karpenter.queue_name
}


###############################################################################
# ECR Repository Outputs
###############################################################################

output "frontend_ecr_repository_url" {
  description = "Frontend Docker image repository URL"
  value       = aws_ecr_repository.frontend.repository_url
}


output "backend_ecr_repository_url" {
  description = "Backend Docker image repository URL"
  value       = aws_ecr_repository.backend.repository_url
}


output "migration_ecr_repository_url" {
  description = "Migration Docker image repository URL"
  value       = aws_ecr_repository.migration.repository_url
}





###############################################################################
# Kubernetes Namespaces
###############################################################################

output "application_namespace" {
  description = "Application namespace"
  value       = kubernetes_namespace_v1.app_namespace.metadata[0].name
}


output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = kubernetes_namespace_v1.argocd_namespace.metadata[0].name
}


###############################################################################
# ArgoCD Information
###############################################################################

output "argocd_initial_password_command" {
  description = "Command to get ArgoCD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

