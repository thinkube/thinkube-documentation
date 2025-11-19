# DevPI

This component deploys [DevPI](https://devpi.net/) - a private Python package index server for hosting internal packages and caching PyPI packages.

## Overview

DevPI provides a private Python package repository for the Thinkube platform with:

- **Private Package Hosting**: Host internal Python packages for your organization
- **PyPI Caching**: Cache packages from PyPI for faster installation and offline access
- **Web UI**: Browse packages and indices via Keycloak-authenticated web interface
- **Unauthenticated API**: Direct pip/CLI access without authentication for package installation
- **Dual Ingress Configuration**: Separate endpoints for web UI (protected) and API (open)
- **Fish Shell Integration**: Helper functions for developers to manage packages
- **OAuth2 Session Management**: Redis-backed session storage for authenticated web access

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster
- ingress (deployment order #13) - For web UI and API access
- acme-certificates (deployment order #12) - For TLS certificates
- keycloak (deployment order #15) - For SSO authentication on web UI
- harbor (deployment order #16) - For container image storage

**Deployment order**: #25

## Prerequisites

**Required inventory variables** (example values shown):

```yaml
# DevPI configuration
devpi_namespace: devpi
devpi_dashboard_hostname: devpi.example.com  # Replace with your domain
devpi_api_hostname: devpi-api.example.com  # Replace with your domain
devpi_index_name: stable

# OAuth2 proxy settings
oauth2_proxy_client_id: oauth2-proxy-devpi
oauth2_proxy_enabled: true

# Harbor configuration (inherited)
harbor_registry: harbor.example.com  # Replace with your domain
harbor_project: library

# Keycloak configuration (inherited)
keycloak_url: https://keycloak.example.com  # Replace with your domain
keycloak_realm: thinkube
admin_username: admin

# Kubernetes configuration (inherited)
domain_name: example.com  # Replace with your domain
kubeconfig: /var/snap/k8s/common/etc/admin.conf
kubectl_bin: /snap/k8s/current/bin/kubectl
helm_bin: /snap/k8s/current/bin/helm
```

**Required environment variables**:
- `ADMIN_PASSWORD`: Admin password for Keycloak, Harbor, and DevPI root user

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all DevPI deployment playbooks in sequence:
- Imports 10_deploy.yaml - Deploys DevPI server
- Imports 15_configure_cli.yaml - Installs CLI and fish shell integration
- Imports 17_configure_discovery.yaml - Configures service discovery

### 10_deploy.yaml
Main deployment playbook for DevPI server:

- **Namespace Setup**:
  - Creates `devpi` namespace
  - Copies wildcard TLS certificate from default namespace
  - Copies Harbor pull secret for container image access

- **Container Build and Push**:
  - Clones https://github.com/thinkube/thinkube-devpi.git repository
  - Builds DevPI container image with Podman from dockerfile/Dockerfile
  - Tags image as `harbor.example.com/library/devpi:latest`
  - Pushes to Harbor registry (insecure mode for internal registry)

- **Storage Configuration**:
  - Creates `devpi-data-pvc` PersistentVolumeClaim (5Gi, ReadWriteOnce)
  - Mounts to /data for package storage

- **Redis Session Storage**:
  - Deploys ephemeral Valkey (Redis-compatible) instance via valkey/ephemeral_valkey role
  - Service name: ephemeral-redis
  - Used by OAuth2 Proxy for session management

- **OAuth2 Proxy Deployment**:
  - Deploys OAuth2 Proxy via oauth2_proxy role for Keycloak authentication
  - Provider: keycloak-oidc
  - Client ID: oauth2-proxy-devpi
  - Redirect URL: `https://devpi.example.com/oauth2/callback`
  - Session store: Redis (ephemeral-redis service)
  - Cookie domain: example.com

- **DevPI Deployment** (two-stage process):
  - Stage 1: Deploys DevPI without `--outside-url` configuration
  - Waits for deployment and pod to be ready
  - Runs initialization Job (devpi-init) to set root password and create root/stable index
  - Stage 2: Redeploys with `--outside-url` enabled for proper external access
  - Uses deployment template from templates/deployment.yaml.j2

- **Service Configuration**:
  - Creates DevPI Service on port 3141 (TCP)
  - Creates nginx-headers ConfigMap with proxy headers:
    - X-Real-IP, X-Forwarded-For, X-Forwarded-Proto, X-Forwarded-Host, X-Outside-URL

- **Dual Ingress Configuration**:
  - **Dashboard Ingress** (`devpi-http-ingress`):
    - Host: `devpi.example.com`
    - TLS enabled with wildcard certificate
    - OAuth2 authentication annotations (secured by OAuth2 Proxy)
    - Proxy body size: 50m
    - Custom headers from nginx-headers ConfigMap
    - Routes to devpi service port 3141
  - **API Ingress** (`devpi-api-ingress`):
    - Host: `devpi-api.example.com`
    - TLS enabled with wildcard certificate
    - No authentication (direct pip/CLI access)
    - Proxy body size: 50m
    - Custom headers from nginx-headers ConfigMap
    - Routes to devpi service port 3141

- **Initialization Job**:
  - Waits for DevPI server to be ready (HTTP health check)
  - Uses internal service URL (no OAuth2)
  - Logs in with empty password (default for new DevPI)
  - Sets root password to ADMIN_PASSWORD
  - Creates root/stable index with bases=root/pypi
  - TTL: 300 seconds after completion

### 15_configure_cli.yaml
CLI installation and fish shell integration:

- **DevPI Client Installation**:
  - Installs python3-pip package
  - Installs devpi-client via pip to system Python

- **Fish Shell Configuration**:
  - Creates fish config directory: `~/.config/fish/conf.d`
  - Creates devpi.fish configuration with:
    - DEVPI_URL environment variable: `https://devpi-api.example.com`
    - `devpi-env` function: Display current DevPI configuration
    - `devpi-init-admin` function: Initialize admin user and create index
    - `devpi-upload-pkg` function: Upload package with validation
    - Creates default `~/.devpi.ini` configuration file

- **Scripts Directory**:
  - Creates `~/devpi-scripts` directory
  - Generates devpi-init-admin.sh bash script from template

- **Pip Configuration**:
  - Creates `~/.pip` directory
  - Creates pip.conf with:
    - index-url: `https://devpi-api.example.com/root/stable/+simple/`
    - trusted-host: devpi-api.example.com

### 17_configure_discovery.yaml
Service discovery configuration:

- **Service Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in devpi namespace
  - Labels: `thinkube.io/managed`, `thinkube.io/service-type: core`, `thinkube.io/service-name: devpi`
  - Defines service metadata:
    - Display name: "DevPI"
    - Description: "Private Python package repository"
    - Category: development
    - Icon: /icons/tk_artifact.svg
  - Endpoint configuration:
    - Web UI: https://devpi.example.com (primary)
    - API: https://devpi-api.example.com (no auth)
  - Scaling configuration: Deployment devpi, minimum 1 replica
  - Environment variables: DEVPI_URL, DEVPI_INDEX, DEVPI_USERNAME, DEVPI_PASSWORD

- **Code-Server Integration**:
  - Updates code-server environment variables via code_server_env_update role

## Deployment

DevPI is automatically deployed by the Thinkube installer at deployment order #25. The installer executes the orchestrator playbook (00_install.yaml) which runs all required playbooks in sequence.

No manual intervention is required during installation.

## Access Points

- **Web UI**: https://devpi.example.com (Keycloak SSO authentication)
- **API Endpoint**: https://devpi-api.example.com (No authentication - for pip/CLI)

Replace `example.com` with your actual domain.

## Configuration

### CLI Authentication

The DevPI CLI is installed via pip and configured for API access:

```bash
# Display DevPI configuration
devpi-env

# Use DevPI server (fish shell)
devpi use https://devpi-api.example.com

# Login
devpi login root --password=$ADMIN_PASSWORD

# Create index
devpi index -c myindex bases=root/pypi

# Upload package
devpi upload path/to/package.whl

# Or use fish helper function
devpi-upload-pkg path/to/package.whl
```

### Pip Configuration

Pip is automatically configured to use DevPI as the default index during CLI setup:

```bash
# Configuration already applied by 15_configure_cli.yaml
# Verify with:
pip config get global.index-url
# Should show: https://devpi-api.example.com/root/stable/+simple/

# Install package from DevPI
pip install package-name

# Install with explicit index
pip install --index-url https://devpi-api.example.com/root/stable/+simple/ package-name
```

### Fish Shell Functions

Available functions after running 15_configure_cli.yaml:

```bash
# Display DevPI environment
devpi-env

# Initialize admin user and create index
devpi-init-admin

# Upload package with validation
devpi-upload-pkg path/to/package.whl
```

### Creating Indices

```bash
# Login as root
devpi login root --password=$ADMIN_PASSWORD

# Create new index
devpi index -c myuser/myindex bases=root/pypi

# Use index
devpi use myuser/myindex

# Upload to index
devpi upload
```

## Troubleshooting

### Check DevPI pods
```bash
kubectl get pods -n devpi
kubectl logs -n devpi deploy/devpi
kubectl logs -n devpi deploy/oauth2-proxy
```

### Verify ingress configuration
```bash
# Check both ingresses
kubectl get ingress -n devpi

# Verify dashboard ingress (OAuth2 protected)
kubectl get ingress -n devpi devpi-http-ingress -o yaml

# Verify API ingress (no auth)
kubectl get ingress -n devpi devpi-api-ingress -o yaml
```

### Test API connectivity
```bash
# Should return DevPI version info
curl https://devpi-api.example.com/+api  # Replace with your domain

# Test package index
curl https://devpi-api.example.com/root/stable/+simple/  # Replace with your domain
```

### Verify initialization
```bash
# Check initialization job
kubectl get job -n devpi devpi-init
kubectl logs -n devpi job/devpi-init

# Verify root index exists
curl https://devpi-api.example.com/root/stable  # Replace with your domain
```

### Reset root password
```bash
# Get DevPI pod name
kubectl get pods -n devpi -l app=devpi

# Exec into pod
kubectl exec -n devpi -it <devpi-pod-name> -- bash

# Reset password
devpi-server --passwd root
```

### Check OAuth2 Proxy
```bash
# Verify OAuth2 Proxy is running
kubectl get pods -n devpi -l app=oauth2-proxy

# Check OAuth2 logs
kubectl logs -n devpi deploy/oauth2-proxy

# Test OAuth2 callback
curl -I https://devpi.example.com/oauth2/callback  # Replace with your domain
```

## References

- [DevPI Documentation](https://devpi.net/)
- [DevPI Quickstart](https://devpi.net/docs/devpi/devpi/stable/+doc/quickstart-pypimirror.html)
- [DevPI Client Documentation](https://devpi.net/docs/devpi/devpi/stable/+doc/userman/devpi_commands.html)
