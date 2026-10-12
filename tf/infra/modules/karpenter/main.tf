# IAM roles, SQS interruption queue and Pod Identity for Karpenter
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.23.0"

  cluster_name = var.cluster_name

  create_pod_identity_association = true

  # extra policy for the nodes Karpenter starts (not for the Karpenter controller),
  # so we can open a shell on them with SSM
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  }
}

resource "helm_release" "karpenter" {
  namespace  = "kube-system"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.12.1"

  # Don't wait for Karpenter to be ready. Waiting can time out while its webhooks
  # start up; it finishes starting in the background.
  wait = false

  # The chart already adds the CriticalAddonsOnly toleration.
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

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = templatefile("${path.root}/../../k8s/karpenter/karpenter-node-class.yaml", {
    cluster_name = var.cluster_name
    role_name    = module.karpenter.node_iam_role_name
  })
  depends_on = [
    helm_release.karpenter
  ]
}

# test deployment for Karpenter scaling (scale it up to see new nodes)
resource "kubectl_manifest" "inflate_deployment" {
  yaml_body = file("${path.root}/../../k8s/inflate/inflate-deployment.yaml")

  depends_on = [
    kubectl_manifest.karpenter_node_pool
  ]
}
