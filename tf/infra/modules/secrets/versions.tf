###############################################################################
# Required providers
###############################################################################
# kubectl isn't a HashiCorp provider, so each module that uses it has to list it here.
terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
