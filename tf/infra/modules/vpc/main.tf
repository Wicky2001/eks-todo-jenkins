###############################################################################
# VPC
###############################################################################
# Subnets, the NAT gateway, and the tags the LB controller and Karpenter look for.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  # Only the first two zones get subnets (two of each kind below).
  azs = ["${var.region}a", "${var.region}b", "${var.region}c"]

  # Worker nodes, pods and RDS. Not reachable from the internet; they go out through the NAT gateway.
  private_subnets = ["10.0.0.0/20", "10.0.16.0/20"]

  # Internet-facing load balancers and the NAT gateway.
  public_subnets = ["10.0.32.0/20", "10.0.48.0/20"]

  # No internet access at all. EKS puts the control plane's network interfaces here.
  intra_subnets = ["10.0.64.0/20", "10.0.80.0/20"]

  # One NAT gateway instead of one per zone, to save money.
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # The AWS Load Balancer Controller puts internet-facing load balancers in subnets
  # with this tag. The value has to be 1.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    # for internal (private) load balancers
    "kubernetes.io/role/internal-elb" = 1
    # Karpenter starts new nodes in subnets with this tag, so nodes stay private
    "karpenter.sh/discovery" = var.cluster_name
  }
}
