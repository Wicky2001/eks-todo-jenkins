variable "github_org" {
  description = "GitHub org whose members can log in. Its teams decide the role."
  type        = string
}

variable "github_client_id" {
  description = "Client ID of the Argo CD OAuth App in GitHub"
  type        = string
}

variable "github_client_secret" {
  description = "Client secret of the Argo CD OAuth App in GitHub"
  type        = string
  sensitive   = true
}
