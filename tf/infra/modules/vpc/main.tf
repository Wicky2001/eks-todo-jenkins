###############################################################################
# VPC
###############################################################################
module "vpc" {
  # The source code location for the official AWS VPC module
  source = "terraform-aws-modules/vpc/aws"
  # The specific version of the module to ensure consistent deployments
  version = "6.6.1"

  # Name used to identify this VPC in the AWS console
  name = "${var.cluster_name}-vpc"
  # The main IP address range (pool) for the entire VPC
  cidr = "10.0.0.0/16"

  # The three physical AWS data centers (Availability Zones) to distribute your resources across
  azs = ["${var.region}a", "${var.region}b", "${var.region}c"]

  # Private subnets: The "inside of the house." Instances here cannot be reached from the internet,
  # but they can "look out the window" to download updates via a NAT Gateway.
  private_subnets = ["10.0.0.0/20", "10.0.16.0/20"]

  # Public subnets: The "front yard." Instances here have direct access to the public internet,
  # typically used for public-facing entry points.
  public_subnets = ["10.0.32.0/20", "10.0.48.0/20"]

  # Intra subnets: The "sealed safe room." These have zero access to the outside internet,
  # not even for updates. EKS needs these to securely house the network cables (ENIs)
  # that connect the Kubernetes 'brain' (Control Plane) to your worker nodes,
  # ensuring that no external traffic can ever reach the control plane infrastructure.
  intra_subnets = ["10.0.64.0/20", "10.0.80.0/20"]

  # Enable the NAT Gateway so private instances can reach out to the internet for updates
  enable_nat_gateway = true
  # Use only one NAT Gateway to save costs (instead of one per AZ)
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # Tag for public subnets so the AWS Load Balancer Controller knows where to place public load balancers.
  # This tag acts as a neon sign: 'Hey! This is a public subnet! You are allowed to build internet-facing
  # load balancers right here.' The value '1' is a hardcoded AWS standard (meaning True). Using 'true',
  # 'yes', or any other value will cause the AWS controller to ignore these subnets, and your load balancers will fail to create.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  # Tags for private subnets to handle internal traffic and auto-discovery
  private_subnet_tags = {
    # This acts as a 'neon sign' for internal components. It tells AWS: 'If Kubernetes asks for an
    # internal-only, private load balancer (e.g., for frontend-to-database traffic), put it here.'
    # Like the public tag, the value '1' is a strict requirement for the AWS Load Balancer Controller.
    "kubernetes.io/role/internal-elb" = 1

    # This is the 'discovery' tag for Karpenter. Karpenter is the engine that builds your EC2 worker nodes.
    # When it needs to launch a new node, it asks AWS: 'Give me subnets with this tag.' Because we only
    # place this tag on private subnets, Karpenter will automatically and securely launch your
    # EC2 instances in the private 'safe room', keeping them completely hidden from the public internet.
    "karpenter.sh/discovery" = var.cluster_name
  }
}

