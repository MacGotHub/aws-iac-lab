terraform {
  backend "s3" {
    bucket         = "351668480009-opentofu-state"
    key            = "ec2-w2/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "opentofu-state-lock"
    encrypt        = true
  }
}
