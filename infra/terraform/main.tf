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

# -----------------------------------------------
# EKS
# -----------------------------------------------
module "eks" {
  source = "./modules/eks"

  project             = local.project
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  kubernetes_version  = "1.32"
  node_instance_types = ["t3.large"]
  node_desired_size   = 2
  node_min_size       = 2
  node_max_size       = 4
  node_disk_size      = 30
  tags                = local.tags
}

# -----------------------------------------------
# ALB Controller (IAM for AWS Load Balancer Controller)
# -----------------------------------------------
module "alb_controller" {
  source = "./modules/alb-controller"

  project           = local.project
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  vpc_id            = module.vpc.vpc_id
  region            = local.region
  tags              = local.tags
}
