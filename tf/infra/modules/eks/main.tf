###############################################################################
# Pod Identity for AWS EBS CSI Driver
###############################################################################

module "aws_ebs_csi_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  # 1. This IS the name of the IAM role the module will automatically CREATE for you.
  # It will show up in your AWS IAM Console as "aws-ebs-csi".
  name = "${var.cluster_name}-aws-ebs-csi"

  # 2. When set to true, the module automatically grabs the official AWS-managed policy
  # "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  # and attaches it to the role it just created. (Saves you from writing it yourself).
  attach_aws_ebs_csi_policy = true

  # 3. OPTIONAL: If you encrypt your EBS volumes using a custom AWS KMS Key,
  # the IAM role needs permission to use that key to decrypt/encrypt disks.
  # You put your KMS Key ARN here. (If using default AWS-managed EBS encryption, you can delete this line).
  aws_ebs_csi_kms_arns = ["arn:aws:kms:*:*:key/1234abcd-12ab-34cd-56ef-1234567890ab"]

  # 4. The map that tells the AWS EKS API to match the newly created "aws-ebs-csi" IAM role
  # to the "ebs-csi-controller-sa" pod identifier inside your specific cluster.
  associations = {
    this = {
      cluster_name    = var.cluster_name # Change "example" to match your cluster variable
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }

  tags = {
    Environment = "production"
  }
}

###############################################################################
# Pod Identity for AWS Load Balancer Controller
###############################################################################

module "aws_lb_controller_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "aws-lbc"

  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller-sa"
    }
  }

  tags = {
    Environment = "dev"
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
      depends_on  = [module.aws_ebs_csi_pod_identity]
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
