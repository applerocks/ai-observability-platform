locals {
  region  = var.region
  project = var.project
  azs     = ["${var.region}a", "${var.region}b"]

  tags = {
    Project   = var.project
    ManagedBy = "terraform"
  }
}

# -----------------------------------------------
# VPC
# -----------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project              = local.project
  vpc_cidr             = "10.0.0.0/16"
  azs                  = local.azs
  public_subnet_cidrs  = ["10.0.0.0/20", "10.0.16.0/20"]
  private_subnet_cidrs = ["10.0.64.0/20", "10.0.80.0/20"]
  enable_nat_gateway   = true
  tags                 = local.tags
}
