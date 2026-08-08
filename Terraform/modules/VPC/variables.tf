variable "project_name" {
  description = "Name of the project used for resource naming."
  type        = string
}


variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}


variable "availability_zones" {
  description = "Availability Zones where public and private subnets will be created."
  type        = list(string)
}


variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "The number of public subnet CIDRs must match the number of availability zones."
  }
}


variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.availability_zones)
    error_message = "The number of private subnet CIDRs must match the number of availability zones."
  }
}


variable "enable_nat_gateway" {
  description = "Whether to create NAT Gateway resources for private subnet internet access."
  type        = bool
  default     = true
}


variable "single_nat_gateway" {
  description = "Whether to use a single NAT Gateway for all private subnets. Set to false for one NAT Gateway per Availability Zone."
  type        = bool
  default     = true
}


variable "common_tags" {
  description = "Common tags applied to all VPC resources."
  type        = map(string)
  default     = {}
}
