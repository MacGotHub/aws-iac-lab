variable "region" {
  description = "AWS region this security VPC lives in — used for tagging only, the actual region comes from the provider passed in via the module's `providers` argument"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the security VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to build tgw/gwlbe/untrust/trust_mgmt subnets in"
  type        = list(string)
}

variable "subnet_cidrs" {
  description = "Per-AZ subnet CIDRs, keyed by AZ name"
  type = map(object({
    tgw        = string
    gwlbe      = string
    untrust    = string
    trust_mgmt = string
  }))
}

variable "common_tags" {
  description = "Common tags merged onto every resource"
  type        = map(string)
}
