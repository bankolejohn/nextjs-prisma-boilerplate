variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used to prefix all resource names"
  type        = string
  default     = "npb"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "instance_type" {
  description = "EC2 instance type — t3.small minimum for yarn build"
  type        = string
  default     = "t3.small"
}

variable "volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file to register as EC2 key pair"
  type        = string
  default     = "~/.ssh/npb-prod-key.pub"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH — restrict to your IP in production"
  type        = string
  # Override in terraform.tfvars with your actual IP: "1.2.3.4/32"
  default     = "0.0.0.0/0"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}
