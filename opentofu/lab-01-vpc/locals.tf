locals {

  # ---------------------------------------------------------------------------
  # Environment
  # ---------------------------------------------------------------------------
  env = var.environment # e.g. "lab", "sandbox"

  # ---------------------------------------------------------------------------
  # Security VPC definitions — one per region
  # Each region defines its AZs and a /22 VPC CIDR.
  # Subnet CIDRs are carved out of the VPC CIDR using cidrsubnet().
  #
  # Subnet layout per AZ (all /28 = 14 usable IPs):
  #   Index 0  → tgw        (TGW attachment)
  #   Index 1  → gwlbe      (GWLB endpoint)
  #   Index 2  → untrust    (Firewall untrust / data plane)
  #   Index 3  → trust_mgmt (Firewall trust / mgmt — /27 = 30 usable IPs)
  #
  # The /22 gives us 1024 IPs across:
  #   - 3 AZs × 3 × /28 subnets = 48 IPs used for tgw/gwlbe/untrust
  #   - 3 AZs × 1 × /27 subnets = 96 IPs used for trust/mgmt
  #   Plenty of room for future expansion.
  # ---------------------------------------------------------------------------
  security_vpcs = {

    "us-east-1" = {
      cidr = "10.0.16.0/22"
      azs  = ["us-east-1b", "us-east-1c", "us-east-1d"]

      # Subnet CIDRs carved from 10.0.16.0/22
      # Using explicit CIDRs here for readability and easy console cross-referencing
      subnet_cidrs = {
        "us-east-1b" = {
          tgw        = "10.0.16.0/28"
          gwlbe      = "10.0.16.16/28"
          untrust    = "10.0.16.32/28"
          trust_mgmt = "10.0.16.64/27"
        }
        "us-east-1c" = {
          tgw        = "10.0.16.96/28"
          gwlbe      = "10.0.16.112/28"
          untrust    = "10.0.16.128/28"
          trust_mgmt = "10.0.16.160/27"
        }
        "us-east-1d" = {
          tgw        = "10.0.16.192/28"
          gwlbe      = "10.0.16.208/28"
          untrust    = "10.0.16.224/28"
          trust_mgmt = "10.0.17.0/27"
        }
      }
    }

    "us-west-2" = {
      cidr = "10.0.20.0/22"
      azs  = ["us-west-2b", "us-west-2c", "us-west-2d"]

      subnet_cidrs = {
        "us-west-2b" = {
          tgw        = "10.0.20.0/28"
          gwlbe      = "10.0.20.16/28"
          untrust    = "10.0.20.32/28"
          trust_mgmt = "10.0.20.64/27"
        }
        "us-west-2c" = {
          tgw        = "10.0.20.96/28"
          gwlbe      = "10.0.20.112/28"
          untrust    = "10.0.20.128/28"
          trust_mgmt = "10.0.20.160/27"
        }
        "us-west-2d" = {
          tgw        = "10.0.20.192/28"
          gwlbe      = "10.0.20.208/28"
          untrust    = "10.0.20.224/28"
          trust_mgmt = "10.0.21.0/27"
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Hub VPC definition (us-east-1 only)
  # Refactored from individual resource blocks to a structured local.
  # ---------------------------------------------------------------------------
  hub_vpc = {
    cidr   = "10.0.0.0/20"
    region = "us-east-1"

    subnet_cidrs = {
      "us-east-1a" = {
        public   = "10.0.1.0/24"
        firewall = "10.0.2.0/24"
      }
      "us-east-1b" = {
        public   = "10.0.3.0/24"
        firewall = "10.0.4.0/24"
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Flattened subnet maps — used by for_each in vpc_security.tf
  # Produces a flat map keyed by "<region>-<az>-<subnet_type>"
  # e.g. "us-east-1-us-east-1b-tgw"
  # ---------------------------------------------------------------------------

  # All TGW subnets across both regions
  security_tgw_subnets = {
    for region, vpc in local.security_vpcs :
    region => {
      for az, cidrs in vpc.subnet_cidrs :
      az => cidrs.tgw
    }
  }

  # All GWLBE subnets across both regions
  security_gwlbe_subnets = {
    for region, vpc in local.security_vpcs :
    region => {
      for az, cidrs in vpc.subnet_cidrs :
      az => cidrs.gwlbe
    }
  }

  # All untrust subnets across both regions
  security_untrust_subnets = {
    for region, vpc in local.security_vpcs :
    region => {
      for az, cidrs in vpc.subnet_cidrs :
      az => cidrs.untrust
    }
  }

  # All trust/mgmt subnets across both regions
  security_trust_mgmt_subnets = {
    for region, vpc in local.security_vpcs :
    region => {
      for az, cidrs in vpc.subnet_cidrs :
      az => cidrs.trust_mgmt
    }
  }

  # ---------------------------------------------------------------------------
  # Common tags applied to all resources
  # ---------------------------------------------------------------------------
  common_tags = {
    Environment = local.env
    ManagedBy   = "opentofu"
    Project     = "aws-iac-lab"
    Owner       = var.owner
  }
}
