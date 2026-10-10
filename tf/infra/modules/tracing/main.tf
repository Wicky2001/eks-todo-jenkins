###############################################################################
# Tracing: frontend and backend (OpenTelemetry) → Jaeger → its own Elasticsearch
###############################################################################

# The backend sends spans to jaeger.tracing.svc.cluster.local:4318, so the namespace is "tracing".
resource "kubernetes_namespace_v1" "tracing" {
  metadata {
    name = "tracing"
  }
}

###############################################################################
# Elasticsearch user for Jaeger (instead of the "elastic" superuser)
###############################################################################
resource "random_password" "jaeger_user" {
  length  = 32
  special = false
}



# The role: may only use the jaeger-* indices, and create the index templates for them.
resource "kubernetes_secret_v1" "jaeger_role" {
  metadata {
    name      = "jaeger-role"
    namespace = kubernetes_namespace_v1.tracing.metadata[0].name
  }
  data = {
    "roles.yml" = yamlencode({
      jaeger_writer = {
        cluster = ["monitor", "manage_index_templates"]
        indices = [
          {
            names      = ["jaeger-*"]
            privileges = ["all"]
          }
        ]
      }
    })
  }

}

# ECK reads this as a user: name, password and role. Jaeger reads the password from it too.
resource "kubernetes_secret_v1" "jaeger_user" {
  metadata {
    name      = "jaeger-user"
    namespace = kubernetes_namespace_v1.tracing.metadata[0].name
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "jaeger-user"
    password = random_password.jaeger_user.result
    roles    = "jaeger_writer"
  }

  depends_on = [kubernetes_secret_v1.jaeger_role]
}

# A separate Elasticsearch for traces, run by the ECK operator from the logging module.
resource "kubectl_manifest" "traces_elasticsearch" {
  yaml_body = file("${path.root}/../../k8s/observability/tracing/elasticsearch.yaml")

  # On destroy, wait until ECK has removed the pod and its disk.
  wait = true

  depends_on = [
    kubernetes_namespace_v1.tracing,
    kubernetes_secret_v1.jaeger_user,
    kubernetes_secret_v1.jaeger_role,
  ]
}

resource "helm_release" "jaeger" {
  name       = "jaeger"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger"
  namespace  = kubernetes_namespace_v1.tracing.metadata[0].name
  version    = "4.14.1"

  values = [file("${path.root}/../../k8s/observability/tracing/jaeger-values.yaml")]

  # Jaeger reads the password and CA Secrets that ECK creates for this Elasticsearch.
  depends_on = [kubectl_manifest.traces_elasticsearch]
}
