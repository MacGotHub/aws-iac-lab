terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default provider — us-west-2 (where the new TGW lives)
provider "aws" {
  region = "us-west-2"
}

# Aliased provider — us-east-1 (used to accept peering and add east-side routes)
provider "aws" {
  alias  = "east"
  region = "us-east-1"
}
