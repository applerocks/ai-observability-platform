terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "artemis-tfstate-994878981126"
    key          = "artemis/terraform.tfstate"
    region       = "us-east-2"
    profile      = "suresh-aws"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region  = "us-east-2"
  profile = "suresh-aws"

  default_tags {
    tags = {
      Project   = "artemis"
      ManagedBy = "terraform"
    }
  }
}
