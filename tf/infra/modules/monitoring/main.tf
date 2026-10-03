###############################################################################
# Install prometheus stack via helm
###############################################################################


# 1. Read the multi-document YAML file and split it into individual manifests
resource "kubectl_manifest" "prometheus_storage_classes" {
  for_each  = { for i, doc in split("---", file("${path.root}/../../k8s/observability/monitoring/storage-classes.yaml")) : i => doc if trimspace(doc) != "" }
  yaml_body = each.value
}


resource "helm_release" "monitoring" {
  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  version    = "87.5.0"

  create_namespace = true

  values = [
    file("${path.root}/../../k8s/observability/monitoring/helm-values.yaml"),
    yamlencode({
      prometheus-node-exporter = {
        tolerations = [
          {
            key    = "CriticalAddonsOnly"
            value  = "true"
            effect = "NoSchedule"
          }
        ]
      }
    })
  ]

  depends_on = [kubectl_manifest.prometheus_storage_classes]
}
