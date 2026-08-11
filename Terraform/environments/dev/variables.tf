variable "aws_region" {
  description = "AWS region where the development environment will be deployed."
  type        = string
}


variable "project_name" {
  description = "Project name used for naming AWS resources."
  type        = string
}


variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}


variable "availability_zones" {
  description = "Availability Zones used by the environment."
  type        = list(string)
}


variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
}


variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
}


variable "enable_nat_gateway" {
  description = "Whether NAT Gateway should be created."
  type        = bool
}


variable "single_nat_gateway" {
  description = "Whether the environment should use one NAT Gateway."
  type        = bool
}


variable "eks_cluster_version" {
  description = "Kubernetes version for EKS."
  type        = string
}


variable "endpoint_public_access" {
  description = "Whether the EKS API endpoint has public access."
  type        = bool
}


variable "endpoint_private_access" {
  description = "Whether the EKS API endpoint has private access."
  type        = bool
}


variable "node_instance_types" {
  description = "EC2 instance types used by the managed node group."
  type        = list(string)
}


variable "node_capacity_type" {
  description = "Capacity type used by the managed node group."
  type        = string
}


variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
}


variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
}


variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
}


variable "common_tags" {
  description = "Common tags applied to infrastructure resources."
  type        = map(string)
}
