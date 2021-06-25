##################################################################################
# VARIABLES
##################################################################################

variable "region" {
  default = "us-east-1"
}
variable "web_network_address_space" {
  type = map(string)
}
variable "web_subnet_count" {
  type = map(number)
}

##################################################################################
# LOCALS
##################################################################################

locals {
  common_tags = {
    Environment = terraform.workspace
    Owner       = "alexandre.osada"
  }
}
