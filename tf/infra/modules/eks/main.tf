###############################################################################
# Pod Identity for AWS EBS CSI Driver
###############################################################################

module "aws_ebs_csi_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "${var.cluster_name}-aws-ebs-csi-iam"

  attach_aws_ebs_csi_policy = true
  aws_ebs_csi_kms_arns      = ["arn:aws:kms:*:*:key/1234abcd-12ab-34cd-56ef-1234567890ab"]

  tags = {
    Environment = "production"
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
          # This enables the trick to allow more pods on tiny free-tier servers
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

      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["c7i-flex.large"]

      min_size     = 1
      max_size     = 2
      desired_size = 1

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
    "karpenter.sh/discovery" = var.cluster_name
  }
}
