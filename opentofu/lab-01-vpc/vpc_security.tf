# =============================================================================
# vpc_security.tf
# Security / Inspection VPCs — us-east-1 and us-west-2
#
# Each region is a separate call to the ./modules/security-vpc module, bound
# to a different provider (see providers.tf for the aws.west alias). See
# modules/security-vpc/main.tf for why this can't be a single for_each block.
# =============================================================================

module "security_vpc_east" {
  source = "./modules/security-vpc"
  providers = {
    aws = aws
  }

  region       = "us-east-1"
  vpc_cidr     = local.security_vpcs["us-east-1"].cidr
  azs          = local.security_vpcs["us-east-1"].azs
  subnet_cidrs = local.security_vpcs["us-east-1"].subnet_cidrs
  common_tags  = local.common_tags
}

module "security_vpc_west" {
  source = "./modules/security-vpc"
  providers = {
    aws = aws.west
  }

  region       = "us-west-2"
  vpc_cidr     = local.security_vpcs["us-west-2"].cidr
  azs          = local.security_vpcs["us-west-2"].azs
  subnet_cidrs = local.security_vpcs["us-west-2"].subnet_cidrs
  common_tags  = local.common_tags
}
