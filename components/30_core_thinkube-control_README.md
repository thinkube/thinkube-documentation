# Thinkube Control

This component deploys [Thinkube Control](https://github.com/thinkube/thinkube-control) - the central management interface for the Thinkube platform with web UI, API, and MCP server capabilities.

## Overview

Thinkube Control provides a unified management interface for the entire platform:

- **Web Dashboard**: Vue.js application with DaisyUI components for platform monitoring
- **FastAPI Backend**: RESTful API with Keycloak authentication and CI/CD pipeline monitoring
- **GitOps Workflow**: GitHub templates → Jinja processing → Gitea manifests → ArgoCD deployment
- **Webhook Infrastructure**: Automated sync and GitOps updates for instant deployments
- **MCP Integration**: Model Context Protocol server for LLM-based template deployment
- **CI/CD Monitoring**: Real-time pipeline tracking across Argo Workflows, Harbor, and ArgoCD
- **Template Deployment**: Deploy applications from GitHub templates with domain-specific variables
- **Package Version Service**: MCP server for checking package versions in Python, npm, and GitHub

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster
- ingress (deployment order #13) - For web UI access
- acme-certificates (deployment order #12) - For TLS certificates
- postgresql (deployment order #14) - For database backend
- keycloak (deployment order #15) - For SSO authentication
- harbor (deployment order #16) - For container images
- seaweedfs (deployment order #21) - For S3-compatible storage
- argo-workflows (deployment order #23) - For CI/CD builds
- argocd (deployment order #24) - For GitOps deployment
- gitea (deployment order #26) - For hosting processed manifests
- mlflow (deployment order #28) - For model registry (OAuth secret needed)
- jupyterhub (deployment order #29) - For shared models PVC

**Deployment order**: #30

## Prerequisites

**Required inventory variables** (example values shown):

```yaml
# Thinkube Control configuration
thinkube_control_namespace: thinkube-control
thinkube_control_hostname: control.example.com  # Replace with your domain
thinkube_control_db_name: thinkube_control
thinkube_control_cicd_db_name: cicd_monitoring

# GitHub configuration
github_org: thinkube  # GitHub organization for templates
github_repo_name: thinkube-control

# Keycloak configuration (inherited)
keycloak_url: https://keycloak.example.com  # Replace with your domain
keycloak_realm: thinkube
admin_username: admin
auth_realm_username: tkadmin

# Harbor configuration (inherited)
harbor_registry: harbor.example.com  # Replace with your domain
harbor_project: thinkube
harbor_robot_name: thinkube-deployer

# PostgreSQL configuration (inherited)
postgres_namespace: postgres
postgres_release_name: postgresql-official

# ArgoCD configuration (inherited)
argocd_namespace: argocd
argocd_hostname: argocd.example.com  # Replace with your domain

# Argo Workflows configuration (inherited)
argo_workflows_namespace: argo

# Gitea configuration (inherited)
gitea_hostname: git.example.com  # Replace with your domain

# Kubernetes configuration (inherited)
domain_name: example.com  # Replace with your domain
kubeconfig: /var/snap/k8s/common/etc/admin.conf
kubectl_bin: /snap/k8s/current/bin/kubectl
system_username: ubuntu
shared_code_path: /home/ubuntu/shared-code
```

**Required environment variables**:
- `ADMIN_PASSWORD`: Admin password for all services
- `GITHUB_TOKEN`: GitHub personal access token for template access
- `HF_TOKEN`: HuggingFace API token for model downloads (optional)

**Required in ~/.env**:
- `HARBOR_ROBOT_TOKEN`: Harbor robot account token (created during Harbor setup)

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all Thinkube Control deployment playbooks in sequence:
- Imports 10_deploy_sync_webhook.yaml - Deploys ArgoCD sync webhook service
- Imports 11_deploy_webhook_adapter.yaml - Deploys Harbor webhook adapter
- Imports 12_deploy.yaml - Main thinkube-control deployment
- Imports 13_configure_code_server.yaml - Configures code-server integration
- Imports 14_deploy_tk_package_version.yaml - Deploys MCP package version server

### 10_deploy_sync_webhook.yaml
ArgoCD sync webhook service for secure, controlled syncing:

- **Webhook Secret**:
  - Generates random 32-character HMAC-SHA256 secret if not exists
  - Reuses existing secret if already deployed (idempotent)
  - Creates `sync-webhook-secret` in argocd namespace with webhook secret and ArgoCD server address

- **Python Webhook Server**:
  - Creates ConfigMap `argocd-sync-webhook-script` with Python HTTP server script
  - Features:
    - HMAC signature verification for security
    - ArgoCD CLI authentication with admin credentials
    - Token caching (24-hour expiry) with automatic refresh
    - "Latest commit wins" semantics (terminates previous operations before sync)
    - Health check endpoint at `/health`
    - Sync endpoint at `/POST /sync` with JSON payload: `{"application": "app-name"}`

- **Deployment**:
  - Image: `{harbor_registry}/library/python:3.12-alpine`
  - Downloads latest ArgoCD CLI binary (architecture-aware)
  - Runs Python webhook server on port 8080
  - Resource requests: 50m CPU, 128Mi memory
  - Resource limits: 100m CPU, 256Mi memory
  - Liveness probe: HTTP GET /health, 30s initial delay
  - Readiness probe: HTTP GET /health, 10s initial delay

- **Service**:
  - ClusterIP service for in-cluster communication
  - Internal URL: `http://argocd-sync-webhook.argocd.svc.cluster.local/sync`

### 11_deploy_webhook_adapter.yaml
Harbor webhook adapter for automatic GitOps updates:

- **Deployment Sequence**:
  - Deploys **before** thinkube-control (no CI/CD token exists yet)
  - Initially processes webhooks without CI/CD monitoring
  - When 12_deploy.yaml completes, it creates the CI/CD monitoring token
  - The deployment then updates the webhook adapter with the token and restarts it
  - After restart, full CI/CD monitoring is active

- **CI/CD Token Configuration**:
  - Checks for `cicd-monitoring-token` secret in thinkube-control namespace
  - If found: Sends pipeline monitoring data to thinkube-control API
  - If not found: Logs "Running in bootstrap mode - CI/CD monitoring will auto-enable when token becomes available"

- **Sync Webhook Integration**:
  - Retrieves sync webhook secret for HMAC signature generation
  - Uses sync webhook URL: `http://argocd-sync-webhook.argocd.svc.cluster.local/sync`

- **Python Webhook Handler**:
  - Creates ConfigMap `harbor-webhook-adapter-script` with comprehensive Python script
  - Listens for Harbor PUSH_ARTIFACT webhook events on port 8080
  - **Smart Image Detection**:
    - Extracts workflow UID from image tag
    - Queries Kubernetes API to find Argo Workflow by UID
    - Retrieves app metadata from workflow labels: `thinkube.io/app-name`, `thinkube.io/namespace`
    - Reads WorkflowTemplate to identify which containers were built
    - Verifies all container images exist in Harbor before processing
  - **Git Operations**:
    - Clones Gitea repository: `https://git.example.com/thinkube-deployments/{app-name}.git`
    - Updates `.argocd-source-{app-name}.yaml` with new image tags
    - Commits: "build: automatic update of {app-name} to {tag}"
    - Pushes changes to Gitea
    - Triggers ArgoCD sync via sync webhook with HMAC signature
  - **CI/CD Monitoring** (when token available):
    - Queries pipeline by workflow UID via thinkube-control API
    - Creates `image_push` stage (component: harbor) with status SUCCEEDED
    - Creates `gitops_update` stage (component: webhook-adapter) with status RUNNING
    - Updates stage to SUCCEEDED or FAILED based on Git push result
  - **Background Processing**:
    - Webhook handler responds immediately (200 accepted)
    - Processing continues in background thread
    - Prevents Harbor webhook timeouts

- **RBAC Configuration**:
  - Creates ServiceAccount `harbor-webhook-adapter` in argocd namespace
  - Creates ClusterRole with permissions:
    - Read ConfigMaps (all namespaces)
    - Read Argo Workflows and WorkflowTemplates (all namespaces)
  - Creates ClusterRoleBinding granting permissions

- **Deployment**:
  - Image: `{harbor_registry}/library/python:3.12-alpine`
  - Installs git and Python dependencies: requests, pyyaml
  - Environment variables:
    - HARBOR_URL, HARBOR_USER, HARBOR_PASSWORD
    - GITEA_URL, GITEA_USER, GITEA_PASSWORD
    - SYNC_WEBHOOK_URL, SYNC_WEBHOOK_SECRET
    - CICD_API_URL: `https://control.example.com/api/v1/cicd`
    - CICD_API_TOKEN: from cicd-monitoring-token secret (if available)
  - Resource requests: 50m CPU, 64Mi memory
  - Resource limits: 100m CPU, 128Mi memory
  - Liveness probe: HTTP GET /, 10s initial delay
  - Readiness probe: HTTP GET /, 5s initial delay

- **Service and Ingress**:
  - ClusterIP service on port 80 → targetPort 8080
  - Ingress at `harbor-webhook-adapter.example.com/webhook`
  - TLS enabled with wildcard certificate

- **Harbor Webhook Configuration**:
  - Creates webhook policy in Harbor `thinkube` project
  - Name: "ArgoCD Git Updater"
  - Target: `https://harbor-webhook-adapter.example.com/webhook`
  - Event type: PUSH_ARTIFACT
  - Skip cert verify: true (internal traffic)

### 12_deploy.yaml
Main deployment playbook for Thinkube Control Hub:

- **Pre-tasks**:
  - Loads environment variables from `.env`
  - Sets GitHub token, HuggingFace token, admin password from environment
  - Retrieves Kubernetes node name and pod network CIDR
  - Configures SSH password authentication for pod network (enables container access)
  - Installs migration tools in shared venv: alembic, sqlalchemy, psycopg2, fastapi, etc.
  - Validates required variables: domain_name, admin_username, github_token, github_org, hf_token

- **Database Setup**:
  - Drops and recreates databases (fresh state):
    - `thinkube_control`: Main application database
    - `thinkube_control_test`: Test database
    - `cicd_monitoring`: CI/CD pipeline tracking
    - `cicd_monitoring_test`: CI/CD test database

- **Namespace and Storage**:
  - Creates `thinkube-control` namespace
  - Creates Role for Job management (template deployments)
  - Creates shared models PVC (500Gi, JuiceFS ReadWriteMany)
  - Accessible by backend and model download workflows

- **Secrets**:
  - `github-token`: GitHub personal access token
  - `huggingface-token`: HuggingFace API token
  - `db-credentials`: PostgreSQL connection details
  - `admin-credentials`: Admin username and password
  - Copies wildcard TLS certificate from default namespace
  - Creates MLflow OAuth2 config secret in argo namespace (for model download workflows)

- **Keycloak Integration**:
  - Creates OAuth2 client via keycloak/keycloak_client role:
    - Client ID: thinkube-control
    - Redirect URI: `https://control.example.com/*`
    - Standard flow enabled
    - Group membership mapper for RBAC
  - Creates `thinkube-admins` group
  - Adds auth_realm_username to admins group

- **Git Repository**:
  - Clones `git@github.com:thinkube/thinkube-control.git`
  - Processes `.jinja` templates with domain values
  - Configures git user for automated commits
  - Sets up deploy keys for SSH access
  - Pushes processed manifests to Gitea repository

- **Gitea Repository Setup**:
  - Creates `thinkube-deployments/thinkube-control` repository in Gitea
  - Configures webhook for Argo Events CI/CD trigger
  - Stores Gitea API token for repository operations

- **Harbor Integration**:
  - Retrieves Harbor robot credentials
  - Creates `harbor-registry-secret` for image pulls
  - Verifies backend and frontend images exist in registry

- **CI/CD Infrastructure**:
  - Creates app metadata ConfigMap with deployment info
  - Deploys CI/CD monitoring ConfigMaps
  - Creates Argo WorkflowTemplate for builds

- **ArgoCD Applications**:
  - Configures ArgoCD repository credentials
  - Creates ArgoCD Application for backend
  - Creates ArgoCD Application for frontend
  - Waits for deployments to stabilize

- **Backend Initialization**:
  - Waits for backend pods to be ready
  - Allows time for database table initialization
  - Verifies API tables exist: users, templates, deployments
  - Creates CI/CD monitoring API token in database
  - Stores token in `cicd-monitoring-token` Kubernetes secret

- **Post-Deployment**:
  - Updates webhook adapter with CI/CD monitoring token
  - Restarts webhook adapter pods to enable full monitoring
  - Displays comprehensive setup summary

- **Resource Configuration**:
  - Frontend: 500m CPU limit, 512Mi memory limit
  - Backend: 500m CPU limit, 512Mi memory limit
  - Liveness and readiness probes configured

### 13_configure_code_server.yaml
Code-server and VS Code integration configuration:

- **Kubernetes Configuration Play**:
  - Verifies thinkube-control and code-server namespaces exist
  - Extracts CI/CD monitoring token from thinkube-control namespace
  - Copies token to code-server namespace as `cicd-monitoring-token`
  - Updates VS Code settings.json in code-server pod:
    - Enables git autofetch
    - Configures CI/CD extension settings:
      - apiUrl: `https://control.example.com/api/v1/cicd`
      - apiToken: from secret
      - refreshInterval: 30000ms
    - Sets terminal environment paths
  - Restarts code-server deployment to apply changes

- **MCP Configuration Play** (localhost):
  - Updates or creates `.mcp.json` in thinkube-control project root
  - Registers thinkube-control as HTTP MCP server:
    - Command: Uses bearer token authorization
    - URL: `https://control.example.com/api/mcp/mcp/`
    - Authorization: Bearer {cicd_token}
  - Available MCP tools:
    - `list_templates()`: List available deployment templates
    - `get_template_parameters(template_url)`: Get template variables
    - `deploy_template(template_url, app_name, variables)`: Deploy application
    - `get_deployment_status_by_id(deployment_id)`: Check deployment status
    - `get_deployment_logs_by_id(deployment_id)`: View deployment logs
    - `list_recent_deployments()`: List recent deployments
    - `cancel_deployment_by_id(deployment_id)`: Cancel deployment

### 14_deploy_tk_package_version.yaml
MCP package version server deployment:

- **Deployment Configuration**:
  - Creates Deployment `tk-package-version` in thinkube-control namespace
  - Image: `{harbor_registry}/library/tk-package-version:latest`
  - Replicas: 1
  - Environment variables:
    - BASE_URL: `https://control.example.com/tk-package-version`
    - PORT: 18080
    - LOG_LEVEL: info
    - CACHE_TTL: 300 seconds
  - Resource requests: 50m CPU, 64Mi memory
  - Resource limits: 500m CPU, 256Mi memory
  - Liveness probe: HTTP GET /health, 15s initial delay
  - Readiness probe: HTTP GET /health, 5s initial delay

- **Service**:
  - ClusterIP service exposing port 18080

- **Ingress**:
  - Path: `/tk-package-version(/|$)(.*)`
  - Rewrite target: `/$2` (strips prefix)
  - TLS enabled
  - Proxy timeouts: 600 seconds
  - Routes to tk-package-version service port 18080

- **Endpoints**:
  - Service: `https://control.example.com/tk-package-version`
  - MCP: `https://control.example.com/tk-package-version/mcp`
  - Health: `https://control.example.com/tk-package-version/health`

## Deployment

Thinkube Control is automatically deployed by the Thinkube installer at deployment order #30. The installer executes the orchestrator playbook (00_install.yaml) which runs all required playbooks in sequence.

No manual intervention is required during installation.

## Access Points

- **Web Dashboard**: https://control.example.com (Keycloak SSO authentication)
- **API**: https://control.example.com/api/v1/ (Bearer token authentication)
- **MCP Server**: https://control.example.com/api/mcp/mcp/ (Bearer token authentication)
- **Package Version MCP**: https://control.example.com/tk-package-version/mcp (Streamable HTTP transport)

Replace `example.com` with your actual domain.

## GitOps Workflow

Thinkube Control demonstrates the platform's GitOps pattern:

```
GitHub (templates) → Jinja Processing → Gitea (manifests) → ArgoCD
     ↑                                         ↓
     └──── Contribute back (templates) ───────┘
```

### Development Cycle

1. **Source Repository** (GitHub):
   - Stores template files with `.jinja` extensions
   - Variables like `{{ domain_name }}` for portability
   - Reusable across different Thinkube installations

2. **Template Processing** (Ansible):
   - Clones from GitHub
   - Processes Jinja templates with domain-specific values
   - Example: `{{ domain_name }}` → `example.com`

3. **Deployment Repository** (Gitea):
   - Stores processed manifests with actual values
   - Domain-specific, not portable
   - Watched by ArgoCD for automatic deployment

4. **Continuous Deployment** (ArgoCD):
   - Syncs from Gitea repository
   - Applies manifests to Kubernetes cluster
   - Automatic updates on git push (via webhooks)

### CI/CD Pipeline Flow

```
1. Git Push → Gitea
   ↓
2. Gitea Webhook → Argo Events → Argo Workflow
   ↓
3. Kaniko Build → Harbor Registry (~1 min)
   ↓
4. Harbor Webhook → Webhook Adapter
   ↓
5. Git Update → Gitea (.argocd-source files)
   ↓
6. Gitea Commit → Sync Webhook → ArgoCD
   ↓
7. ArgoCD Deploys (~30 sec)
```

**Total time**: ~1.5 minutes from code push to deployment

## Configuration

### Authentication

Users must have Keycloak realm role `thinkube-admins` to access the dashboard and API.

### Template Deployment

Deploy applications from GitHub templates:

```bash
# Via API
curl -X POST https://control.example.com/api/v1/templates/deploy \
  -H "Authorization: Bearer $CICD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "template_url": "https://github.com/thinkube/thinkube-fastapi-template.git",
    "app_name": "my-api",
    "variables": {
      "domain_name": "example.com",
      "namespace": "my-api"
    }
  }'

# Via MCP (in Claude Code)
# Use the deploy_template MCP tool with template URL and variables
```

### CI/CD Monitoring API

Track pipeline execution:

```bash
# List recent pipelines
curl https://control.example.com/api/v1/cicd/pipelines?limit=10 \
  -H "Authorization: Bearer $CICD_TOKEN"

# Get pipeline details
curl https://control.example.com/api/v1/cicd/pipelines/{pipeline_id} \
  -H "Authorization: Bearer $CICD_TOKEN"

# Get deployment logs
curl https://control.example.com/api/v1/cicd/deployments/{deployment_id}/logs \
  -H "Authorization: Bearer $CICD_TOKEN"
```

### MCP Integration

Use with Claude Code or other MCP clients:

```json
{
  "mcpServers": {
    "thinkube-control": {
      "command": "curl",
      "args": [
        "-H", "Authorization: Bearer YOUR_TOKEN",
        "https://control.example.com/api/mcp/mcp/"
      ]
    },
    "tk-package-version": {
      "url": "https://control.example.com/tk-package-version/mcp"
    }
  }
}
```

## Troubleshooting

### Check thinkube-control pods
```bash
kubectl get pods -n thinkube-control
kubectl logs -n thinkube-control deploy/thinkube-control-backend
kubectl logs -n thinkube-control deploy/thinkube-control-frontend
```

### Verify webhook infrastructure
```bash
# Check sync webhook
kubectl get pods -n argocd -l app=argocd-sync-webhook
kubectl logs -n argocd deploy/argocd-sync-webhook

# Check webhook adapter
kubectl get pods -n argocd -l app=harbor-webhook-adapter
kubectl logs -n argocd deploy/harbor-webhook-adapter

# Verify CI/CD token
kubectl get secret -n thinkube-control cicd-monitoring-token -o yaml
```

### Test webhook endpoints
```bash
# Test sync webhook health
curl http://argocd-sync-webhook.argocd.svc.cluster.local/health

# Test webhook adapter health
curl https://harbor-webhook-adapter.example.com  # Replace with your domain

# Verify Harbor webhook configuration
# Login to Harbor → Projects → thinkube → Webhooks
# Should show "ArgoCD Git Updater" webhook
```

### Check database connections
```bash
# Verify databases exist
kubectl exec -n postgres deploy/postgresql-official -- psql -U admin -l | grep thinkube_control

# Check API tables
kubectl exec -n postgres deploy/postgresql-official -- \
  psql -U admin -d thinkube_control -c "\dt"
# Should show: users, templates, deployments, etc.
```

### Verify ArgoCD applications
```bash
# Check ArgoCD applications
kubectl get applications -n argocd | grep thinkube-control

# Get application status
argocd app get thinkube-control-backend --insecure
argocd app get thinkube-control-frontend --insecure
```

### Test API endpoints
```bash
# Get CI/CD monitoring token
CICD_TOKEN=$(kubectl get secret -n thinkube-control cicd-monitoring-token -o jsonpath='{.data.token}' | base64 -d)

# Test API health
curl https://control.example.com/api/health  # Replace with your domain

# Test CI/CD API
curl -H "Authorization: Bearer $CICD_TOKEN" \
  https://control.example.com/api/v1/cicd/pipelines?limit=1  # Replace with your domain
```

### Check Gitea repository
```bash
# Verify repository exists
curl https://git.example.com/api/v1/repos/thinkube-deployments/thinkube-control  # Replace with your domain

# Check webhook configuration
curl -H "Authorization: token $GITEA_TOKEN" \
  https://git.example.com/api/v1/repos/thinkube-deployments/thinkube-control/hooks  # Replace with your domain
```

## References

- [Thinkube Control GitHub Repository](https://github.com/thinkube/thinkube-control)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Argo Workflows Documentation](https://argoproj.github.io/workflows/)
- [Model Context Protocol (MCP) Specification](https://spec.modelcontextprotocol.io/)
