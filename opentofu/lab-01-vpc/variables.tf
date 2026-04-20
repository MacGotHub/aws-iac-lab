variable "environment" {
  description = "Environment name applied to all resource tags (e.g. lab, sandbox)"
  type        = string
  default     = "lab"
}

variable "owner" {
  description = "Owner tag applied to all resources — useful when sharing a sandbox account"
  type        = string
  default     = "derek"
}

variable "aws_primary_region" {
  description = "Primary AWS region for hub VPC and TGW"
  type        = string
  default     = "us-east-1"
}

variable "aws_secondary_region" {
  description = "Secondary AWS region for west security VPC"
  type        = string
  default     = "us-west-2"
}
