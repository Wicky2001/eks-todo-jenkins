###############################################################################
# Install prometheus stack via helm
###############################################################################

# Apply storage classes for prometheus tsdb and alertmanager
# 1. Read the multi-document YAML file and split it into individual manifests
data "kubectl_file_documents" "storage_class_docs" {
  content = file("${path.root}/../../k8s/observability/monitoring/storage-classes.yaml")
}

# 2. Loop through every split manifest block and apply them cleanly
resource "kubectl_manifest" "prometheus_storage_classes" {
  for_each  = data.kubectl_file_documents.storage_class_docs.manifests
  yaml_body = each.value
}


resource "helm_release" "prometheus" {
  name       = "prometheus"
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
