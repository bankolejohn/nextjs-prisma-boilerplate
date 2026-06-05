# -----------------------------------------------------------------------
# Security Group — firewall rules for the EC2 instance
# -----------------------------------------------------------------------
resource "aws_security_group" "app_server" {
  name        = "${var.project_name}-${var.environment}-sg"
  description = "Security group for ${var.project_name} production server"
  vpc_id      = aws_vpc.main.id

  # SSH — restricted to your IP (set allowed_ssh_cidr in terraform.tfvars)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # HTTP — public
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS — public (for when SSL is added)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Direct app access — restrict to your IP for debugging only
  # Remove this rule once Nginx is confirmed working
  ingress {
    description = "Direct app port (temporary)"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Allow all outbound traffic (Docker pulls, apt updates, etc.)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-sg"
  }
}
