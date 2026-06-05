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
  # Fully bootstraps the server so it is pipeline-ready without manual SSH
  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    exec > /var/log/user-data.log 2>&1

    echo "==> [1/7] System update"
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

    echo "==> [2/7] Install base packages"
    apt-get install -y \
      ca-certificates \
      curl \
      gnupg \
      git \
      nginx \
      openssl

    echo "==> [3/7] Install Docker"
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
    apt-get install -y \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-compose-plugin

    echo "==> [4/7] Configure Docker and services"
    usermod -aG docker ubuntu
    systemctl enable docker
    systemctl start docker
    systemctl enable nginx
    systemctl start nginx

    echo "==> [5/7] Create required Docker networks"
    docker network create proxy || true

    echo "==> [6/7] Clone application repository"
    cd /home/ubuntu
    git clone https://github.com/bankolejohn/nextjs-prisma-boilerplate.git
    chown -R ubuntu:ubuntu /home/ubuntu/nextjs-prisma-boilerplate

    echo "==> [7/7] Configure Nginx reverse proxy"
    cat > /etc/nginx/sites-available/npb-app <<'NGINX'
    server {
        listen 80;
        server_name _;

        client_max_body_size 10M;

        location / {
            proxy_pass http://localhost:3001;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
        }
    }
    NGINX

    ln -sf /etc/nginx/sites-available/npb-app /etc/nginx/sites-enabled/npb-app
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx

    echo "==> Bootstrap complete. Server is pipeline-ready."
    echo "==> Next step: SSH in and create envs/production-docker/.env.production.docker.local"
    echo "==> Then push a commit to trigger the CI/CD pipeline."
    echo "Bootstrap finished at $(date)" > /tmp/bootstrap-done.txt
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
