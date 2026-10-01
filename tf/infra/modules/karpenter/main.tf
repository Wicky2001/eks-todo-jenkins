###############################################################################
# Karpenter submodule
###############################################################################
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.23.0"

  cluster_name = var.cluster_name

  create_pod_identity_association = true

  # Attach additional IAM policies to the Karpenter node IAM role
  # When you add the policy to node_iam_role_additional_policies in Terraform, you are configuring the Worker Node's identity, not the Karpenter controller's identity.
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  }
}

###############################################################################
# Install Karpenter via helm
###############################################################################
resource "helm_release" "karpenter" {
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.12.1"

  /*
    Why `wait = false` for Karpenter?

    By default, the Helm provider waits until all Kubernetes resources
    are fully deployed and healthy before Terraform continues.

    For Karpenter, this can sometimes cause installation deadlocks because
    the controller needs to register and initialize its admission webhooks
    before it can become fully ready. If Terraform waits for complete
    readiness, the Helm release may time out and fail.

    Setting `wait = false` allows Terraform to submit the Helm chart to
    Kubernetes and continue immediately, letting Karpenter finish its
    startup process asynchronously in the background.
*/
  wait = false

  # By default official, Karpeneter Helm chart automatically add CriticalAddonsOnly toleration to the Karpenter pods.

  values = [
    <<-EOT
    replicas: 1
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${var.cluster_name}
      clusterEndpoint: ${var.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]

  depends_on = [module.karpenter]
}


resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = file("${path.root}/../../k8s/karpenter/karpenter-node-pool.yaml")

  depends_on = [
    kubectl_manifest.karpenter_node_class
  ]
}


###############################################################################
# Apply Karpenter NodeClass YAML via kubectl provider
###############################################################################
resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = templatefile("${path.root}/../../k8s/karpenter/karpenter-node-class.yaml", {
    cluster_name = var.cluster_name
    role_name    = module.karpenter.node_iam_role_name
  })
  depends_on = [
    helm_release.karpenter
  ]
}

###############################################################################
# Inflate deployment
###############################################################################
resource "kubectl_manifest" "inflate_deployment" {
  yaml_body = file("${path.root}/../../k8s/inflate/inflate-deployment.yaml")


  depends_on = [
    kubectl_manifest.karpenter_node_pool
  ]
}
