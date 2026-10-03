###############################################################################
# Environment
###############################################################################
variable "region" {
  type = string
}

variable "aws_profile" {
  type    = string
  default = "terraform-user"
}