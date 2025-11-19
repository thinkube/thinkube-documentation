# Keycloak Component

## Overview

This component deploys and configures Keycloak as the identity provider for the Thinkube platform. Keycloak provides centralized authentication and authorization services for all platform components, running in production mode with PostgreSQL backend.

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster infrastructure
- acme-certificates (deployment order #12) - Wildcard TLS certificate in default namespace
- ingress (deployment order #13) - Primary NGINX ingress controller for HTTPS access
- postgresql (deployment order #14) - Database backend for Keycloak data

**Required by** (which components depend on this):
- harbor - Uses Keycloak for OIDC authentication
- jupyterhub - Integration for user authentication
- Other platform services requiring SSO/OIDC

**Deployment order**: #15

See [Deployment Dependency Graph](https://github.com/thinkube/thinkube-documentation/blob/main/architecture/deployment-dependency-graph.md) for complete dependency tree.

## Prerequisites

**Required inventory variables** (example values shown):
```yaml
# Keycloak configuration
keycloak_hostname: auth.example.com       # Hostname for Keycloak service (replace with your domain)
keycloak_url: https://auth.example.com    # Full URL to Keycloak instance
keycloak_realm: thinkube                   # Platform realm name
keycloak_namespace: keycloak               # Namespace for Keycloak deployment

# Admin user configuration
admin_username: admin                      # Administrator username
admin_first_name: Admin                    # Administrator first name
admin_last_name: User                      # Administrator last name
admin_email: admin@example.com            # Administrator email (replace with your email)

# Domain and ingress configuration
domain_name: example.com                   # Base domain for certificate lookup (replace with your domain)
primary_ingress_ip_octet: 200              # For hostAliases configuration
zerotier_subnet_prefix: 10.200.0.         # Network prefix for IP construction (or use network_cidr for local mode)

# Realm display name
thinkube_applications_displayname: "Thinkube Platform"  # Or customize for your platform
```

**Environment variables**:
- `ADMIN_PASSWORD`: Keycloak admin password (required)

**Required infrastructure**:
1. PostgreSQL database server (creates `keycloak` database automatically)
2. Wildcard TLS certificate in default namespace (from acme-certificates)
3. Primary NGINX ingress controller for HTTPS routing
4. DNS resolution for keycloak_hostname
5. PostgreSQL client tools on control plane node

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all Keycloak deployment playbooks in sequence:
- Imports 10_deploy.yaml - Deploys Keycloak with PostgreSQL backend
- Imports 15_configure_realm.yaml - Configures thinkube realm
- Imports 16_configure_theme.yaml - Deploys custom theme
- Imports 17_configure_discovery.yaml - Configures service discovery

### 10_deploy.yaml
Main deployment playbook that deploys Keycloak identity provider:

- **Database Setup**:
  - Verifies ADMIN_PASSWORD is set
  - Installs postgresql-client package
  - Creates `keycloak` database in PostgreSQL if not exists

- **Namespace and Certificate**:
  - Creates `keycloak` namespace
  - Copies wildcard certificate from default namespace as `keycloak-tls-secret`
  - Includes cert-manager annotations for reference

- **Keycloak Service**:
  - Creates ClusterIP service exposing:
    - Port 8080 (HTTP)
    - Port 9000 (health endpoints)

- **Keycloak Deployment**:
  - Deploys Keycloak 26.1.0 from Quay.io
  - Production mode (`start` command, NOT development mode)
  - PostgreSQL backend: `jdbc:postgresql://postgresql-official.postgres.svc.cluster.local:5432/keycloak`
  - Edge proxy mode for TLS termination at ingress
  - Hostname strict mode enabled
  - Health endpoints enabled on port 9000
  - HostAliases for proper hostname resolution (ingress IP)
  - Probes: readiness (30s initial, 10s period), liveness (60s initial, 30s period)

- **Ingress Configuration**:
  - NGINX ingress with TLS termination
  - IngressClass: nginx
  - Proxy settings: body size 2500m, buffer sizes 12k/24k, timeouts 180s
  - Force SSL redirect enabled

- **Admin User Management**:
  - Waits for Keycloak pod to be ready (300s timeout)
  - Tests DNS resolution for keycloak_hostname
  - Waits for Keycloak API availability
  - Creates permanent admin user (configured via admin_username) via Keycloak REST API
  - Assigns admin role to permanent user
  - **Note**: Bootstrap admin user (username: `admin`) expires after 2 hours

### 15_configure_realm.yaml
Realm configuration playbook that configures the platform realm:

- Creates the "thinkube" realm (or custom realm from `keycloak_realm` variable)
- Configures realm settings for platform integration
- Enables unmanaged attributes policy for Kubernetes integration
- Creates cluster-admins group
- Sets up initial admin user with proper group membership

### 16_configure_theme.yaml
Optional theme customization playbook that deploys custom branding:

- Deploys custom Thinkube theme for login pages
- Theme files located in `ansible/40_thinkube/core/keycloak/theme/`
- Copies theme files to Keycloak pod
- Restarts Keycloak to apply theme changes
- Re-run after editing theme files to deploy updates

### 17_configure_discovery.yaml
Service discovery configuration playbook that creates discovery metadata:

- **Service Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in keycloak namespace
  - Labels: `thinkube.io/managed`, `thinkube.io/service-type: core`, `thinkube.io/service-name: keycloak`
  - Defines service metadata:
    - Display name: "Keycloak"
    - Category: security
    - Icon: /icons/tk_dashboard.svg
  - Endpoint configuration:
    - Web UI: https://auth.{{ domain_name }}
    - Health URL: https://auth.{{ domain_name }}/realms/master
    - API: OpenID Connect endpoint at https://auth.{{ domain_name }}
  - Dependency: PostgreSQL
  - Scaling configuration: Deployment `keycloak` in keycloak namespace, min 1 replica

## Usage

### Deploy Keycloak

```bash
export ADMIN_PASSWORD='your-secure-password'
ansible-playbook -i inventory/inventory.yaml ansible/40_thinkube/core/keycloak/10_deploy.yaml
```

### Configure Kubernetes Realm

```bash
ansible-playbook -i inventory/inventory.yaml ansible/40_thinkube/core/keycloak/15_configure_realm.yaml
```

### Configure Custom Theme (Optional)

```bash
ansible-playbook -i inventory/inventory.yaml ansible/40_thinkube/core/keycloak/16_configure_theme.yaml
```

This will deploy a custom Thinkube theme for the login pages. To customize:
1. Edit files in `ansible/40_thinkube/core/keycloak/theme/`
2. Re-run the playbook to deploy changes

### Test Deployment

```bash
ansible-playbook -i inventory/inventory.yaml ansible/40_thinkube/core/keycloak/18_test.yaml
```

### Rollback

```bash
ansible-playbook -i inventory/inventory.yaml ansible/40_thinkube/core/keycloak/19_rollback.yaml -e confirm_rollback=true
```

## Notes

- Deployed in **production mode** (`start` command, not `start-dev`)
- Bootstrap admin user (`admin`) expires after 2 hours - use permanent admin (configured via `admin_username`) for long-term access
- Uses NGINX ingress controller with edge proxy mode for TLS termination
- Wildcard TLS certificate from acme-certificates (Let's Encrypt)
- PostgreSQL backend provides persistent data storage
- Health endpoints exposed on port 9000 for monitoring
- Admin password is shared between Keycloak and PostgreSQL
- Realm configuration enables unmanaged attributes for Kubernetes integration

## Security Considerations

- **Bootstrap Admin**: Temporary `admin` user expires in 2 hours - delete manually after verifying permanent admin access
- **Permanent Admin**: Use the account configured in `admin_username` for long-term administration
- **TLS Enforcement**: All connections use HTTPS with Let's Encrypt certificates
- **Password Security**: ADMIN_PASSWORD must be set via environment variable
- **Database Security**: Keycloak database uses same admin credentials as PostgreSQL
- **Certificate Management**: Wildcard certificate automatically renewed by acme-certificates
- **Proxy Headers**: Configured to trust X-Forwarded headers from ingress controller

## Integration

After deployment, Keycloak can be integrated with:
- Kubernetes API server for authentication
- Harbor registry for user management
- AWX for access control
- Other platform services requiring SSO