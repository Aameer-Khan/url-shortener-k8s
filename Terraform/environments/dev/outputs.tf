output "vpc_id" {
  description = "ID of the development VPC."
  value       = module.vpc.vpc_id
}


output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = module.vpc.public_subnet_ids
}


output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = module.vpc.private_subnet_ids
}


output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways."
  value       = module.vpc.nat_gateway_ids
}


output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}


output "eks_cluster_endpoint" {
  description = "EKS Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}


output "eks_cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = module.eks.cluster_arn
}


output "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster."
  value       = module.eks.cluster_version
}


output "eks_node_group_name" {
  description = "Name of the EKS managed node group."
  value       = module.eks.node_group_name
}
