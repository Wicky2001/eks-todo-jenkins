###############################################################################
# Log collection: Fluent Bit → Elasticsearch → Grafana (one UI for metrics, logs and traces)
###############################################################################

# ECK (Elastic Cloud on Kubernetes) is the operator that installs and runs
# Elasticsearch from a small YAML file (the traces Elasticsearch in the tracing module too).
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

###############################################################################
# Elasticsearch user for Fluent Bit (instead of the "elastic" superuser)
###############################################################################
resource "random_password" "fluentbit_user" {
  length  = 32
  special = false
}


# The role: may only create the logs-* indices and write log lines into them.
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


# ECK reads this as a user: name, password and role. Fluent Bit reads the password from it too.
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

###############################################################################
# Elasticsearch user for Grafana (read-only, so Grafana can show the logs)
###############################################################################
resource "random_password" "grafana_user" {
  length  = 32
  special = false
}

# The role: may only read the logs-* indices.
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

# ECK reads this as a user. Grafana runs in another namespace, so the password is
# handed to the monitoring module through the output "grafana_es_password".
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

###############################################################################
# Elasticsearch (ECK creates the pod, Services, Secrets and certificates)
###############################################################################
resource "kubectl_manifest" "elasticsearch" {
  yaml_body = file("${path.root}/../../k8s/observability/logging/elasticsearch.yaml")

  # On destroy, wait until ECK has removed the pod and its disk before the operator is uninstalled.
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

###############################################################################
# trust-manager: shares the logs Elasticsearch's CA (public, not secret) with Grafana
###############################################################################

# A small companion to cert-manager. It copies trusted CA certificates into other
# namespaces. It reads its sources from one "trust namespace", here "logging", where
# ECK keeps the CA. That namespace must exist before trust-manager is installed.
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

# Copies ca.crt of the logs Elasticsearch into a ConfigMap "logs-es-ca" in namespace monitoring.
resource "kubectl_manifest" "logs_es_ca_bundle" {
  yaml_body = file("${path.root}/../../k8s/observability/logging/logs-es-ca-bundle.yaml")

  depends_on = [helm_release.trust_manager, kubectl_manifest.elasticsearch]
}

###############################################################################
# Fluent Bit: Deamon set
###############################################################################
resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  namespace  = kubernetes_namespace_v1.logging.metadata[0].name
  version    = "0.58.3"

  values = [file("${path.root}/../../k8s/observability/logging/fluent-bit-values.yaml")]

  depends_on = [kubectl_manifest.elasticsearch]
}
