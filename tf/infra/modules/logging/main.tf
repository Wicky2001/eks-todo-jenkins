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
