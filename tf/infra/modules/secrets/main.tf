# Secrets: the passwords live in AWS Secrets Manager, and ESO (External Secrets Operator)
# copies them into Kubernetes Secrets. The ExternalSecret files that say what to copy are
# in the GitOps repo (platform/*/manifests/secrets).
#
#   1. Terraform makes each password and stores it in AWS Secrets Manager (eks-todo/...)
#   2. Terraform installs ESO, gives it read access through Pod Identity, and creates
#      the ClusterSecretStore (k8s/external-secrets/cluster-secret-store.yaml)
#   3. Argo CD applies the ExternalSecrets, ESO creates the Kubernetes Secrets

###############################################################################
# Secret names
###############################################################################
# AWS name prefix, and the list of secrets.
locals {
  prefix = "eks-todo"

  # the secret names, as a plain list: Terraform can't loop over values that contain
  # passwords, so the loops below go over these names and look the values up
  secret_names = ["grafana-admin", "fluentbit-user", "grafana-user", "jaeger-user", "grafana-github-oauth", "mail-pass"]
}

###############################################################################
# Grafana admin password
###############################################################################
# Random password for Grafana's admin login.
resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

###############################################################################
# fluentbit-user password
###############################################################################
# Fluent Bit logs in to the logs Elasticsearch with it.
resource "random_password" "fluentbit_user" {
  length  = 32
  special = false
}

###############################################################################
# grafana-user password
###############################################################################
# Grafana reads the logs Elasticsearch with it.
resource "random_password" "grafana_user" {
  length  = 32
  special = false
}

###############################################################################
# jaeger-user password
###############################################################################
# Jaeger writes to the traces Elasticsearch with it.
resource "random_password" "jaeger_user" {
  length  = 32
  special = false
}

###############################################################################
# Secret contents
###############################################################################
# One secret per Kubernetes Secret. Each one holds JSON whose fields become the keys of
# the Kubernetes Secret (the ExternalSecrets use "extract", which copies every field).
locals {
  secrets = {
    # Grafana's admin login (monitoring)
    grafana-admin = {
      admin-user     = "admin"
      admin-password = random_password.grafana_admin.result
    }
    # Elasticsearch users, in the format ECK expects (username, password, roles)
    fluentbit-user = {
      username = "fluentbit-user"
      password = random_password.fluentbit_user.result
      roles    = "fluentbit_writer"
    }
    grafana-user = {
      username = "grafana-user"
      password = random_password.grafana_user.result
      roles    = "grafana_reader"
    }
    jaeger-user = {
      username = "jaeger-user"
      password = random_password.jaeger_user.result
      roles    = "jaeger_writer"
    }
    # Grafana's "Log in with GitHub" (read as GF_AUTH_GITHUB_* environment variables)
    grafana-github-oauth = {
      client-id             = var.grafana_github_client_id
      client-secret         = var.grafana_github_client_secret
      allowed-organizations = var.github_org
      # GitHub teams come in as "@<org>/<team>": platform = Admin, developers = Viewer
      role-attribute-path = "contains(groups[*], '@${var.github_org}/platform') && 'Admin' || contains(groups[*], '@${var.github_org}/developers') && 'Viewer'"
    }
    # Gmail app password Alertmanager uses to send alert emails
    mail-pass = {
      gmail-pass = var.alert_email_password
    }
  }
}

###############################################################################
# AWS Secrets Manager secrets
###############################################################################
# One secret per name, called eks-todo/<name>.
resource "aws_secretsmanager_secret" "this" {
  for_each = toset(local.secret_names)

  name        = "${local.prefix}/${each.key}"
  description = "Copied into the Kubernetes Secret ${each.key} by External Secrets Operator"

  # Delete right away on terraform destroy. The default keeps it 7-30 days, and a new
  # secret with the same name can't be created until then (we rebuild often).
  recovery_window_in_days = 0
}

###############################################################################
# Secret values
###############################################################################
# Stores the JSON from local.secrets in each secret.
resource "aws_secretsmanager_secret_version" "this" {
  for_each = toset(local.secret_names)

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = jsonencode(local.secrets[each.key])
}

###############################################################################
# ESO IAM role
###############################################################################
# IAM role that may read only the eks-todo/* secrets, given to ESO's ServiceAccount
# (external-secrets in namespace external-secrets) through Pod Identity
module "external_secrets_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "${var.cluster_name}-external-secrets-iam"

  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = [for s in aws_secretsmanager_secret.this : s.arn]

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}

###############################################################################
# External Secrets Operator
###############################################################################
# ESO: three small Deployments (controller, webhook, cert-controller), no DaemonSet
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "2.11.0"

  values = [
    yamlencode({
      # must match the service account in the Pod Identity association above
      serviceAccount = { name = "external-secrets" }

      tolerations    = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }]
      webhook        = { tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }] }
      certController = { tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists", effect = "NoSchedule" }] }
    })
  ]

  depends_on = [module.external_secrets_pod_identity]
}

###############################################################################
# ClusterSecretStore
###############################################################################
# The connection to AWS Secrets Manager that the ExternalSecrets point to
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = templatefile("${path.root}/../../k8s/external-secrets/cluster-secret-store.yaml", {
    region = var.region
  })

  depends_on = [helm_release.external_secrets]
}
