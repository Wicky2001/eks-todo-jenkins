# Metrics: Prometheus, Alertmanager and Grafana (kube-prometheus-stack)

# storage classes for the Prometheus, Alertmanager and Grafana disks (one per --- document)
resource "kubectl_manifest" "prometheus_storage_classes" {
  for_each  = { for i, doc in split("---", file("${path.root}/../../k8s/observability/monitoring/storage-classes.yaml")) : i => doc if trimspace(doc) != "" }
  yaml_body = each.value
}

# created here instead of by Helm, so the Secrets below exist before Grafana starts
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# Grafana admin password (instead of the chart's default, which everyone knows)
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

# grafana-user's password, copied from the logging module (pods can only read
# Secrets in their own namespace)
resource "kubernetes_secret_v1" "grafana_es_credentials" {
  metadata {
    name      = "grafana-es-credentials"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    password = var.grafana_es_password
  }
}

# GitHub OAuth App secret for "Log in with GitHub"
resource "kubernetes_secret_v1" "grafana_github_oauth" {
  metadata {
    name      = "grafana-github-oauth"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    client-secret = var.github_client_secret
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
    templatefile("${path.root}/../../k8s/observability/monitoring/grafana-github-sso.yaml", {
      github_org = var.github_org
      client_id  = var.github_client_id
    }),
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
    kubernetes_secret_v1.grafana_github_oauth,
  ]
}

# https://grafana.jawsight.online (an HTTPRoute on main-gateway)
resource "kubectl_manifest" "grafana_route" {
  yaml_body = file("${path.root}/../../k8s/observability/monitoring/grafana-route.yaml")

  depends_on = [helm_release.monitoring]
}
