variable "project_name" {
  description = "Name of the project used for resource naming."
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to EKS resources."
  type        = map(string)
  default     = {}
}

variable "public_subnet_ids" {
  description = "IDs of the public subnets used by the EKS control plane."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets used by the EKS control plane and worker nodes."
  type        = list(string)
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.33"
}

variable "endpoint_public_access" {
  description = "Whether the EKS API endpoint is publicly accessible."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Whether the EKS API endpoint is privately accessible."
  type        = bool
  default     = false
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Capacity type for the managed node group."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}
