# ArgoCD

This component deploys [ArgoCD](https://argo-cd.readthedocs.io/) - a declarative, GitOps continuous delivery tool for Kubernetes.

## Overview

ArgoCD enables declarative, Git-based management of Kubernetes resources and applications. It provides:

- **Git as Single Source of Truth**: Application definitions, configurations, and environments tracked in Git
- **Automated Deployment**: Automatically sync applications from Git repositories to Kubernetes clusters
- **Web UI**: Visual interface for managing applications and viewing sync status
- **CLI**: Command-line tool for automation and CI/CD integration
- **SSO Integration**: Keycloak authentication for centralized user management
- **Multi-Cluster Support**: Manage applications across multiple Kubernetes clusters
- **RBAC**: Role-based access control integrated with Keycloak groups

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster
- ingress (deployment order #13) - For web UI and API access
- acme-certificates (deployment order #12) - For TLS certificates
- keycloak (deployment order #15) - For SSO authentication

**Deployment order**: #24

## Prerequisites

**Required inventory variables** (example values shown):

```yaml
# ArgoCD configuration
argocd_namespace: argocd
argocd_hostname: argocd.example.com  # Replace with your domain
argocd_grpc_hostname: argocd.example.com  # Same as main hostname (SSL passthrough)
argocd_client_id: argocd
argocd_release_name: argocd
argocd_chart_repo: https://argoproj.github.io/argo-helm
argocd_chart_name: argo-cd

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
- `ADMIN_PASSWORD`: Admin password for ArgoCD and Keycloak access

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all ArgoCD deployment playbooks in sequence:
- Imports 10_configure_keycloak.yaml - Configures Keycloak OAuth2 client
- Imports 11_deploy.yaml - Deploys ArgoCD
- Imports 12_get_credentials.yaml - Retrieves initial admin credentials
- Imports 13_setup_serviceaccount.yaml - Installs CLI and configures service account
- Imports 17_configure_discovery.yaml - Configures service discovery

### 10_configure_keycloak.yaml
Keycloak OAuth2 client configuration for ArgoCD SSO authentication:

- **Keycloak Client Creation**:
  - Creates ArgoCD OAuth2/OIDC client in Keycloak realm
  - Client ID: `argocd`
  - Protocol: openid-connect
  - Enables standard flow (authorization code flow)
  - Disables direct access grants

- **Redirect URI Configuration**:
  - Configures redirect URIs: `https://argocd.{{ domain_name }}/api/dex/callback`, `https://argocd.{{ domain_name }}/*`
  - Sets web origins: `https://argocd.{{ domain_name }}`

- **Group Membership Mapper**:
  - Checks for existing protocol mappers
  - Creates group membership mapper for RBAC
  - Maps user groups to token claims for ArgoCD authorization

- **ArgoCD Admin Group**:
  - Creates `argocd-admins` group in Keycloak
  - Adds admin user to argocd-admins group
  - Group membership used for ArgoCD RBAC policies

### 11_deploy.yaml
Main deployment playbook for ArgoCD:

- **Keycloak Client Secret Retrieval**:
  - Obtains Keycloak admin token
  - Queries for existing ArgoCD client
  - Fails if client not found (must run 10_configure_keycloak.yaml first)
  - Retrieves OAuth2 client secret from Keycloak API

- **Namespace Setup**:
  - Creates `argocd` namespace
  - Copies wildcard TLS certificate from default namespace as `argocd-server-tls`

- **Helm Repository**:
  - Adds argo-helm Helm repository
  - Updates Helm repository index

- **Admin Password Hash**:
  - Installs apache2-utils for htpasswd
  - Generates bcrypt hash of admin password from ADMIN_PASSWORD environment variable
  - Hash used for ArgoCD admin user authentication

- **ArgoCD Helm Deployment**:
  - Creates Helm values file with:
    - Admin user enabled with custom username (from inventory)
    - Server URL: `https://argocd.{{ domain_name }}`
    - Admin password hash and modification time
    - Server TLS configuration (TLS 1.2-1.3, secure cipher suites)
    - Ingress disabled (manual creation with SSL passthrough)
  - Deploys or upgrades ArgoCD via Helm chart
  - Waits for ArgoCD pods to be ready

- **SSL Passthrough Ingress**:
  - Removes any existing ingress resources (argocd-grpc-ingress, argocd-http-ingress, argocd-ingress)
  - Creates single Ingress `argocd-ingress` at `argocd.{{ domain_name }}`
  - Annotations:
    - `nginx.ingress.kubernetes.io/ssl-passthrough: "true"` - Passes encrypted traffic directly to ArgoCD
    - `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"` - Backend expects HTTPS
  - IngressClass: nginx
  - Routes to argocd-server service port 443
  - ArgoCD server handles TLS and auto-detects HTTP (web UI) vs gRPC (CLI) protocols

**Note**: SSL passthrough approach recommended by ArgoCD documentation. Single endpoint serves both web UI and gRPC API, with ArgoCD server automatically detecting protocol.

### 12_get_credentials.yaml
Retrieves ArgoCD initial admin credentials:

- **Initial Admin Password**:
  - Retrieves password from `argocd-initial-admin-secret` secret
  - Username is always `admin` (ArgoCD default)
  - Displays credentials (will be changed by 13_setup_serviceaccount.yaml)

- **Save to .env File**:
  - Checks if `~/.env` file exists
  - Creates .env file with mode 0600 if needed
  - Updates or adds ARGOCD_PASSWORD variable
  - Stores initial password for reference

### 13_setup_serviceaccount.yaml
CLI installation and service account configuration:

- **System Architecture Detection**:
  - Detects system architecture (amd64 or arm64)
  - Sets appropriate ArgoCD CLI binary architecture

- **ArgoCD CLI Installation**:
  - Downloads ArgoCD CLI v2.13.1 for detected architecture
  - Creates `~/.local/bin` directory
  - Installs binary to `~/.local/bin/argocd` with executable permissions

- **Admin Credentials**:
  - Retrieves initial admin password from argocd-initial-admin-secret
  - Falls back to ADMIN_PASSWORD if secret doesn't exist (retry scenario)
  - Sets argocd_user to `admin`

- **CLI Login**:
  - Logs in to ArgoCD server at `argocd.{{ domain_name }}`
  - Uses insecure mode (argocd_cli_insecure: true)
  - Updates admin password to match ADMIN_PASSWORD

- **Service Account Creation**:
  - Creates `argo-cd-deployer` account in ArgoCD
  - Generates authentication token for automation
  - Saves token to `argo-cd-deployer-token` secret
  - Updates .env file with ARGOCD_AUTH_TOKEN

- **SSH Key Configuration**:
  - Uses SSH key from `~/.ssh/{{ hostname }}` for Git repository access
  - Creates `github-ssh-key` secret in argocd namespace

### 17_configure_discovery.yaml
Service discovery configuration:

- **Service Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in argocd namespace
  - Labels: `thinkube.io/managed`, `thinkube.io/service-type: core`, `thinkube.io/service-name: argocd`
  - Defines service metadata:
    - Display name: "ArgoCD"
    - Description: "GitOps continuous delivery for Kubernetes"
    - Category: devops
    - Icon: /icons/tk_devops.svg
  - Endpoint configuration:
    - Web UI: https://argocd.{{ domain_name }} (primary)
    - Health check: https://argocd.{{ domain_name }}/api/version
  - Dependencies: redis (internal ArgoCD dependency)
  - Scaling configuration: Deployment argocd-server, minimum 1 replica
  - Environment variables: ARGOCD_SERVER, ARGOCD_GRPC_SERVER, ARGOCD_AUTH_TOKEN

## Deployment

ArgoCD is automatically deployed by the Thinkube installer at deployment order #24. The installer executes the orchestrator playbook (00_install.yaml) which runs all required playbooks in sequence.

No manual intervention is required during installation.

## Access Points

- **Web UI**: https://argocd.{{ domain_name }} (Keycloak SSO authentication)
- **gRPC API**: https://argocd.{{ domain_name }} (Same endpoint, protocol auto-detected)

Replace `{{ domain_name }}` with your actual domain (e.g., example.com).

## Security Notice

### SSL Passthrough Configuration

The ArgoCD deployment uses **SSL passthrough** for secure connections, as recommended by the [official ArgoCD documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/):

1. **Single Ingress Endpoint**: Both web UI (HTTP/HTTPS) and CLI (gRPC) use the same domain: `argocd.{{ domain_name }}`
2. **SSL Passthrough**: Nginx Ingress passes encrypted TLS traffic directly to the ArgoCD server without terminating it
3. **Protocol Auto-Detection**: ArgoCD server handles TLS termination and automatically detects whether incoming requests are HTTP (web browser) or gRPC (CLI)
4. **TLS Configuration**: ArgoCD server uses the wildcard certificate copied to the argocd namespace

### Why CLI Requires `--insecure` Flag

The ArgoCD CLI must use the `--insecure` flag when connecting to the API server. This is **NOT** a security compromise but a technical requirement:

**Why this is needed**:
- SSL passthrough means the ingress does NOT terminate TLS
- The CLI connects directly to ArgoCD server's self-signed service certificate, not the wildcard ingress certificate
- The ArgoCD server presents its own certificate for the gRPC connection
- The CLI cannot validate this certificate against standard CA chains

**Security is maintained because**:
- TLS encryption is still fully active (SSL passthrough ensures this)
- Traffic between client and server is encrypted end-to-end
- The wildcard certificate secures the ingress layer
- Only the certificate validation step is skipped, not the encryption

**Alternative approaches considered**:
- **Separate ingresses for HTTP and gRPC** (previous approach): Required running ArgoCD server in insecure mode, which was less secure
- **Current SSL passthrough approach**: ArgoCD server handles its own TLS, providing better security despite requiring `--insecure` flag

For more details, see [ArgoCD Ingress Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/) and [How to eat the gRPC cake and have it too!](https://blog.argoproj.io/how-to-eat-the-grpc-cake-and-have-it-too-77bc4ed555f6)

## Configuration

### CLI Authentication

The ArgoCD CLI is installed at `~/.local/bin/argocd`. The `--insecure` flag is required due to SSL passthrough (see Security Notice above):

```bash
# Login with admin credentials
argocd login argocd.example.com --insecure --username admin --password $ADMIN_PASSWORD

# Or use service account token
argocd login argocd.example.com --insecure --auth-token $ARGOCD_AUTH_TOKEN

# List applications
argocd app list

# Sync application
argocd app sync my-app

# Get application details
argocd app get my-app
```

### SSO Authentication

Users can log in via Keycloak SSO:

1. Navigate to https://argocd.{{ domain_name }}
2. Click "LOG IN VIA KEYCLOAK" button
3. Authenticate with Keycloak credentials
4. ArgoCD grants permissions based on Keycloak group membership

Users in the `argocd-admins` Keycloak group have full administrator access.

### Creating Applications

ArgoCD applications can be created via UI, CLI, or declaratively:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/repo.git
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Troubleshooting

### Check ArgoCD pods
```bash
kubectl get pods -n argocd
kubectl logs -n argocd deploy/argocd-server
kubectl logs -n argocd deploy/argocd-application-controller
```

### Verify Keycloak integration
```bash
# Check ArgoCD client exists in Keycloak
# Login to Keycloak admin console and verify argocd client

# Check argocd-admins group membership
# Verify admin user is member of argocd-admins group
```

### Test web UI access
```bash
# Should redirect to Keycloak for authentication
curl -I https://argocd.example.com  # Replace with your domain
```

### Verify SSL passthrough
```bash
# Check ingress annotations
kubectl get ingress -n argocd argocd-ingress -o yaml

# Should show:
# nginx.ingress.kubernetes.io/ssl-passthrough: "true"
# nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
```

### CLI connection issues
```bash
# Verify CLI can connect (must use --insecure flag)
argocd version --insecure --server argocd.example.com  # Replace with your domain

# If connection fails, check ArgoCD server logs
kubectl logs -n argocd deploy/argocd-server

# Verify argocd-server service is listening on port 443
kubectl get svc -n argocd argocd-server
```

### Reset admin password
```bash
# Update admin password via CLI
argocd account update-password --insecure

# Or update via kubectl
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {"admin.password": "'$(htpasswd -nbiBC 10 "" '$NEW_PASSWORD' | tr -d ':\n' | sed 's/$2y/$2a/')'"}}'
```

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Ingress Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/)
- [How to eat the gRPC cake and have it too!](https://blog.argoproj.io/how-to-eat-the-grpc-cake-and-have-it-too-77bc4ed555f6)
- [ArgoCD Helm Chart](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd)
