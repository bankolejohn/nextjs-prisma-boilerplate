# Deployment Documentation

## nextjs-prisma-boilerplate — Production Deployment Guide

**Project:** nextjs-prisma-boilerplate  
**Stack:** Next.js 12, Express, PostgreSQL, Prisma, Docker  
**Target Environment:** AWS EC2 (Ubuntu 24.04)  
**Last Updated:** June 2026

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Phase 1 — Local Development](#2-phase-1--local-development)
3. [Phase 2 — Containerization](#3-phase-2--containerization)
4. [Phase 3 — EC2 Deployment with Docker](#4-phase-3--ec2-deployment-with-docker)
5. [Phase 4 — CI/CD with GitHub Actions](#5-phase-4--cicd-with-github-actions)
6. [Phase 5 — Infrastructure as Code (Terraform)](#6-phase-5--infrastructure-as-code-terraform)
7. [Phase 6 — Observability (Prometheus, Grafana, Alerts)](#7-phase-6--observability-prometheus-grafana-alerts)
8. [Phase 7 — Kubernetes (Minikube)](#8-phase-7--kubernetes-minikube)
9. [Troubleshooting Reference](#9-troubleshooting-reference)
10. [Architecture Summary](#10-architecture-summary)

---

## 1. Project Overview

This is a full-stack blog/content platform with the following capabilities:

- User registration and authentication (email/password, Google OAuth, Facebook OAuth)
- Create, read, update, delete posts with draft/publish system
- User profiles with avatar and header image uploads
- Paginated, searchable post and user listings
- Admin role with elevated permissions
- Prometheus metrics endpoint at `/api/metrics`

### Tech Stack

| Layer             | Technology                                      |
| ----------------- | ----------------------------------------------- |
| Frontend          | Next.js 12 (Pages Router), React 18, TypeScript |
| Backend           | Next.js API routes + custom Express server      |
| Database          | PostgreSQL 14                                   |
| ORM               | Prisma 4                                        |
| Auth              | NextAuth v4                                     |
| Container Runtime | Docker + Docker Compose                         |
| Reverse Proxy     | Nginx                                           |
| Observability     | Prometheus, Grafana                             |

### Repository Structure

```
nextjs-prisma-boilerplate/
├── pages/              # Next.js routes and API routes
├── components/         # Reusable UI components
├── views/              # Page-level content components
├── layouts/            # Page layout wrappers
├── lib-client/         # Client-side React Query hooks and utilities
├── lib-server/         # Server-side services, middleware, Prisma client
├── prisma/             # Schema, migrations, seed script
├── server/             # Custom Express server entry point
├── types/              # TypeScript type definitions
├── envs/               # Environment variable files per environment
├── Dockerfile.dev      # Development Docker image
├── Dockerfile.prod     # Production Docker image (multi-stage)
├── docker-compose.dev.yml
├── docker-compose.prod.yml
└── prometheus.yml      # Prometheus scrape configuration
```

---

## 2. Phase 1 — Local Development

### Goal

Run the application locally without Docker to understand the codebase and verify it works end to end.

### Prerequisites

- Node.js 18
- PostgreSQL 14 (Homebrew on macOS: `brew install postgresql@14`)
- Yarn

### Setup

**1. Create a local database**

```bash
psql -c 'CREATE DATABASE "npb-db-dev";'
```

**2. Create the local environment file**

Create `.env.development.local` in the project root:

```bash
APP_ENV=local
SITE_PROTOCOL=http
SITE_HOSTNAME=localhost
PORT=3001

NEXTAUTH_URL=http://localhost:3001
DATABASE_URL=postgresql://<your-mac-username>@localhost:5432/npb-db-dev?schema=public&connection_limit=10&pool_timeout=20

SECRET=random-string-local

FACEBOOK_CLIENT_ID=
FACEBOOK_CLIENT_SECRET=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=

NEXT_PUBLIC_BASE_URL=http://localhost:3001
NEXT_PUBLIC_POSTS_PER_PAGE=10
NEXT_PUBLIC_USERS_PER_PAGE=10
NEXT_PUBLIC_DEFAULT_THEME=theme-light
```

> **Note:** On macOS with Homebrew PostgreSQL, the username is your system username and there is no password by default.

**3. Run migrations and seed the database**

```bash
npx dotenv -e .env.development.local -- npx prisma migrate dev --skip-seed
npx dotenv -e .env.development.local -- npx prisma db seed
```

**4. Build and start**

```bash
npx dotenv -e .env.development.local -- yarn build
npx dotenv -e .env.development.local -- yarn start
```

Access the app at `http://localhost:3001`.

### Why Local First

Running locally without Docker establishes a baseline. If the app works locally but not in Docker, the problem is in the container configuration, not the code. This separation makes debugging significantly faster.

---

## 3. Phase 2 — Containerization

### Goal

Run the entire application stack (app, database, Prometheus, Grafana) using Docker Compose for a consistent, reproducible development environment.

### Development Docker Stack

```
docker-compose.dev.yml
├── npb-app-dev      (Next.js + Express, port 3001)
├── npb-db-dev       (PostgreSQL 14, port 5432)
├── adminer-dev      (Database UI, port 8080)
├── prometheus       (Metrics collection, port 9090)
└── grafana          (Metrics dashboards, port 3002)
```

### Environment Configuration

Copy the example and fill in values:

```bash
cp envs/development-docker/.env.development.docker.local.example \
   envs/development-docker/.env.development.docker.local
```

Minimum required variables:

```bash
POSTGRES_HOSTNAME=npb-db-dev
POSTGRES_PORT=5432
POSTGRES_USER=postgres_user
POSTGRES_PASSWORD=password
POSTGRES_DB=npb-db-dev

DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOSTNAME}:${POSTGRES_PORT}/${POSTGRES_DB}?schema=public&connection_limit=10&pool_timeout=20

SECRET=random-string

MY_UID=1000
MY_GID=1000
```

### Running the Dev Stack

```bash
# Build the app image
docker compose -f docker-compose.dev.yml build npb-app-dev

# Start all services
docker compose -f docker-compose.dev.yml -p npb-dev up

# Stop and remove volumes
docker compose -f docker-compose.dev.yml -p npb-dev down -v --remove-orphans
```

### Why Development Mode is Slow

When running with `NODE_ENV=development`, Next.js compiles each page on-demand the first time it is requested. A page like `/` with 591 modules takes ~8 seconds to compile on first load. This is expected and unavoidable in development mode.

The production build (`yarn build`) pre-compiles all pages at build time, so every page loads in milliseconds. This is why the dev container feels slow compared to `yarn start` after a production build.

Additionally, on macOS, Docker mounts the entire source directory as a volume (`./:/app`). Every file read passes through the Docker-macOS filesystem bridge (VirtioFS), which adds latency on top of the compilation delay.

### Observability Setup

**Prometheus** scrapes metrics from the app's `/api/metrics` endpoint every 5 seconds.

Configuration (`prometheus.yml`):

```yaml
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: 'nextjs-app'
    metrics_path: '/api/metrics'
    static_configs:
      - targets: ['npb-app-dev:3001']
```

> **Note:** `metrics_path` is an HTTP path, not a filesystem path. Prometheus makes an HTTP GET request to the running container. The file `pages/api/metrics.ts` is served by Next.js at the URL `/api/metrics`.

**Grafana** is available at `http://localhost:3002`. Add Prometheus as a data source using `http://prometheus:9090` (container name, not localhost).

### Prometheus Metrics Implementation

The metrics module (`lib-server/metrics.ts`) uses a singleton pattern to prevent duplicate metric registration errors during Next.js hot-reload:

```typescript
import client from 'prom-client';

const register = client.register;

// Guard against hot-reload re-registration
if (!register.getSingleMetric('process_cpu_user_seconds_total')) {
  client.collectDefaultMetrics({ register });
}

export { register, client };

export const httpRequestsCounter =
  (register.getSingleMetric('http_requests_total') as client.Counter<string>) ||
  new client.Counter({
    name: 'http_requests_total',
    help: 'Total number of HTTP requests',
    labelNames: ['method', 'route', 'status'],
  });
```

> **Known limitation:** The `status` label on `httpRequestsCounter` is currently hardcoded to `200`. Accurate per-response status tracking is a planned improvement.

---

## 4. Phase 3 — EC2 Deployment with Docker

### Goal

Deploy the application to a live AWS EC2 server, accessible from the internet, with Nginx as a reverse proxy and automatic container restart on server reboot.

### Infrastructure Overview

```
Internet
    │
    ▼
AWS EC2 (Ubuntu 24.04, t3.small)
    │
    ├── Nginx (port 80) ──────────────► reverse proxy
    │                                        │
    │                                        ▼
    ├── Docker: npb-app-prod (port 3001) ← Next.js + Express
    │
    ├── Docker: npb-db-prod (port 5432) ← PostgreSQL 14
    │
    └── Docker network: proxy (external), internal-prod
```

### EC2 Instance Setup

**Launch parameters:**

- AMI: Ubuntu 24.04 LTS (64-bit x86)
- Instance type: `t3.small` minimum (t2.micro will run out of memory during `yarn build`)
- Storage: 20 GB gp3
- Key pair: Create and download `.pem` file

**Security group inbound rules:**

| Type       | Port | Source                                  |
| ---------- | ---- | --------------------------------------- |
| SSH        | 22   | Your IP only                            |
| HTTP       | 80   | 0.0.0.0/0                               |
| HTTPS      | 443  | 0.0.0.0/0                               |
| Custom TCP | 3001 | Your IP (temporary, for direct testing) |

**Assign an Elastic IP** so the server IP does not change on restart:
EC2 → Elastic IPs → Allocate → Associate with instance.

### Server Prerequisites

SSH into the server and install dependencies:

```bash
# System update
sudo apt update && sudo apt upgrade -y

# Docker (official Docker repository)
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Allow ubuntu user to run Docker without sudo
sudo usermod -aG docker ubuntu
newgrp docker

# Enable Docker on boot
sudo systemctl enable docker

# Nginx
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Git
sudo apt install -y git
```

### Clone the Repository

```bash
cd ~
git clone https://github.com/<your-username>/nextjs-prisma-boilerplate.git
cd nextjs-prisma-boilerplate
```

### Production Environment File

Create `envs/production-docker/.env.production.docker.local`:

```bash
# PostgreSQL — Docker creates this database on first start
POSTGRES_USER=npb_user
POSTGRES_PASSWORD=<strong-password>
POSTGRES_DB=npb-prod

# App database connection — hostname matches the container name in docker-compose.prod.yml
DATABASE_URL=postgresql://npb_user:<strong-password>@npb-db-prod:5432/npb-prod?schema=public&connection_limit=10&pool_timeout=20

# NextAuth
SECRET=<output of: openssl rand -base64 32>

# Server address — use Elastic IP, not localhost
SITE_PROTOCOL=http
SITE_HOSTNAME=<ELASTIC_IP>
PORT=3001
NEXTAUTH_URL=http://<ELASTIC_IP>

# OAuth (leave blank unless credentials are available)
FACEBOOK_CLIENT_ID=
FACEBOOK_CLIENT_SECRET=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=

MY_UID=1000
MY_GID=1000
```

> **Important:** `NEXTAUTH_URL` must be a hardcoded full URL. Variable expansion like `${SITE_PROTOCOL}://${SITE_HOSTNAME}:${PORT}` does not work across separate `env_file` entries in Docker Compose.

### Building the Production Image

The production `Dockerfile.prod` uses a multi-stage Alpine build that includes OpenSSL 1.1, solving the Ubuntu 24.04 / Next.js 12 SWC incompatibility (see Troubleshooting section).

`docker-compose.prod.yml` passes `NEXTAUTH_URL` and `DATABASE_URL` as build arguments. Docker Compose reads build args from the **host shell environment**, not from `env_file`. Export them before building:

```bash
export NEXTAUTH_URL=http://<ELASTIC_IP>
export DATABASE_URL=postgresql://npb_user:<password>@npb-db-prod:5432/npb-prod?schema=public

docker compose -f docker-compose.prod.yml build
```

### Creating Required Docker Networks

`docker-compose.prod.yml` references an external `proxy` network. Create it before starting:

```bash
docker network create proxy
```

### Starting the Application

```bash
docker compose -f docker-compose.prod.yml -p npb-prod up -d
```

Monitor startup:

```bash
docker logs npb-app-prod -f
```

Expected output when ready:

```
> NODE_ENV=production
> Server listening at http://<ELASTIC_IP>:3001
```

### Container Restart Policy

Set containers to restart automatically on server reboot:

```bash
docker update --restart=unless-stopped npb-app-prod
docker update --restart=unless-stopped npb-db-prod
```

Combined with `sudo systemctl enable docker`, the full restart chain is:

```
Server reboots
    → systemd starts Docker daemon
        → Docker starts containers with restart=unless-stopped
            → App is live without manual intervention
```

### Nginx Reverse Proxy

Create the site configuration:

```bash
sudo nano /etc/nginx/sites-available/npb-app
```

```nginx
server {
    listen 80;
    server_name <ELASTIC_IP>;

    # Max upload size for avatar and header images
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
```

Enable the configuration:

```bash
sudo ln -s /etc/nginx/sites-available/npb-app /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

The application is now accessible at `http://<ELASTIC_IP>` on port 80.

---

## 5. Phase 4 — CI/CD with GitHub Actions

### Goal

Eliminate manual deployments entirely. Every push to `main` automatically builds a new Docker image, pushes it to Docker Hub, and deploys it to the EC2 server. From this point forward, deploying is just `git push`.

### Pipeline Overview

```
Developer pushes to main
         │
         ▼
┌─────────────────────────────┐
│   Job 1: build-and-push     │
│                             │
│  1. Checkout code           │
│  2. Login to Docker Hub     │
│  3. Build Dockerfile.prod   │
│     (with build args)       │
│  4. Push image:             │
│     - :latest               │
│     - :<commit-sha>         │
└────────────┬────────────────┘
             │ on success
             ▼
┌─────────────────────────────┐
│   Job 2: deploy             │
│                             │
│  1. SSH into EC2            │
│  2. git pull origin main    │
│  3. docker pull :latest     │
│  4. docker compose down     │
│  5. docker compose up -d    │
│  6. prisma migrate deploy   │
│  7. docker image prune      │
└─────────────────────────────┘
```

### Workflow File

Location: `.github/workflows/deploy.yml`

Triggers:

- Every push to the `main` branch
- Manual trigger via GitHub Actions UI (`workflow_dispatch`)

### Required GitHub Secrets

Go to: **GitHub → Repository → Settings → Secrets and variables → Actions**

Add the following repository secrets:

| Secret Name          | Description                                  | Example Value                                                        |
| -------------------- | -------------------------------------------- | -------------------------------------------------------------------- |
| `DOCKERHUB_USERNAME` | Docker Hub account username                  | `youruser`                                                           |
| `DOCKERHUB_TOKEN`    | Docker Hub access token (not password)       | `dckr_pat_xxx...`                                                    |
| `NPB_DATABASE_URL`   | Full production database connection string   | `postgresql://npb_user:pass@npb-db-prod:5432/npb-prod?schema=public` |
| `NPB_NEXTAUTH_URL`   | Full public URL of the application           | `http://44.200.64.211`                                               |
| `EC2_HOST`           | EC2 Elastic IP address                       | `44.200.64.211`                                                      |
| `EC2_USERNAME`       | SSH username on EC2                          | `ubuntu`                                                             |
| `EC2_SSH_KEY`        | Full contents of the `.pem` private key file | `-----BEGIN RSA PRIVATE KEY-----...`                                 |

**Generating a Docker Hub access token:**
Docker Hub → Account Settings → Security → New Access Token → copy the token.

**Getting the EC2 SSH key:**

```bash
cat ~/.ssh/npb-prod-key.pem
```

Copy the entire output including the `-----BEGIN` and `-----END` lines.

### Why Build Args Come From Secrets, Not env_file

`Dockerfile.prod` requires `DATABASE_URL` and `NEXTAUTH_URL` at **build time** (not just runtime) because Next.js embeds the `NEXTAUTH_URL` into the compiled client bundle for SEO, and `DATABASE_URL` is needed if any pages use `getStaticProps`.

Docker Compose reads build args from the **host shell environment**. In the pipeline, GitHub Actions exposes secrets as environment variables via the `build-args` input — so they are available to the build without ever being written to a file.

### Docker Image Tagging Strategy

Every build produces two tags:

```
youruser/nextjs-prisma-boilerplate:latest      ← always the newest build
youruser/nextjs-prisma-boilerplate:<sha>       ← e.g. :a1b2c3d4...
```

The commit SHA tag gives you full traceability — you can look at any running container and know exactly which commit it was built from. It also enables rollbacks:

```bash
# Roll back to a previous version
docker pull youruser/nextjs-prisma-boilerplate:<previous-sha>
docker tag youruser/nextjs-prisma-boilerplate:<previous-sha> \
           youruser/nextjs-prisma-boilerplate:latest
docker compose -f docker-compose.prod.yml -p npb-prod up -d
```

### Build Layer Caching

The pipeline uses Docker registry-based layer caching:

```yaml
cache-from: type=registry,ref=youruser/nextjs-prisma-boilerplate:buildcache
cache-to: type=registry,ref=youruser/nextjs-prisma-boilerplate:buildcache,mode=max
```

On first run, there is no cache — the full build takes 8-12 minutes. On subsequent runs where only application code changed (not `package.json` or `yarn.lock`), Docker reuses cached layers for dependency installation, cutting build time to 2-3 minutes.

### Migration Handling in the Pipeline

The deploy job runs `prisma migrate deploy` explicitly after the containers start:

```bash
docker exec npb-app-prod npx prisma migrate deploy
```

This is technically redundant because `Dockerfile.prod` already runs migrations via `CMD ["yarn", "cmd:start:prod"]` which expands to `prisma migrate deploy && prisma db seed && node dist/index.js`.

Running it explicitly in the pipeline is intentional for visibility — the migration step appears as a named action in the deployment log. In a future iteration, migrations will be removed from the container CMD and run exclusively as a pipeline step, giving full control over migration ordering relative to traffic.

### Verifying a Successful Deployment

After the pipeline completes:

1. Check the Actions tab — both jobs should show green checkmarks
2. Check the running containers on EC2:

```bash
docker ps
docker logs npb-app-prod --tail 20
```

3. Verify the application is live:

```bash
curl http://<ELASTIC_IP>
```

### On Secrets Management

GitHub Secrets is a production-grade solution for single-application deployments and is used by many real companies. It encrypts secrets at rest and only exposes them to pipeline runners.

The planned evolution as the system grows:

| Phase         | Secrets Approach                                                                  |
| ------------- | --------------------------------------------------------------------------------- |
| Phase 4 (now) | GitHub Secrets                                                                    |
| Phase 5       | Terraform provisions AWS Secrets Manager                                          |
| Phase 6       | Pipeline fetches secrets via IAM role — no long-lived credentials stored anywhere |

---

## 6. Phase 5 — Infrastructure as Code (Terraform)

### Goal

Replace all manual AWS console clicks with version-controlled code. If the server dies or you need a second environment, run one command and everything rebuilds in minutes.

### What Terraform Provisions

```
infra/terraform/
├── main.tf               # Provider config, Ubuntu 24.04 AMI data source
├── variables.tf          # All input variables with defaults
├── networking.tf         # VPC, subnet, internet gateway, route table
├── security.tf           # Security group (firewall rules)
├── compute.tf            # EC2 instance, Elastic IP, SSH key pair, user data
├── outputs.tf            # Outputs (IP, SSH command, app URL)
├── terraform.tfvars.example  # Template for your actual values
└── .gitignore            # Excludes state files and secrets
```

### Resources Created

| Resource                    | Purpose                                                      |
| --------------------------- | ------------------------------------------------------------ |
| VPC (10.0.0.0/16)           | Isolated network for all resources                           |
| Public subnet (10.0.1.0/24) | Holds the EC2 instance                                       |
| Internet Gateway            | Connects the VPC to the internet                             |
| Route Table                 | Routes all outbound traffic through the IGW                  |
| Security Group              | Firewall: SSH (your IP), HTTP/HTTPS (public), 3001 (your IP) |
| EC2 Instance (t3.small)     | Ubuntu 24.04, 20GB gp3 volume                                |
| Elastic IP                  | Static public IP that survives reboots                       |
| Key Pair                    | Registers your SSH public key                                |

### Prerequisites

```bash
# Install Terraform (macOS)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform -v

# Configure AWS CLI
aws configure
# Enter: Access Key ID, Secret Access Key, region: us-east-1, format: json

# Verify credentials
aws sts get-caller-identity
```

### Setup

```bash
cd infra/terraform

# Copy the example and fill in your values
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars

# Generate SSH public key from your .pem file
ssh-keygen -y -f ~/.ssh/npb-prod-key.pem > ~/.ssh/npb-prod-key.pub

# Get your current IP for SSH restriction
curl ifconfig.me
# Set allowed_ssh_cidr = "YOUR_IP/32" in terraform.tfvars
```

### Usage

```bash
# Initialise Terraform (downloads AWS provider)
terraform init

# Preview what will be created (nothing happens yet)
terraform plan

# Create all resources
terraform apply

# Outputs include:
# - elastic_ip
# - ssh_command
# - app_url
```

### User Data Bootstrap

The EC2 instance runs a bootstrap script on first boot that:

1. Updates the system
2. Installs Docker, Nginx, Git
3. Adds the `ubuntu` user to the Docker group
4. Enables Docker and Nginx on boot
5. Creates the required `proxy` Docker network
6. Clones the application repository
7. Configures Nginx as a reverse proxy

After boot, the only manual step is creating the env file with secrets. The CI/CD pipeline handles everything else.

### Destroying Infrastructure

```bash
# Remove all resources Terraform created
terraform destroy
```

This deletes the VPC, EC2, Elastic IP — everything. Use with caution.

### State Management

Terraform stores infrastructure state in `terraform.tfstate`. This file tracks what resources exist and is required for updates and destroys.

- **Local state (current):** State lives on your machine. If lost, Terraform loses track of resources.
- **Remote state (recommended for teams):** Store state in S3 with DynamoDB locking. Config is commented out in `main.tf` — uncomment after creating the S3 bucket.

---

## 7. Phase 6 — Observability (Prometheus, Grafana, Alerts)

### Goal

Move from "I think the app is working" to "I can prove the app is healthy and know immediately when it isn't." Add metrics, dashboards, latency tracking, and alert rules.

### Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  EC2 Server                                                     │
│                                                                 │
│  npb-app-prod ─── /api/metrics ──┐                             │
│                                   │ scrape every 15s            │
│                                   ▼                             │
│                            Prometheus ──── Alert Rules           │
│                                   │                             │
│                                   │ data source                 │
│                                   ▼                             │
│                              Grafana ──── Dashboards            │
│                                                                 │
│  Ports (127.0.0.1 only — not exposed to internet):             │
│  - Prometheus: localhost:9090                                    │
│  - Grafana: localhost:3002                                       │
└────────────────────────────────────────────────────────────────┘
```

### What Gets Measured

**Default Node.js metrics** (collected automatically by prom-client):

- `process_cpu_user_seconds_total` — CPU usage
- `nodejs_heap_size_used_bytes` — Memory usage
- `nodejs_eventloop_lag_seconds` — Event loop health
- `nodejs_gc_duration_seconds` — Garbage collection

**Custom application metrics** (added by our code):

- `http_requests_total` — Counter: total requests by method, route, status code
- `http_request_duration_seconds` — Histogram: response latency in seconds with percentile buckets

### How Metrics Instrumentation Works

Every API route is automatically instrumented via middleware in `lib-server/nc.ts`:

```typescript
const metricsMiddleware = (req, res, next) => {
  const startTime = Date.now();
  const method = req.method || 'GET';
  const route = req.url?.replace(/\/\d+/g, '/[id]').split('?')[0] || 'unknown';

  // Intercept res.end to capture the REAL status code after handler finishes
  const originalEnd = res.end.bind(res);
  res.end = (...args) => {
    const statusCode = String(res.statusCode || 200);
    const durationSeconds = (Date.now() - startTime) / 1000;

    httpRequestsTotal.inc({ method, route, status_code: statusCode });
    httpRequestDurationSeconds.observe(
      { method, route, status_code: statusCode },
      durationSeconds
    );

    return originalEnd(...args);
  };

  next();
};
```

Key design decisions:

- Intercepts `res.end` instead of recording at middleware entry — captures accurate status codes including errors
- Normalises dynamic route segments (`/api/posts/123` → `/api/posts/[id]`) — prevents cardinality explosion
- Wrapped in try/catch — metrics never break a request

### Alert Rules

Location: `observability/prometheus/rules/alerts.yml`

| Alert             | Condition                                        | Severity | Meaning                      |
| ----------------- | ------------------------------------------------ | -------- | ---------------------------- |
| `HighErrorRate`   | >5% of requests return 5xx over 5 minutes        | critical | Application is failing       |
| `HighLatency`     | p95 latency >2 seconds for 5 minutes             | warning  | Performance degradation      |
| `AppDown`         | Prometheus can't reach /api/metrics for 1 minute | critical | App crashed or network issue |
| `HighMemoryUsage` | Node.js heap >400MB for 5 minutes                | warning  | Possible memory leak         |

### Grafana Dashboard

A pre-built dashboard auto-loads at startup with 6 panels:

1. **Request Rate** — requests/second by route
2. **Error Rate** — percentage of 5xx responses
3. **p50/p95/p99 Latency** — response time percentiles
4. **Heap Memory** — used vs total heap in MB
5. **Requests by Status Code** — 200, 404, 500, etc.
6. **Event Loop Lag** — Node.js event loop health

### Accessing Observability in Production

Prometheus and Grafana are bound to `127.0.0.1` — not exposed to the internet. Access them via SSH tunnel:

```bash
# Grafana
ssh -i ~/.ssh/npb-prod-key.pem -L 3002:localhost:3002 ubuntu@<ELASTIC_IP> -N
# Open http://localhost:3002 — login: admin / admin

# Prometheus
ssh -i ~/.ssh/npb-prod-key.pem -L 9090:localhost:9090 ubuntu@<ELASTIC_IP> -N
# Open http://localhost:9090
```

### Useful PromQL Queries

```promql
# Total requests in the last hour
sum(increase(http_requests_total[1h]))

# Current request rate (req/sec)
sum(rate(http_requests_total[5m]))

# p95 latency
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Error rate as percentage
100 * sum(rate(http_requests_total{status_code=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# Slowest routes (p95 by route)
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, route))

# Heap memory in MB
nodejs_heap_size_used_bytes / 1024 / 1024

# Is the app up? (1 = yes, 0 = no)
up{job="nextjs-app"}
```

### Load Testing

Generate traffic to see metrics in action:

```bash
# Install a load testing tool (macOS)
brew install hey

# 200 requests, 10 concurrent to homepage
hey -n 200 -c 10 http://<ELASTIC_IP>/

# 100 requests to API
hey -n 100 -c 5 http://<ELASTIC_IP>/api/posts/

# Generate 404 errors
hey -n 50 -c 5 http://<ELASTIC_IP>/api/posts/99999/
```

### Simulating an Incident

Stop the app container and observe how metrics respond:

```bash
# On EC2 server
docker stop npb-app-prod

# In Prometheus, check:
up{job="nextjs-app"}   # shows 0

# AppDown alert fires after 1 minute
# Check: http://localhost:9090/alerts

# Restore
docker start npb-app-prod
```

### What Healthy Metrics Look Like

| Metric         | Healthy                          | Warning     | Critical |
| -------------- | -------------------------------- | ----------- | -------- |
| Request rate   | Stable, matches expected traffic | Sudden drop | Zero     |
| p95 latency    | < 500ms                          | 500ms - 2s  | > 2s     |
| Error rate     | < 1%                             | 1% - 5%     | > 5%     |
| Heap memory    | < 200MB                          | 200-400MB   | > 400MB  |
| Event loop lag | < 50ms                           | 50-200ms    | > 200ms  |
| `up` target    | 1                                | —           | 0        |

---

## 8. Phase 7 — Kubernetes (Minikube)

### Goal

Deploy the same application to Kubernetes, understanding pods, services, deployments, ingress, secrets, configmaps, persistent volumes, health probes, and autoscaling. Start locally with Minikube before moving to a managed cluster.

### Architecture

```
┌──────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                   │
│                                                       │
│  ┌─────────────┐    ┌─────────────────────────────┐  │
│  │   Ingress   │───▶│  Service: npb-app            │  │
│  │  (port 80)  │    │  (ClusterIP, port 3001)      │  │
│  └─────────────┘    └────────────┬────────────────┘  │
│                                  │                    │
│                     ┌────────────┼────────────┐      │
│                     ▼            ▼            ▼       │
│               ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│               │  Pod 1  │ │  Pod 2  │ │  Pod 3  │   │
│               │ npb-app │ │ npb-app │ │ npb-app │   │
│               └─────────┘ └─────────┘ └─────────┘   │
│                                                       │
│  ┌─────────────────────────────────────────────────┐  │
│  │  StatefulSet: npb-db (PostgreSQL)               │  │
│  │  Service: npb-db (ClusterIP, port 5432)         │  │
│  │  PersistentVolumeClaim: 2Gi                     │  │
│  └─────────────────────────────────────────────────┘  │
│                                                       │
│  ┌──────────────┐  ┌──────────────┐                  │
│  │  ConfigMap   │  │   Secret     │                  │
│  │ (env vars)   │  │ (DB creds)  │                  │
│  └──────────────┘  └──────────────┘                  │
│                                                       │
│  ┌──────────────────────────────────────────────────┐ │
│  │  HorizontalPodAutoscaler                         │ │
│  │  min: 2 pods, max: 5 pods, target: 70% CPU      │ │
│  └──────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

### Prerequisites

```bash
# Install Minikube (local K8s cluster)
brew install minikube

# Install kubectl (K8s CLI)
brew install kubectl

# Start Minikube with adequate resources
minikube start --driver=docker --memory=4096 --cpus=2

# Enable required addons
minikube addons enable ingress
minikube addons enable metrics-server

# Verify
kubectl cluster-info
kubectl get nodes
```

### Manifest Files

```
k8s/
├── 00-namespace.yml        # Isolates app from system resources
├── 01-secret.yml           # DB credentials, JWT secret (base64 encoded)
├── 02-configmap.yml        # Non-secret environment variables
├── 03-pvc-postgres.yml     # 2GB persistent disk for Postgres
├── 04-postgres.yml         # StatefulSet + Service for PostgreSQL
├── 05-app.yml              # Deployment (2 replicas) + Service for Next.js
├── 06-migration-job.yml    # One-time Job for Prisma migrations
├── 07-ingress.yml          # Routes external traffic to the app
└── 08-hpa.yml              # Auto-scales pods based on CPU
```

### Deploying Step by Step

```bash
# 1. Create the namespace
kubectl apply -f k8s/00-namespace.yml

# 2. Create secrets and config
kubectl apply -f k8s/01-secret.yml
kubectl apply -f k8s/02-configmap.yml

# 3. Create persistent storage
kubectl apply -f k8s/03-pvc-postgres.yml

# 4. Deploy PostgreSQL
kubectl apply -f k8s/04-postgres.yml
# Wait for it to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=database -n npb --timeout=120s

# 5. Run database migrations
kubectl apply -f k8s/06-migration-job.yml
kubectl wait --for=condition=complete job/npb-migrate -n npb --timeout=120s

# 6. Deploy the application
kubectl apply -f k8s/05-app.yml

# 7. Set up ingress
kubectl apply -f k8s/07-ingress.yml

# 8. Enable autoscaling
kubectl apply -f k8s/08-hpa.yml
```

### Accessing the App

```bash
# Get the Minikube IP
minikube ip

# Access the app
curl http://$(minikube ip)/

# Or open in browser
open http://$(minikube ip)/
```

### Key Kubernetes Concepts Used

| Concept                     | What it does                   | Why we need it                                 |
| --------------------------- | ------------------------------ | ---------------------------------------------- |
| **Namespace**               | Logical isolation              | Keeps our resources separate from system pods  |
| **Secret**                  | Stores sensitive data (base64) | DB passwords, JWT tokens — never in ConfigMap  |
| **ConfigMap**               | Non-secret key-value pairs     | App configuration that isn't sensitive         |
| **PersistentVolumeClaim**   | Requests disk storage          | Database data survives pod restarts            |
| **StatefulSet**             | Pod with stable identity       | Database needs consistent name and volume      |
| **Deployment**              | Manages replica pods           | App runs as 2+ copies for availability         |
| **Service (ClusterIP)**     | Internal DNS + load balancing  | Pods find each other by name                   |
| **Ingress**                 | External HTTP routing          | Maps port 80 to the app service                |
| **Job**                     | Run-once task                  | Database migrations run once, not in every pod |
| **HorizontalPodAutoscaler** | Auto-scales replicas           | Adds pods under load, removes when idle        |

### Health Probes

Every pod has two probes:

**Readiness probe** — "Is this pod ready to receive traffic?"

- Kubernetes only sends traffic to pods that pass readiness
- If a pod fails, it's removed from the service until it recovers

**Liveness probe** — "Is this pod alive?"

- If a pod fails liveness, Kubernetes kills and restarts it
- Catches zombie processes that are running but not responding

```yaml
# App: HTTP check on /api/metrics
readinessProbe:
  httpGet:
    path: /api/metrics
    port: 3001
  initialDelaySeconds: 10
  periodSeconds: 5

# Postgres: pg_isready command
readinessProbe:
  exec:
    command: ["pg_isready", "-U", "npb_user", "-d", "npb-k8s"]
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 5
```

### Autoscaling Behaviour

```yaml
minReplicas: 2 # Always at least 2 pods (availability)
maxReplicas: 5 # Never more than 5 (cost control)
targetCPUUtilization: 70% # Scale up when average CPU > 70%

scaleUp:
  stabilizationWindow: 30s # React quickly to load spikes
  maxPodsPerMinute: 2 # Add up to 2 pods per minute

scaleDown:
  stabilizationWindow: 300s # Wait 5 min before scaling down
  maxPodsPerMinute: 1 # Remove max 1 pod per minute
```

### Useful kubectl Commands

```bash
# See all resources in our namespace
kubectl get all -n npb

# Check pod status and events
kubectl describe pod <pod-name> -n npb

# View pod logs
kubectl logs <pod-name> -n npb
kubectl logs -f deployment/npb-app -n npb  # follow logs

# Execute a command inside a pod
kubectl exec -it <pod-name> -n npb -- sh

# Scale manually
kubectl scale deployment npb-app -n npb --replicas=3

# Check autoscaler status
kubectl get hpa -n npb

# Delete everything and start fresh
kubectl delete namespace npb
```

### Docker Compose vs Kubernetes — Translation

| Docker Compose            | Kubernetes Equivalent             |
| ------------------------- | --------------------------------- |
| `services:`               | Deployment + Service              |
| `volumes:`                | PersistentVolumeClaim             |
| `env_file:`               | ConfigMap + Secret                |
| `ports: "80:3001"`        | Service + Ingress                 |
| `depends_on:`             | InitContainers or readiness gates |
| `restart: unless-stopped` | Pod restartPolicy + Deployment    |
| `docker-compose up -d`    | `kubectl apply -f k8s/`           |
| `docker-compose down`     | `kubectl delete namespace npb`    |

### Troubleshooting: Postgres Liveness Probe Timeout

**Error:**

```
Liveness probe failed: command timed out: "pg_isready -U npb_user -d npb-k8s" timed out after 1s
```

**Cause:** Minikube has limited resources. Under memory/CPU pressure, Postgres can take more than 1 second to respond to `pg_isready`, causing the probe to time out and K8s to restart the pod.

**Fix:** Increase timeout and reduce probe frequency:

```yaml
livenessProbe:
  exec:
    command: ['pg_isready', '-U', 'npb_user', '-d', 'npb-k8s']
  initialDelaySeconds: 30 # Give Postgres time to start
  periodSeconds: 30 # Check less frequently
  timeoutSeconds: 5 # Allow 5 seconds to respond
  failureThreshold: 5 # 5 failures before restart (2.5 min tolerance)
```

This is a Minikube-specific issue. On a real cluster with proper resource allocation, the default 1-second timeout works fine.

---

## 9. Troubleshooting Reference

### `react-hook-form` engine incompatibility during Docker build

**Error:**

```
error react-hook-form@8.0.0-beta.2: The engine "node" is incompatible
```

**Cause:** `^8.0.0-alpha.4` in `package.json` allows yarn to upgrade to `beta.2`, which requires Node >=18. The Docker image runs Node 16.

**Fix:** Pin the exact version in `package.json`:

```json
"react-hook-form": "8.0.0-alpha.4"
```

---

### `yarn.lock` missing during Docker build

**Error:**

```
failed to compute cache key: "/yarn.lock": not found
```

**Cause:** `yarn.lock` was deleted and yarn was not available locally to regenerate it.

**Fix:** Restore from git history:

```bash
git checkout HEAD -- yarn.lock
```

---

### `prom-client` getMetricsAsJSON TypeScript error

**Error:**

```
Type error: Property 'length' does not exist on type 'Promise<MetricObjectWithValues...>'
```

**Cause:** `getMetricsAsJSON()` returns a Promise in prom-client v15, not a synchronous array.

**Fix:** Use `getSingleMetric()` as a synchronous guard instead:

```typescript
if (!register.getSingleMetric('process_cpu_user_seconds_total')) {
  client.collectDefaultMetrics({ register });
}
```

---

### Prisma `$on('query')` TypeScript error

**Error:**

```
Argument of type '"query"' is not assignable to parameter of type '"beforeExit"'
```

**Cause:** The global Prisma instance is typed as base `PrismaClient` without the event log config, so TypeScript only knows about `'beforeExit'`.

**Fix:** Use stdout logging instead of event-based logging:

```typescript
global.prisma = new PrismaClient({
  log: [
    { level: 'warn', emit: 'stdout' },
    { level: 'error', emit: 'stdout' },
  ],
});
```

---

### Next.js SWC binary fails on Ubuntu 24.04

**Error:**

```
warn - Attempted to load @next/swc-linux-x64-gnu, but an error occurred:
libssl.so.1.1: cannot open shared object file: No such file or directory
error - Failed to load SWC binary for linux/x64
```

**Cause:** Next.js 12's SWC binary was compiled against OpenSSL 1.1. Ubuntu 24.04 ships only OpenSSL 3 and has removed OpenSSL 1.1 entirely.

**Why it works locally (macOS):** The SWC binary for macOS is compiled differently and does not depend on the system OpenSSL.

**Fix:** Remove the `experimental` flags from `next.config.js` that force SWC usage. With `.babelrc` present, Next.js falls back to Babel which has no OpenSSL dependency:

```javascript
// Remove this entire block from next.config.js:
experimental: {
  runtime: 'nodejs',
  serverComponents: true,
  reactRoot: true,
},
```

**Why Docker avoids this entirely:** `Dockerfile.prod` uses `node:16.13.1-alpine` which includes OpenSSL 1.1. The build runs inside the container, not on the Ubuntu host. This is the primary reason Docker is preferred over bare-metal deployment for this application.

---

### `NEXTAUTH_URL` is empty during Docker build

**Error:**

```
TypeError [ERR_INVALID_URL]: Invalid URL
input: ''
```

**Cause:** `docker-compose.prod.yml` passes `NEXTAUTH_URL` as a build argument:

```yaml
build:
  args:
    - ARG_NEXTAUTH_URL=$NEXTAUTH_URL
```

Build args are resolved from the **host shell environment**, not from `env_file`. The `env_file` directive only applies to the running container, not the build stage.

**Fix:** Export the variable into the shell before building:

```bash
export NEXTAUTH_URL=http://<ELASTIC_IP>
export DATABASE_URL=postgresql://...
docker compose -f docker-compose.prod.yml build
```

In CI/CD (Phase 4), the pipeline exports these from GitHub Secrets automatically, so this step is only needed for manual builds.

---

### `PORT:3001` instead of `PORT=3001` in env file

**Error:** `NEXTAUTH_URL` evaluates to empty string.

**Cause:** Typo in `.env` file — colon used instead of equals sign.

**Fix:**

```bash
# Wrong
PORT:3001

# Correct
PORT=3001
```

---

### `network proxy declared as external, but could not be found`

**Error:**

```
network proxy declared as external, but could not be found
```

**Cause:** `docker-compose.prod.yml` references a pre-existing external Docker network named `proxy` which does not exist on a fresh server.

**Fix:** Create it once before running:

```bash
docker network create proxy
```

---

### Duplicate identifier `NextApiRequestWithResult` in nc.ts

**Error:**

```
Type error: Duplicate identifier 'NextApiRequestWithResult'.
```

**Cause:** The `ssrNcHandler` block and its type export were accidentally duplicated in `lib-server/nc.ts`, resulting in two identical type declarations.

**Fix:** Remove the duplicate block. The file should only contain one `export type NextApiRequestWithResult<T>` and one `export const ssrNcHandler`.

---

### Kubernetes: Postgres liveness probe timeout in Minikube

**Error:**

```
Liveness probe failed: command timed out: "pg_isready -U npb_user -d npb-k8s" timed out after 1s
```

**Cause:** Minikube runs with limited CPU and memory. Under resource pressure, Postgres responds slower than the default 1-second timeout.

**Fix:** Increase `timeoutSeconds` and `periodSeconds`, add `failureThreshold`:

```yaml
livenessProbe:
  exec:
    command: ['pg_isready', '-U', 'npb_user', '-d', 'npb-k8s']
  initialDelaySeconds: 30
  periodSeconds: 30
  timeoutSeconds: 5
  failureThreshold: 5
```

This is a local resource constraint — not an issue on production clusters with dedicated resource allocation.

---

## 10. Architecture Summary

### Request Flow (Production)

```
Browser request
    │
    ▼
Nginx (port 80)
    │  proxy_pass http://localhost:3001
    ▼
Express server (port 3001)
    │  next.js request handler
    ▼
Next.js page or API route
    │  Prisma ORM
    ▼
PostgreSQL container (npb-db-prod)
```

### Environment Variable Flow

```
envs/production-docker/.env.production.docker        (versioned, non-secret defaults)
envs/production-docker/.env.production.docker.local  (not versioned, secrets + overrides)
    │
    ├── runtime vars → injected into running container via env_file
    │
    └── build vars (DATABASE_URL, NEXTAUTH_URL)
            → must be exported to host shell before docker compose build
            → passed as ARG into Dockerfile.prod at build time
```

### Docker Image Build (Dockerfile.prod)

Three-stage multi-stage build:

| Stage          | Base                  | Purpose                                                              |
| -------------- | --------------------- | -------------------------------------------------------------------- |
| `dependencies` | `node:16.13.1-alpine` | Install prod + dev deps, generate Prisma client                      |
| `builder`      | `node:16.13.1-alpine` | Copy source, run `yarn build`, compile TypeScript server             |
| `production`   | `node:16.13.1-alpine` | Copy only built artifacts and prod node_modules, minimal final image |

The Alpine base image includes OpenSSL 1.1, which is required by Next.js 12's SWC compiler. This is why the Docker build works on Ubuntu 24.04 even though a bare-metal build on the same server fails.
