# -----------------------------------------------------------------------
# SSH Key Pair — registers your local public key with AWS
# -----------------------------------------------------------------------
resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-${var.environment}-key"
  public_key = file(var.ssh_public_key_path)

  tags = {
    Name = "${var.project_name}-${var.environment}-key"
  }
}

# -----------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app_server.id]
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.volume_size_gb
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-${var.environment}-root-vol"
    }
  }

  # User data script — runs once on first boot after instance creation
  # Installs Docker, Nginx, Git and sets up the ubuntu user
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # System update
    apt-get update -y
    apt-get upgrade -y

    # Install Docker
    apt-get install -y ca-certificates curl gnupg git nginx
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Allow ubuntu user to run Docker without sudo
    usermod -aG docker ubuntu

    # Enable services on boot
    systemctl enable docker
    systemctl enable nginx
    systemctl start nginx

    # Create the external Docker network required by docker-compose.prod.yml
    docker network create proxy || true

    echo "Bootstrap complete" > /tmp/bootstrap-done.txt
  EOF

  tags = {
    Name = "${var.project_name}-${var.environment}-server"
  }

  # Prevent accidental instance replacement when user_data changes
  # user_data changes only take effect on new instances, not running ones
  lifecycle {
    ignore_changes = [user_data]
  }
}

# -----------------------------------------------------------------------
# Elastic IP — static public IP that survives instance stop/start
# -----------------------------------------------------------------------
resource "aws_eip" "app_server" {
  instance = aws_instance.app_server.id
  domain   = "vpc"

  # Elastic IP must be created after the internet gateway
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-${var.environment}-eip"
  }
}
