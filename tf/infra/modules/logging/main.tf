###############################################################################
# Log collection: Fluent Bit → Elasticsearch → Kibana
###############################################################################

# ECK (Elastic Cloud on Kubernetes) is the operator that installs and runs
# Elasticsearch and Kibana from the two small YAML files below.
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

resource "kubectl_manifest" "elasticsearch_storage_class" {
  yaml_body = file("${path.root}/../../k8s/observability/logging/storage-class.yaml")
}

###############################################################################
# Elasticsearch and Kibana (ECK creates the pods, Services, Secrets and certificates)
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
  ]
}

resource "kubectl_manifest" "kibana" {
  yaml_body = file("${path.root}/../../k8s/observability/logging/kibana.yaml")

  wait = true

  depends_on = [kubectl_manifest.elasticsearch]
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
