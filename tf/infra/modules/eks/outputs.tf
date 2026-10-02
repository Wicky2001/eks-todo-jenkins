output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "eks_managed_node_groups" {
  value = module.eks.eks_managed_node_groups
}

output "node_security_group_id" {
  value = module.eks.node_security_group_id
}
