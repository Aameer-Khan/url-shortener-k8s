module "vpc" {
  source = "../../modules/VPC"

  project_name = var.project_name

  vpc_cidr = var.vpc_cidr

  availability_zones = var.availability_zones

  public_subnet_cidrs = var.public_subnet_cidrs

  private_subnet_cidrs = var.private_subnet_cidrs

  enable_nat_gateway = var.enable_nat_gateway

  single_nat_gateway = var.single_nat_gateway

  common_tags = var.common_tags
}


module "eks" {
  source = "../../modules/EKS"

  project_name = var.project_name

  common_tags = var.common_tags

  public_subnet_ids = module.vpc.public_subnet_ids

  private_subnet_ids = module.vpc.private_subnet_ids

  eks_cluster_version = var.eks_cluster_version

  endpoint_public_access = var.endpoint_public_access

  endpoint_private_access = var.endpoint_private_access

  node_instance_types = var.node_instance_types

  node_capacity_type = var.node_capacity_type

  node_desired_size = var.node_desired_size

  node_min_size = var.node_min_size

  node_max_size = var.node_max_size
}
