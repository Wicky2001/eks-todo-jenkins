# Gateway API CRDs (Gateway, HTTPRoute, ...). Kubernetes doesn't ship them, so we
# install them from the official v1.5.1 release, one file per CRD in k8s/gateway-api-crds.
# Istio and cert-manager both use them.

###############################################################################
# Paths
###############################################################################
# Folder with the CRD files.
locals {
  crds_dir = "${path.root}/../../k8s/gateway-api-crds"
}

###############################################################################
# Gateway API CRDs
###############################################################################
# Server-side apply because some CRDs (httproutes) are too big for a normal kubectl apply
resource "kubectl_manifest" "gateway_api_crds" {
  for_each = toset([
    "gatewayclasses.yaml",
    "gateways.yaml",
    "httproutes.yaml",
    "grpcroutes.yaml",
    "tlsroutes.yaml",
    "referencegrants.yaml",
    "backendtlspolicies.yaml",
    "listenersets.yaml",
  ])

  yaml_body         = file("${local.crds_dir}/${each.key}")
  server_side_apply = true
}

###############################################################################
# Safe-upgrades policy
###############################################################################
# Part of the same release: blocks installing an older or experimental version of
# these CRDs over this one by mistake
resource "kubectl_manifest" "safe_upgrades_policy" {
  yaml_body = file("${local.crds_dir}/safe-upgrades-policy.yaml")
}

###############################################################################
# Safe-upgrades policy binding
###############################################################################
# Turns on the policy above.
resource "kubectl_manifest" "safe_upgrades_policy_binding" {
  yaml_body = file("${local.crds_dir}/safe-upgrades-policy-binding.yaml")

  depends_on = [kubectl_manifest.safe_upgrades_policy]
}
