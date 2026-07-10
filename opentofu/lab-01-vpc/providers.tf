terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Used by module.security_vpc_west (see vpc_security.tf) — a provider can't
# vary per-key within a single for_each/module block, so the west security
# VPC is built by a separate module call bound to this alias.
provider "aws" {
  alias  = "west"
  region = "us-west-2"
}
