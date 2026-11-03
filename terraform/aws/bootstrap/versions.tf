terraform {
  required_version = "= 1.15.8"
  backend "local" {
    path = "../../../.local/aws/bootstrap.tfstate"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.71.0"
    }
  }
}
