# IAM role for the EBS CSI driver (Pod Identity), used by the aws-ebs-csi-driver add-on below
module "aws_ebs_csi_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "${var.cluster_name}-aws-ebs-csi-iam"

  attach_aws_ebs_csi_policy = true

  tags = {
    Environment = "production"
  }
}

# EKS cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.23.0"

  name               = var.cluster_name
  kubernetes_version = "1.33"

  endpoint_public_access = true
  # make whoever runs terraform a cluster admin
  enable_cluster_creator_admin_permissions = true

  enable_irsa = false

  compute_config = {
    enabled = false
  }

  addons = {
    coredns = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      before_compute = true
      most_recent    = true
    }
    kube-proxy = {
      most_recent = true
    }

    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        env = {
          # hand out pod IPs in blocks of 16, so small nodes can run more pods
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
      most_recent = true
    }

    aws-ebs-csi-driver = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = module.aws_ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }

  }

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnets
  control_plane_subnet_ids = var.intra_subnets

  eks_managed_node_groups = {
    karpenter = {

      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["c7i-flex.large"]

      min_size     = 1
      max_size     = 4
      desired_size = 2

      taints = {
        # only add-ons and Karpenter run on this node group; everything else
        # goes to nodes that Karpenter starts
        addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}
