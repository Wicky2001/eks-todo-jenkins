# What the monitoring, logging and tracing stacks need before Argo CD installs them
# (cards in the GitOps repo, argocd/platform/): their namespaces and two operators.
# Their passwords come from AWS Secrets Manager through ESO (tf/infra/modules/secrets).

###############################################################################
# monitoring namespace
###############################################################################
# Prometheus, Alertmanager and Grafana run here.
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
    # join the Istio mesh (ambient mode): pod-to-pod traffic gets mTLS
    labels = {
      "istio.io/dataplane-mode" = "ambient"
    }
  }
}

###############################################################################
# logging namespace
###############################################################################
# not in the mesh: Fluent Bit and Elasticsearch already talk over their own TLS
resource "kubernetes_namespace_v1" "logging" {
  metadata {
    name = "logging"
  }
}

###############################################################################
# tracing namespace
###############################################################################
# Jaeger and the traces Elasticsearch run here.
resource "kubernetes_namespace_v1" "tracing" {
  metadata {
    name = "tracing"
    # join the Istio mesh (ambient mode), so backend -> Jaeger and Grafana -> Jaeger
    # get mTLS. The Elasticsearch pod opts out (it has its own TLS).
    labels = {
      "istio.io/dataplane-mode" = "ambient"
    }
  }
}

###############################################################################
# ECK operator
###############################################################################
# ECK operator. It runs both Elasticsearch clusters ("logs" and "traces"), which Argo CD creates.
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

###############################################################################
# trust-manager
###############################################################################
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
