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
5. [Observability — Prometheus and Grafana](#5-observability--prometheus-and-grafana)
6. [Troubleshooting Reference](#6-troubleshooting-reference)
7. [Architecture Summary](#7-architecture-summary)

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

## 5. Observability — Prometheus and Grafana

Prometheus and Grafana are included in `docker-compose.dev.yml` for local development observability. They are not currently part of the production `docker-compose.prod.yml`.

| Service          | URL                                 | Purpose                      |
| ---------------- | ----------------------------------- | ---------------------------- |
| Prometheus       | `http://localhost:9090`             | Metrics storage and querying |
| Grafana          | `http://localhost:3002`             | Dashboards and visualisation |
| Metrics endpoint | `http://localhost:3001/api/metrics` | Raw Prometheus metrics       |

Default metrics exposed include Node.js process CPU, memory, event loop lag, and the custom `http_requests_total` counter.

---

## 6. Troubleshooting Reference

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

## 7. Architecture Summary

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
