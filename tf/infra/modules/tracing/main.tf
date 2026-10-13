# Traces: frontend and backend (OpenTelemetry) -> Jaeger -> Elasticsearch "traces"

# The backend sends spans to jaeger.tracing.svc.cluster.local:4318.
resource "kubernetes_namespace_v1" "tracing" {
  metadata {
    name = "tracing"
    # join the Istio mesh (ambient mode), so backend -> Jaeger and Grafana -> Jaeger
    # get mTLS. The Elasticsearch pod opts out (it has its own TLS, see elasticsearch.yaml).
    labels = {
      "istio.io/dataplane-mode" = "ambient"
    }
  }
}

# jaeger-user: can only use the jaeger-* indices (and create their index templates)
resource "random_password" "jaeger_user" {
  length  = 32
  special = false
}

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

# ECK creates the user from this Secret; Jaeger reads its password from the same Secret.
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

# Separate Elasticsearch for traces (run by the ECK operator from the logging module)
resource "kubectl_manifest" "traces_elasticsearch" {
  yaml_body = file("${path.root}/../../k8s/observability/tracing/elasticsearch.yaml")

  # on destroy, wait until ECK has deleted the pod and its disk
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

  # Jaeger needs the CA Secret that ECK creates for this Elasticsearch
  depends_on = [kubectl_manifest.traces_elasticsearch]
}
