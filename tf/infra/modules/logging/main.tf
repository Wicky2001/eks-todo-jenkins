# Logs: Fluent Bit -> Elasticsearch "logs" -> Grafana

# ECK operator. It runs both Elasticsearch clusters (logs here, traces in the tracing module).
resource "helm_release" "eck_operator" {
  name             = "eck-operator"
  repository       = "https://helm.elastic.co"
  chart            = "eck-operator"
  namespace        = "elastic-system"
  create_namespace = true
  version          = "3.5.0"

  values = [
    yamlencode({
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]
}

resource "kubernetes_namespace_v1" "logging" {
  metadata {
    name = "logging"
  }
}

# fluentbit-user: can only create and write the logs-* indices
resource "random_password" "fluentbit_user" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "fluentbit_role" {
  metadata {
    name      = "fluentbit-role"
    namespace = kubernetes_namespace_v1.logging.metadata[0].name
  }
  data = {
    "roles.yml" = yamlencode({
      fluentbit_writer = {
        indices = [
          {
            names      = ["logs-*"]
            privileges = ["create_index", "write"]
          }
        ]
      }
    })
  }
}

# ECK creates the user from this Secret; Fluent Bit reads its password from the same Secret.
resource "kubernetes_secret_v1" "fluentbit_user" {
  metadata {
    name      = "fluentbit-user"
    namespace = kubernetes_namespace_v1.logging.metadata[0].name
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "fluentbit-user"
    password = random_password.fluentbit_user.result
    roles    = "fluentbit_writer"
  }

  depends_on = [kubernetes_secret_v1.fluentbit_role]
}

# grafana-user: can only read the logs-* indices
resource "random_password" "grafana_user" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "grafana_role" {
  metadata {
    name      = "grafana-role"
    namespace = kubernetes_namespace_v1.logging.metadata[0].name
  }
  data = {
    "roles.yml" = yamlencode({
      grafana_reader = {
        cluster = ["monitor"]
        indices = [
          {
            names      = ["logs-*"]
            privileges = ["read", "view_index_metadata"]
          }
        ]
      }
    })
  }
}

# Grafana runs in another namespace and can't read this Secret, so the password is
# passed to the monitoring module through the grafana_es_password output.
resource "kubernetes_secret_v1" "grafana_user" {
  metadata {
    name      = "grafana-user"
    namespace = kubernetes_namespace_v1.logging.metadata[0].name
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "grafana-user"
    password = random_password.grafana_user.result
    roles    = "grafana_reader"
  }

  depends_on = [kubernetes_secret_v1.grafana_role]
}

resource "kubectl_manifest" "elasticsearch_storage_class" {
  yaml_body = file("${path.root}/../../k8s/observability/logging/storage-class.yaml")
}

resource "kubectl_manifest" "elasticsearch" {
  yaml_body = file("${path.root}/../../k8s/observability/logging/elasticsearch.yaml")

  # on destroy, wait until ECK has deleted the pod and its disk
  wait = true

  depends_on = [
    helm_release.eck_operator,
    kubernetes_namespace_v1.logging,
    kubectl_manifest.elasticsearch_storage_class,
    kubernetes_secret_v1.fluentbit_user,
    kubernetes_secret_v1.fluentbit_role,
    kubernetes_secret_v1.grafana_user,
    kubernetes_secret_v1.grafana_role,
  ]
}

# trust-manager copies the public CA of the logs Elasticsearch to the monitoring
# namespace, so Grafana can verify its certificate. It reads CAs from the "logging"
# namespace, which has to exist before it is installed.
resource "helm_release" "trust_manager" {
  name       = "trust-manager"
  repository = "https://charts.jetstack.io"
  chart      = "trust-manager"
  namespace  = "cert-manager"
  version    = "v0.25.0"

  values = [
    yamlencode({
      app = {
        trust = {
          namespace = kubernetes_namespace_v1.logging.metadata[0].name
        }
      }
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]
}

resource "kubectl_manifest" "logs_es_ca_bundle" {
  yaml_body = file("${path.root}/../../k8s/observability/logging/logs-es-ca-bundle.yaml")

  depends_on = [helm_release.trust_manager, kubectl_manifest.elasticsearch]
}

# Fluent Bit runs on every node (DaemonSet) and ships container logs to Elasticsearch.
resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  namespace  = kubernetes_namespace_v1.logging.metadata[0].name
  version    = "0.58.3"

  values = [file("${path.root}/../../k8s/observability/logging/fluent-bit-values.yaml")]

  depends_on = [kubectl_manifest.elasticsearch]
}
