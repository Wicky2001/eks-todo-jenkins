###############################################################################
# Install prometheus stack via helm
###############################################################################


# 1. Read the multi-document YAML file and split it into individual manifests
resource "kubectl_manifest" "prometheus_storage_classes" {
  for_each  = { for i, doc in split("---", file("${path.root}/../../k8s/observability/monitoring/storage-classes.yaml")) : i => doc if trimspace(doc) != "" }
  yaml_body = each.value
}

# Created here (not by Helm), so the Grafana admin Secret can exist before Grafana starts.
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

###############################################################################
# Grafana admin login (instead of the chart's well-known default password)
###############################################################################
resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }
}

# Grafana's password for Elasticsearch (logs). A pod can only read Secrets in its own
# namespace, so the password made by the logging module is copied here.
resource "kubernetes_secret_v1" "grafana_es_credentials" {
  metadata {
    name      = "grafana-es-credentials"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    password = var.grafana_es_password
  }
}

resource "helm_release" "monitoring" {
  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  version    = "87.5.0"

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

  depends_on = [
    kubectl_manifest.prometheus_storage_classes,
    kubernetes_secret_v1.grafana_admin,
    kubernetes_secret_v1.grafana_es_credentials,
  ]
}
