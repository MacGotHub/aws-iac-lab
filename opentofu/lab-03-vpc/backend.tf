terraform {
  backend "s3" {
    bucket         = "351668480009-opentofu-state"
    key            = "west-vpc/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "opentofu-state-lock"
    encrypt        = true
  }
}
