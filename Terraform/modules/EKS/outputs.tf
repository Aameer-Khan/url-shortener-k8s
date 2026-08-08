output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS Kubernetes API server."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_version" {
  description = "Kubernetes version running on the EKS cluster."
  value       = aws_eks_cluster.this.version
}

output "cluster_role_arn" {
  description = "IAM role ARN used by the EKS control plane."
  value       = aws_iam_role.eks_cluster.arn
}

output "node_group_name" {
  description = "Name of the EKS managed node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_group_arn" {
  description = "ARN of the EKS managed node group."
  value       = aws_eks_node_group.this.arn
}

output "node_role_arn" {
  description = "IAM role ARN used by the EKS worker nodes."
  value       = aws_iam_role.eks_node.arn
}
