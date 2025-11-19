# Harbor Container Registry

This component deploys Harbor container registry with full OIDC authentication integration via Keycloak.

## Overview

Harbor is an open-source container registry that provides:
- Container image storage and distribution
- OIDC authentication integration with Keycloak
- Image vulnerability scanning via Trivy
- Role-based access control with harbor-admins group
- Image replication
- Project isolation
- Built-in PostgreSQL database and Redis cache

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster with k8s-hostpath storage class
- acme-certificates (deployment order #12) - Wildcard TLS certificate in default namespace
- ingress (deployment order #13) - Primary NGINX ingress controller for HTTPS access
- keycloak (deployment order #15) - OIDC authentication provider

**Required by** (which components depend on this):
- Optional: Other services that pull container images from Harbor
- Optional: CI/CD pipelines using Harbor as container registry

**Deployment order**: #16

See [Deployment Dependency Graph](https://github.com/thinkube/thinkube-documentation/blob/main/architecture/deployment-dependency-graph.md) for complete dependency tree.

## Prerequisites

**Required inventory variables** (example values shown):
```yaml
# Harbor configuration
harbor_registry: registry.example.com       # Harbor registry hostname (replace with your domain)
harbor_namespace: registry                  # Namespace for Harbor deployment
harbor_release: harbor                      # Helm release name
harbor_project: thinkube                   # Default project name

# Keycloak configuration (inherited)
keycloak_url: https://auth.example.com     # Keycloak server URL
keycloak_realm: thinkube                    # Keycloak realm name
admin_username: admin                       # Admin username for Keycloak
auth_realm_username: admin                  # Realm user to add to harbor-admins group

# Ingress configuration (inherited)
primary_ingress_class: nginx                # Primary ingress class
domain_name: example.com                    # Base domain for certificate lookup

# Storage configuration
harbor_storage_class: k8s-hostpath         # Storage class for PVCs
harbor_registry_size: 500Gi                # Registry storage size
harbor_database_size: 10Gi                 # Database storage size
```

**Environment variables**:
- `ADMIN_PASSWORD`: Required for Keycloak authentication and Harbor admin password

**Required infrastructure**:
1. Kubernetes cluster with k8s-hostpath storage class
2. Wildcard TLS certificate in default namespace (from acme-certificates)
3. Primary NGINX ingress controller for HTTPS routing
4. Keycloak deployed and accessible for OIDC authentication

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all Harbor deployment playbooks in sequence:
- Imports 10_deploy.yaml (Harbor deployment)
- Imports 11_install_podman.yaml (Podman installation)
- Imports 12_configure_thinkube.yaml (Project and robot account setup)
- Imports 17_configure_discovery.yaml (Service discovery configuration)

This provides a single entry point for complete Harbor installation.

### 10_deploy.yaml
Main deployment playbook (800 lines) that:
- **Keycloak OIDC Setup** (lines 79-273):
  - Gets Keycloak admin token
  - Creates Harbor OIDC client with redirect URIs
  - Ensures OIDC scopes exist (openid, profile, email, groups)
  - Associates scopes with Harbor client
  - Creates groups mapper for OIDC groups claim
  - Creates `harbor-admins` group in Keycloak
  - Adds `auth_realm_username` to harbor-admins group
  - Retrieves and saves client secret
- **Harbor Deployment** (lines 279-463):
  - Creates `registry` namespace
  - Copies wildcard certificate from default namespace as `harbor-tls-secret`
  - Adds Harbor Helm repository
  - Generates Helm values file with:
    - Ingress configuration (NGINX with TLS)
    - Persistence for registry (500Gi), database (10Gi), redis (2Gi), trivy (10Gi), jobservice (5Gi)
    - ARM64 image overrides if detected (ranichowdary multiarch images)
  - Deploys Harbor v2.14.0 via Helm chart
  - Patches harbor-portal and harbor-trivy for ARM64 compatibility (if ARM64)
  - Waits for all pods except trivy to be ready
- **Admin Password Configuration** (lines 526-625):
  - Retrieves Harbor-generated admin password from secret
  - Tests API access with generated password
  - Changes Harbor admin password to standard `admin_password`
  - Verifies API access with new password
- **OIDC Configuration** (lines 627-683):
  - Refreshes Keycloak token
  - Verifies harbor-admins group exists in Keycloak
  - Configures Harbor OIDC authentication via API:
    - auth_mode: oidc_auth
    - oidc_endpoint, client_id, client_secret
    - oidc_scope: openid,profile,email,groups
    - oidc_auto_onboard: true
    - oidc_groups_claim: groups
    - oidc_admin_group: harbor-admins
- **Certificate Trust Configuration** (lines 686-748):
  - Extracts Let's Encrypt certificate from default namespace
  - Gets intermediate certificate chain
  - Creates ConfigMap `trusted-ca-bundle` with certificates
  - Patches harbor-core deployment to mount ConfigMap
  - Restarts harbor-core to pick up certificate changes
- **Verification** (lines 750-799):
  - Verifies Harbor API is accessible
  - Asserts auth_mode is oidc_auth
  - Displays OIDC configuration
  - Shows deployment status

### 11_install_podman.yaml
Installs and configures Podman for registry testing (184 lines):
- **Package Installation** (lines 34-52):
  - Updates apt cache
  - Installs podman, podman-compose, podman-toolbox, buildah, skopeo
  - Installs qemu-user-static and binfmt-support for multi-arch builds
- **Multi-Architecture Support** (lines 53-73):
  - Enables QEMU binfmt support (amd64/arm64)
  - Restarts systemd-binfmt service
  - Verifies QEMU handlers for ARM/ARM64 emulation
- **Rootless Configuration** (lines 75-100):
  - Adds user to systemd-journal group
  - Enables loginctl linger for user systemd services
  - Creates podman directories (~/.config/containers, ~/.local/share/containers)
- **Registry Configuration** (lines 101-143):
  - Configures Harbor as default unqualified-search-registry
  - Adds docker.io, quay.io, ghcr.io as additional registries
  - Creates both user-level and system-wide registries.conf
- **Subuid/Subgid Setup** (lines 145-160):
  - Sets subuid/subgid mappings (100000:65536)
  - Initializes podman system with migrations
- **Verification** (lines 162-184):
  - Checks podman version
  - Tests with hello-world container

### 12_configure_thinkube.yaml
Creates Harbor project and robot account for Kubernetes deployments (303 lines):
- **Project Creation** (lines 57-97):
  - Creates Harbor project from `harbor_project` variable (private by default)
  - Handles 409 conflict if project already exists
  - Retrieves project ID for robot account permissions
- **Robot Account Management** (lines 99-226):
  - Checks for existing system-level robot account
  - Creates robot account with 100-year duration (effectively never expires)
  - Grants pull/push/list permissions for both `harbor_project` and `library` projects
  - If robot exists, deletes and recreates to refresh credentials
  - Extracts robot secret token
- **Credential Storage** (lines 228-277):
  - Saves robot token to ~/.env as HARBOR_ROBOT_TOKEN
  - Creates harbor-robot-credentials secret in kube-system namespace
  - Creates ~/.config/containers/auth.json for podman authentication
- **Kubernetes Pull Secret** (lines 279-295):
  - Creates harbor-pull-secret in default namespace
  - Type: kubernetes.io/dockerconfigjson
  - Contains robot account credentials for pod image pulls

### 17_configure_discovery.yaml
Configures service discovery for Harbor Registry (99 lines):
- Creates ConfigMap `thinkube-service-config` in registry namespace
- Labels: thinkube.io/managed, thinkube.io/service-type: core, thinkube.io/service-name: harbor
- **Service Metadata**:
  - Display name: "Harbor Registry"
  - Description: "Enterprise container registry with security scanning"
  - Category: storage
  - Icon: /icons/tk_artifact.svg
- **Endpoints**:
  - Web UI: https://registry.example.com (replace with your domain)
  - Docker registry v2: https://registry.example.com:443 (replace with your domain)
  - Notary signing service: https://notary.example.com (replace with your domain)
- **Dependencies**: postgresql, redis
- **Scaling Config**: Deployment harbor-core in registry namespace, min 1 replica

### 18_test.yaml
Comprehensive test playbook that verifies Harbor deployment (336 lines):
- **Kubernetes Resource Checks** (lines 40-100):
  - Verifies namespace exists
  - Checks Helm release status
  - Verifies all Harbor pods are Running
  - Checks services and ingress configuration
- **API and Web Interface Checks** (lines 102-186):
  - Tests Harbor API availability (/api/v2.0/systeminfo)
  - Verifies OIDC authentication is configured (auth_mode: oidc_auth)
  - Checks that Harbor project exists
  - Uses basic auth with admin credentials
- **Registry Operation Tests** (lines 188-304):
  - Detects container runtime (podman or docker)
  - Reads robot token from ~/.env
  - Creates ~/.config/containers/auth.json
  - Tests registry login with robot credentials
  - Verifies harbor-pull-secret exists in default namespace
  - Tests registry V2 API endpoint
- **Display Test Results** (lines 306-336):
  - Shows namespace, pods, services, ingress status
  - Displays API availability and auth mode
  - Shows TLS certificate validation status
  - Confirms pull secret creation

### 19_rollback.yaml
Cleanup playbook that removes Harbor installation (210 lines):
- **Harbor Cleanup** (lines 34-88):
  - Checks if Harbor namespace and Helm release exist
  - Removes Harbor Helm release (300s wait timeout)
  - Deletes Harbor namespace with wait for deletion
  - Verifies cleanup completed
- **Keycloak OIDC Cleanup** (lines 89-167):
  - Gets Keycloak admin token
  - Retrieves harbor OIDC client UUID
  - Deletes harbor OIDC client from Keycloak realm
  - Retrieves harbor-admins group ID
  - Deletes harbor-admins group from Keycloak
- **Credential Cleanup** (lines 169-199):
  - Removes /tmp/harbor_oidc_secret file
  - Removes /tmp/harbor-values.yaml file
  - Removes HARBOR_ROBOT_TOKEN from ~/.env
  - Deletes harbor-pull-secret from default namespace
- **Status Display** (lines 201-210):
  - Shows cleanup status for all components


## Environment Variables

- `ADMIN_PASSWORD`: Required for Keycloak authentication during deployment
- `HARBOR_ROBOT_TOKEN`: Generated by 12_configure_thinkube.yaml and stored in ~/.env

## Usage

Harbor is automatically deployed by the Thinkube installer at deployment order #16. The installer executes the orchestrator playbook (00_install.yaml) which runs all required playbooks in sequence:

1. **10_deploy.yaml** - Deploys Harbor with OIDC authentication
2. **11_install_podman.yaml** - Installs Podman for registry operations
3. **12_configure_thinkube.yaml** - Creates project and robot account
4. **17_configure_discovery.yaml** - Configures service discovery

No manual intervention is required during installation.

## Post-Deployment

After successful deployment:

1. Access Harbor UI at `https://registry.example.com` (replace with your domain)
2. Login using Keycloak SSO with your admin credentials
3. The 'thinkube' project is ready for use (if configured via 15_configure_thinkube.yaml)
4. Robot credentials are stored in ~/.env (if configured)

## Registry Usage

### Podman Login
```bash
podman login registry.example.com  # Replace with your domain
# Use robot credentials from ~/.env or SSO credentials
```

### Push an Image
```bash
podman tag myimage:latest registry.example.com/thinkube/myimage:latest
podman push registry.example.com/thinkube/myimage:latest
```

### Pull an Image
```bash
podman pull registry.example.com/thinkube/myimage:latest
```

### Kubernetes Pull Secret
The deployment creates a pull secret in the default namespace:
```yaml
imagePullSecrets:
  - name: harbor-pull-secret
```

## Troubleshooting

### Check Harbor Status
```bash
kubectl get pods -n registry
kubectl get svc -n registry
helm list -n registry
```

### View Logs
```bash
kubectl logs -n registry deployment/harbor-core
kubectl logs -n registry deployment/harbor-registry
```

### Verify OIDC Configuration
```bash
curl -I https://registry.example.com  # Replace with your domain
# Should redirect to Keycloak for authentication
```

## Rollback

The 19_rollback.yaml playbook can be used to completely remove Harbor:
- Removes the Helm release
- Deletes the namespace and all Harbor resources
- Removes OIDC client and harbor-admins group from Keycloak
- Cleans up credentials from ~/.env and Kubernetes secrets
- Removes temporary files

## ARM64 Support

Harbor v2.14.0 does not provide official ARM64 container images. Thinkube uses pre-built multi-architecture images from ranichowdary:

### Image Source

Pre-built images from https://hub.docker.com/u/ranichowdary (author of Harbor's multiarch-platform-support branch):
- `ranichowdary/harbor-core:latest`
- `ranichowdary/harbor-db:latest`
- `ranichowdary/jobservice-harbor:latest`
- `ranichowdary/harbor-portal:latest`
- `ranichowdary/harbor-registryctl:latest`
- `ranichowdary/registry-harbor:latest`
- `ranichowdary/redis-photon:latest`
- `ranichowdary/trivy-adapter-photon:latest`

These images support both ARM64 and AMD64 architectures.

### Deployment Process

The deployment playbook (`10_deploy.yaml`) automatically:
1. Pulls pre-built Harbor images from ranichowdary's Docker Hub repository
2. Tags images with `tk-harbor-*` prefix for consistency
3. Imports images into containerd on the control plane node
4. Deploys Harbor using Helm with architecture-pinned nodeSelector

### Architecture Pinning

**IMPORTANT**: All Harbor components are pinned to the k8s_control_plane node using nodeSelector.

**Why?**
- Images are imported only on the control plane node
- Simplifies deployment (no need to import on all nodes)
- Prevents scheduling issues when images aren't available on worker nodes

**Limitation**: In multi-node clusters, Harbor will only run on the control plane node.

**Future Enhancement**: To support multi-node scheduling:
- Import images on all nodes during deployment
- Or configure Harbor to use a container registry instead of local images

### Custom Image Names

All Harbor images are tagged with the `tk-harbor-` prefix for local use:
- `tk-harbor-harbor-core:v2.14.0`
- `tk-harbor-harbor-db:v2.14.0`
- `tk-harbor-harbor-jobservice:v2.14.0`
- `tk-harbor-harbor-portal:v2.14.0`
- `tk-harbor-harbor-registryctl:v2.14.0`
- `tk-harbor-registry-photon:v2.14.0`
- `tk-harbor-redis-photon:v2.14.0`
- `tk-harbor-trivy-adapter-photon:v2.14.0`

The Helm values are configured with `imagePullPolicy: Never` to use locally imported images.

## Notes

- **Authentication**: Harbor uses OIDC authentication via Keycloak; admin user is `admin` (cannot be changed, but password is set to standard `admin_password`)
- **Built-in Services**: Harbor includes its own PostgreSQL database and Redis instance (not the platform PostgreSQL)
- **Storage**: Images are stored on persistent volumes using k8s-hostpath storage class (500Gi for registry, 10Gi for database, 2Gi for redis, 10Gi for trivy, 5Gi for jobservice logs)
- **TLS Certificates**: Wildcard TLS certificate is copied from default namespace and trusted CA bundle is configured
- **OIDC Group**: `harbor-admins` group in Keycloak provides admin privileges; `auth_realm_username` is automatically added to this group
- **Trivy Scanner**: May take 5-10 minutes to download vulnerability databases on first start
- **ARM64 Support**: Uses ranichowdary multiarch images for ARM64 architecture; components patched for ARM64 compatibility
- **Certificate Trust**: Let's Encrypt intermediate certificates are added to harbor-core trusted CA bundle for OIDC connectivity

🤖 [AI-assisted]