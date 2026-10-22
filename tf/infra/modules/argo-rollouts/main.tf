###############################################################################
# Argo Rollouts
###############################################################################
# The chart installs the controller (namespace argo-rollouts), the CRDs (Rollout,
# AnalysisTemplate, AnalysisRun, ...) and the permissions it needs, including
# editing HTTPRoutes. Values (system nodes, Gateway API plugin) are in
# k8s/argo-rollouts/helm-values.yaml.
resource "helm_release" "argo_rollouts" {
  name             = "argo-rollouts"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  namespace        = "argo-rollouts"
  create_namespace = true
  # Argo Rollouts v1.10.1
  version = "2.43.8"

  values = [
    file("${path.root}/../../k8s/argo-rollouts/helm-values.yaml")
  ]
}
