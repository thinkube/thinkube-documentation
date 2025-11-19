# Gitea

This component deploys [Gitea](https://about.gitea.com/) - a lightweight self-hosted Git service for the Thinkube GitOps workflow.

## Overview

Gitea provides Git repository hosting with critical functionality for multi-domain deployments:

- **GitOps Repository Hosting**: Hosts processed Kubernetes manifests for ArgoCD deployment
- **Template Processing**: Bridges the gap between GitHub templates and domain-specific manifests
- **Keycloak SSO**: OAuth2/OIDC authentication with automatic admin group mapping
- **Automated Setup**: Unattended installation with admin user and OAuth configuration
- **CI/CD Integration**: Webhook support for Argo Events workflow triggers
- **PostgreSQL Backend**: Shared database for repository metadata
- **SSH Access**: Built-in SSH server on port 2222 for git operations
- **API Access**: Automated API token generation for programmatic access

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster
- ingress (deployment order #13) - For web UI and SSH access
- acme-certificates (deployment order #12) - For TLS certificates
- postgresql (deployment order #14) - For database backend
- keycloak (deployment order #15) - For SSO authentication

**Deployment order**: #26

## Prerequisites

**Required inventory variables** (example values shown):

```yaml
# Gitea configuration
gitea_namespace: gitea
gitea_hostname: git.example.com  # Replace with your domain
gitea_version: 1.23.8
gitea_storage_size: 10Gi
gitea_storage_class: k8s-hostpath

# Database configuration
gitea_db_name: gitea
postgres_namespace: postgresql

# Resource limits
gitea_memory_limit: 512Mi
gitea_memory_request: 256Mi
gitea_cpu_limit: 1000m
gitea_cpu_request: 100m

# Admin configuration
admin_username: admin
auth_realm_username: tkadmin

# Keycloak configuration (inherited)
keycloak_url: https://keycloak.example.com  # Replace with your domain
keycloak_realm: thinkube

# Kubernetes configuration (inherited)
domain_name: example.com  # Replace with your domain
kubeconfig: /var/snap/k8s/common/etc/admin.conf
kubectl_bin: /snap/k8s/current/bin/kubectl
system_username: ubuntu
```

**Required environment variables**:
- `ADMIN_PASSWORD`: Admin password for Keycloak, PostgreSQL, and Gitea admin user

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all Gitea deployment playbooks in sequence:
- Imports 10_deploy.yaml - Deploys Gitea server
- Imports 15_configure.yaml - Configures organizations and ArgoCD integration
- Imports 16_configure_ssh_keys.yaml - Sets up SSH keys for repository access
- Imports 17_configure_discovery.yaml - Configures service discovery

### 10_deploy.yaml
Main deployment playbook for Gitea Git service:

- **Namespace and Secrets**:
  - Creates `gitea` namespace
  - Creates `gitea-db-secret` with database credentials
  - Copies wildcard TLS certificate from default namespace as `gitea-tls-secret`

- **Database Setup**:
  - Creates PostgreSQL database initialization Job in postgres namespace
  - Database name: gitea
  - Owner: admin user
  - Runs psql command to create database if not exists
  - Waits for Job completion (30 retries, 10 second delay)

- **Keycloak Integration**:
  - Creates Keycloak OAuth2 client via keycloak/keycloak_client role:
    - Client ID: gitea
    - Root URL: `https://git.example.com`
    - Redirect URIs: `https://git.example.com/*`
    - Standard flow enabled, direct access disabled
    - Group membership protocol mapper for RBAC
  - Creates `thinkube-admins` group in Keycloak
  - Adds auth_realm_username user to thinkube-admins group
  - Creates `gitea-oauth-secret` Kubernetes secret with client credentials

- **Gitea Deployment**:
  - Image: gitea/gitea:1.23.8
  - Init containers:
    - `init-directories`: Creates /data/git/.ssh and /data/gitea directories with proper permissions (1000:1000)
    - `init-config`: Creates app.ini with INSTALL_LOCK=true to prevent setup screen
  - Ports: 3000 (HTTP), 2222 (SSH)
  - Environment variables for configuration:
    - Server: Domain, ROOT_URL, SSH settings
    - Database: PostgreSQL connection via gitea-db-secret
    - Service: Disable registration, require signin, allow only external registration
    - Admin: Username and password from environment
    - OAuth2: Enabled with Keycloak configuration
    - Webhook: Allowed host list `*.example.com`, 30 second timeout
    - Git timeouts: Default 360s, Migrate 600s, Mirror/Clone/Pull 300s
  - Resource requests: 100m CPU, 256Mi memory
  - Resource limits: 1000m CPU, 512Mi memory
  - Liveness probe: HTTP GET / on port 3000, 200s initial delay
  - Readiness probe: HTTP GET / on port 3000, 5s initial delay

- **Storage**:
  - Creates `gitea-pvc` PersistentVolumeClaim (10Gi, ReadWriteOnce, k8s-hostpath)
  - Mounted at /data for repository storage

- **Service**:
  - ClusterIP service exposing:
    - HTTP: port 3000 → targetPort 3000
    - SSH: port 22 → targetPort 2222

- **Ingress**:
  - Host: `git.example.com`
  - TLS enabled with wildcard certificate
  - Annotations:
    - Proxy body size: unlimited (0)
    - Proxy read timeout: 600s
    - Proxy send timeout: 600s
  - Routes to gitea service port 3000

- **Initialization**:
  - Waits for deployment to be ready (60 retries, 10 second delay)
  - Waits for HTTPS accessibility at /user/login endpoint
  - Creates admin user via kubectl exec if not exists
  - Configures OAuth2 provider with Keycloak:
    - Provider: openidConnect
    - Auto-discover URL: Keycloak well-known endpoint
    - Group claim: groups
    - Admin group: thinkube-admins
    - Group-team mapping: thinkube-admins → thinkube-deployments Owners
  - Generates admin API token via `gitea admin user generate-access-token`
  - Stores token in `gitea-admin-token` Kubernetes secret
  - Creates `thinkube-deployments` organization via Gitea API

### 15_configure.yaml
Organization configuration and ArgoCD integration:

- **API Token Retrieval**:
  - Checks for existing `gitea-admin-token` secret in gitea namespace
  - Uses automated token if available
  - Falls back to generating token via basic auth API call to `/users/{username}/tokens`
  - Stores generated token in gitea-admin-token secret if created during this playbook

- **Organization Setup**:
  - Waits for Gitea to be fully ready (30 retries, 10 second delay)
  - Checks if `thinkube-deployments` organization exists via API
  - Creates organization if not exists:
    - Username: thinkube-deployments
    - Full name: "Thinkube Deployments"
    - Visibility: private
    - Allows repo admins to change team access

- **Webhook Configuration**:
  - Creates `gitea-webhook-config` ConfigMap in gitea namespace with:
    - argocd_webhook_url: `https://argocd.example.com/api/webhook`
    - default_webhook_secret: Random 32-character secret

- **ArgoCD Integration**:
  - Checks if argocd namespace exists
  - If ArgoCD is installed:
    - Creates `gitea-repo-creds` secret in argocd namespace with label `argocd.argoproj.io/secret-type: repo-creds`
    - Contains: URL, type (git), username, password (API token)
    - Restarts argocd-repo-server deployment to pick up credentials
    - Waits for repo server to be ready (12 retries, 10 second delay)

### 16_configure_ssh_keys.yaml
SSH key configuration for Gitea repository access:

- **SSH Key Generation**:
  - Creates `~/shared-code/.ssh/gitea` directory structure
  - Generates Ed25519 SSH key pair if not exists:
    - Private key: `~/shared-code/.ssh/gitea/id_ed25519`
    - Public key: `~/shared-code/.ssh/gitea/id_ed25519.pub`
    - Comment: `gitea@example.com`
  - Sets proper ownership (system_username) and permissions (0600)

- **Gitea SSH Key Registration**:
  - Retrieves gitea-admin-token from Kubernetes secret
  - Adds SSH public key to Gitea admin user via API:
    - Title: "Thinkube CI/CD Key"
    - Read-only: false
    - Status code 201 (created) or 422 (already exists)

- **SSH Configuration**:
  - Creates SSH config file at `~/shared-code/.ssh/gitea/config`:
    - Host: git.example.com
    - User: git
    - Port: 2222
    - IdentityFile: ~/.ssh/gitea/id_ed25519
    - StrictHostKeyChecking: accept-new
  - Includes gitea config in main SSH config via `Include gitea/config`

- **Kubernetes Secret**:
  - Creates `gitea-ssh-key` secret in argo namespace
  - Contains both private and public keys for Argo Workflows access

### 17_configure_discovery.yaml
Service discovery configuration:

- **Service Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in gitea namespace
  - Labels: `thinkube.io/managed`, `thinkube.io/service-type: core`, `thinkube.io/service-name: gitea`
  - Defines service metadata:
    - Display name: "Gitea"
    - Description: "Git repository management"
    - Category: development
    - Icon: /icons/tk_code.svg
  - Endpoint configuration:
    - Web UI: `https://git.example.com/user/oauth2/Keycloak` (Keycloak login URL)
    - Health check: `https://git.example.com/api/healthz`
  - Scaling configuration: Deployment gitea, minimum 1 replica
  - Environment variables: GITEA_URL, GITEA_TOKEN (from gitea-admin-token secret)

## Deployment

Gitea is automatically deployed by the Thinkube installer at deployment order #26. The installer executes the orchestrator playbook (00_install.yaml) which runs all required playbooks in sequence.

No manual intervention is required during installation.

## Access Points

- **Web UI**: https://git.example.com (Keycloak SSO authentication)
- **SSH**: git@git.example.com:2222 (SSH key authentication)

Replace `example.com` with your actual domain.

## GitOps Workflow

Gitea enables a clean separation between reusable templates (GitHub) and domain-specific deployments (Gitea):

```
GitHub (templates) → Process → Gitea (manifests) → ArgoCD
     ↑                              ↓
     └──── Contribute back ─────────┘
           (templates only)
```

### Development Cycle

1. **Deploy Application**:
   - Playbook clones template repository from GitHub
   - Processes Jinja templates with domain-specific values
   - Pushes processed manifests to Gitea
   - Installs git hooks for automatic template processing

2. **Develop in Gitea**:
   - Edit `.jinja` template files (not processed `.yaml` files)
   - Commit changes (pre-commit hook auto-processes templates)
   - Push to Gitea
   - ArgoCD detects changes and deploys

3. **Contribute to GitHub**:
   - Run `./prepare-for-github.sh` to remove processed files
   - Push branch to GitHub
   - Only template files are shared upstream

### Auto-Generated File Headers

Processed files include warnings to prevent direct editing:

```yaml
# AUTO-GENERATED FILE - DO NOT EDIT DIRECTLY
# This file is automatically generated from k8s/deployment.yaml.jinja
# Any changes made directly to this file will be lost on next commit
# To make changes, edit the template file and commit
# Generated for domain: example.com
```

## Configuration

### API Access

The admin API token is automatically generated and stored:

```bash
# Retrieve token from Kubernetes secret
kubectl get secret -n gitea gitea-admin-token -o jsonpath='{.data.token}' | base64 -d

# Use in API calls
GITEA_TOKEN=$(kubectl get secret -n gitea gitea-admin-token -o jsonpath='{.data.token}' | base64 -d)
curl -H "Authorization: token $GITEA_TOKEN" https://git.example.com/api/v1/user  # Replace with your domain
```

### SSH Access

SSH keys are configured for automated git operations:

```bash
# Clone repository via SSH
git clone git@git.example.com:thinkube-deployments/my-app-deployment.git  # Replace with your domain

# The SSH config is automatically set up:
# Host: git.example.com
# Port: 2222
# IdentityFile: ~/.ssh/gitea/id_ed25519
```

### OAuth2 Configuration

Users in the `thinkube-admins` Keycloak group automatically receive:
- Admin permissions in Gitea
- Owner role in `thinkube-deployments` organization
- Automatic account linking on first login

### Repository Structure

Deployment repositories created in Gitea follow this structure:

```
my-app-deployment/
├── k8s/                        # Processed Kubernetes manifests
│   ├── deployment.yaml         # (auto-generated from .jinja)
│   ├── service.yaml
│   └── ingress.yaml
├── templates/                  # Original Jinja templates
│   ├── deployment.yaml.jinja
│   ├── service.yaml.jinja
│   └── ingress.yaml.jinja
├── .git-hooks/                 # Auto-processing hooks
│   └── pre-commit
├── reprocess-templates.sh      # Manual template processing
├── prepare-for-github.sh       # Clean for upstream contribution
├── install-hooks.sh            # Reinstall git hooks
├── DEPLOYMENT_INFO.yaml        # Deployment metadata
└── DEVELOPMENT.md              # Workflow documentation
```

### Webhook Integration

When Argo Events is deployed, webhooks are automatically configured for repositories created via the `git_push` role:

1. Git push to Gitea repository
2. Gitea sends webhook to `https://argo-events.example.com/gitea`
3. Argo Events EventSource receives webhook
4. Sensor triggers Argo Workflow with repository parameters:
   - repo-name: Repository name
   - repo-url: Clone URL
   - commit-sha: Commit hash
   - branch: Branch reference

## Troubleshooting

### Check Gitea pods
```bash
kubectl get pods -n gitea
kubectl logs -n gitea deploy/gitea
```

### Verify database connection
```bash
# Check database exists
kubectl exec -n postgresql deploy/postgresql-official -- psql -U admin -d mydatabase -c "\l gitea"

# Test Gitea database connection
kubectl exec -n gitea deploy/gitea -- su git -c "gitea admin user list"
```

### Verify OAuth2 configuration
```bash
# List OAuth authentication sources
kubectl exec -n gitea deploy/gitea -- su git -c "gitea admin auth list"

# Should show Keycloak provider with thinkube-admins admin group
```

### Check admin API token
```bash
# Verify secret exists
kubectl get secret -n gitea gitea-admin-token

# Test token
GITEA_TOKEN=$(kubectl get secret -n gitea gitea-admin-token -o jsonpath='{.data.token}' | base64 -d)
curl -H "Authorization: token $GITEA_TOKEN" https://git.example.com/api/v1/user  # Replace with your domain
```

### Verify SSH access
```bash
# Test SSH connection
ssh -p 2222 git@git.example.com  # Replace with your domain
# Should respond with: Hi there, You've successfully authenticated...

# Check SSH key registration
GITEA_TOKEN=$(kubectl get secret -n gitea gitea-admin-token -o jsonpath='{.data.token}' | base64 -d)
curl -H "Authorization: token $GITEA_TOKEN" https://git.example.com/api/v1/user/keys  # Replace with your domain
```

### Verify ArgoCD integration
```bash
# Check ArgoCD repository credentials
kubectl get secret -n argocd gitea-repo-creds -o yaml

# Test ArgoCD can access Gitea
kubectl logs -n argocd deploy/argocd-repo-server | grep gitea
```

### Template processing issues
```bash
# Verify git hooks are installed
cd /path/to/deployment-repo
ls -la .git/hooks/pre-commit

# Manually process templates
./reprocess-templates.sh

# Reinstall hooks if needed
./install-hooks.sh
```

### Webhook issues
```bash
# Verify Argo Events webhook endpoint
curl -I https://argo-events.example.com/gitea  # Replace with your domain

# List repository webhooks via API
GITEA_TOKEN=$(kubectl get secret -n gitea gitea-admin-token -o jsonpath='{.data.token}' | base64 -d)
curl -H "Authorization: token $GITEA_TOKEN" \
  https://git.example.com/api/v1/repos/thinkube-deployments/my-app/hooks  # Replace with your domain
```

## References

- [Gitea Documentation](https://docs.gitea.com/)
- [Gitea API Reference](https://docs.gitea.com/api/1.23/)
- [OAuth2 Provider Configuration](https://docs.gitea.com/usage/authentication)
