# -----------------------------------------------------------------------
# Outputs — printed after terraform apply, useful for reference
# -----------------------------------------------------------------------

output "elastic_ip" {
  description = "Public Elastic IP of the production server"
  value       = aws_eip.app_server.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app_server.id
}

output "instance_type" {
  description = "EC2 instance type"
  value       = aws_instance.app_server.instance_type
}

output "ami_id" {
  description = "AMI used for the instance"
  value       = aws_instance.app_server.ami
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i ~/.ssh/npb-prod-key.pem ubuntu@${aws_eip.app_server.public_ip}"
}

output "app_url" {
  description = "Application URL"
  value       = "http://${aws_eip.app_server.public_ip}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.app_server.id
}
