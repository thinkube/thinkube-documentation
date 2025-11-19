# Ingress Controllers

This component deploys dual NGINX Ingress Controllers for the Thinkube infrastructure to handle incoming traffic routing.

## Overview

The deployment includes:
- **Primary Ingress Controller**: For general services (*.thinkube.com) in `ingress` namespace
- **Secondary Ingress Controller**: For Knative services (*.kn.thinkube.com) in `ingress-kn` namespace

Both controllers use NGINX Ingress Controller deployed via Helm with MetalLB for LoadBalancer services. Wildcard TLS certificates are copied from the default namespace (created by acme-certificates) to both ingress namespaces.

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster with MetalLB enabled
- acme-certificates (deployment order #12) - Wildcard TLS certificate in default namespace

**Required by** (which components depend on this):
- All web services - HTTPS ingress routing for platform services
- Knative serving - HTTP/HTTPS routing for serverless workloads

**Deployment order**: #13

See [Deployment Dependency Graph](https://github.com/thinkube/thinkube-documentation/blob/main/architecture/deployment-dependency-graph.md) for complete dependency tree.

## Architecture

```
                    Internet
                        |
                   DNS Resolution
                    /         \
           Primary IP      Secondary IP
                |               |
        Primary Ingress    Secondary Ingress
        (nginx class)     (nginx-kn class)
                |               |
        General Services   Knative Services
```

## Prerequisites

**Required inventory variables**:
```yaml
# Network configuration
domain_name: thinkube.com
network_mode: overlay  # or 'local'

# IP octets for ingress controllers
primary_ingress_ip_octet: 200      # Last octet for primary ingress LoadBalancer IP
secondary_ingress_ip_octet: 201    # Last octet for secondary ingress LoadBalancer IP

# Namespace configuration
ingress_namespace: ingress          # Primary ingress namespace
ingress_kn_namespace: ingress-kn    # Secondary ingress namespace (Knative)

# IngressClass names
primary_ingress_class: nginx        # Primary controller (set as default)
secondary_ingress_class: nginx-kn   # Secondary controller

# Service names
primary_ingress_service: primary-ingress-ingress-nginx-controller
```

**Required infrastructure**:
1. Kubernetes cluster with MetalLB enabled (k8s playbook)
2. Wildcard TLS certificate in default namespace (acme-certificates playbook)
3. DNS resolution configured (coredns and dns-server playbooks)
4. Network connectivity between nodes

## Playbooks

### 10_deploy.yaml
Main deployment playbook that configures dual NGINX ingress controllers:

- **Helm Repository Setup**:
  - Adds ingress-nginx Helm repository (https://kubernetes.github.io/ingress-nginx)
  - Updates Helm repositories

- **MetalLB Verification**:
  - Checks if MetalLB is installed (fails if metallb-system namespace doesn't exist)

- **Play 1: Primary Ingress Controller Deployment**:
  - Creates `ingress` namespace
  - Generates Helm values file (`/tmp/primary-ingress-values.yaml`) with:
    - IngressClass `nginx` (set as default)
    - LoadBalancer service with external IP from `primary_ingress_ip_octet`
    - Default TLS certificate: `ingress/ingress-tls-secret`
    - SSL passthrough enabled
    - TCP service mappings:
      - PostgreSQL: port 5432 → postgres/postgresql-official:5432
      - Gitea SSH: port 2222 → gitea/gitea:22
      - NATS: port 4222 → nats/nats:4222
      - Valkey: port 6379 → valkey/valkey:6379
      - ClickHouse: port 9000 → clickhouse/clickhouse-clickhouse:9000
    - Prometheus metrics enabled on port 10254
  - Deploys via Helm (release: `primary-ingress`)
  - Waits for LoadBalancer IP assignment and verification
  - Deletes conflicting IngressClass `public` if exists
  - Patches IngressClass annotation to mark `nginx` as default
  - Patches deployment to publish service IP
  - Restarts pods to apply configuration

- **Play 2: Secondary Ingress Controller Deployment**:
  - Creates `ingress-kn` namespace
  - Generates Helm values file (`/tmp/secondary-ingress-values.yaml`) with:
    - IngressClass `nginx-kn` (NOT default)
    - LoadBalancer service with external IP from `secondary_ingress_ip_octet`
    - Default TLS certificate: `ingress-kn/ingress-kn-tls-secret`
    - SSL passthrough enabled
    - Prometheus metrics enabled on port 10254
  - Deploys via Helm (release: `secondary-ingress`)
  - Waits for LoadBalancer IP assignment and verification
  - Patches deployment to publish service IP
  - Restarts pods to apply configuration

- **Play 3: Wildcard Certificate Distribution**:
  - Gets wildcard certificate from default namespace (`{{ domain_name | replace('.', '-') }}-tls`)
  - Creates `ingress-tls-secret` in primary ingress namespace with wildcard certificate
  - Creates `ingress-kn-tls-secret` in secondary ingress namespace with wildcard certificate
  - Labels secrets with `app.kubernetes.io/name: wildcard-certificate`
Comprehensive test playbook that verifies:
- MetalLB namespace exists
- Both ingress namespaces exist (`ingress`, `ingress-kn`)
- Primary and secondary ingress controller pods are Running
- Services have correct external LoadBalancer IPs assigned
- IngressClass resources are configured correctly
- Primary IngressClass `nginx` is set as default
- TLS certificate secrets exist in both namespaces
- Health endpoints are responding

### 19_rollback.yaml
Cleanup playbook that:
- Uninstalls Helm releases (primary-ingress, secondary-ingress)
- Deletes IngressClass resources (`nginx`, `nginx-kn`)
- Removes namespaces (`ingress`, `ingress-kn`)
- Cleans up temporary Helm values files

## Configuration

The playbook dynamically constructs LoadBalancer IPs from inventory variables:

```yaml
# Subnet prefix is determined by network_mode:
# - overlay mode: uses zerotier_subnet_prefix (e.g., "10.200.0.")
# - local mode: uses network_cidr prefix (e.g., "192.168.1.")

primary_ingress_ip: "{{ subnet_prefix }}{{ primary_ingress_ip_octet }}"
secondary_ingress_ip: "{{ subnet_prefix }}{{ secondary_ingress_ip_octet }}"

# Example with overlay mode (zerotier_subnet_prefix: "10.200.0."):
# primary_ingress_ip_octet: 200 → LoadBalancer IP: 10.200.0.200
# secondary_ingress_ip_octet: 201 → LoadBalancer IP: 10.200.0.201
```

**TCP Service Mappings (Primary Ingress)**:
The primary ingress controller includes TCP port forwarding for non-HTTP services:
- Port 5432 → `postgres/postgresql-official:5432`
- Port 2222 → `gitea/gitea:22`
- Port 4222 → `nats/nats:4222`
- Port 6379 → `valkey/valkey:6379`
- Port 9000 → `clickhouse/clickhouse-clickhouse:9000`

**IngressClass Resources**:
- `nginx` - Primary ingress class (default for all Ingress resources)
- `nginx-kn` - Secondary ingress class (for Knative and specialized workloads)

## Usage

### Deploy Ingress Controllers
```bash
./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/ingress/10_deploy.yaml
```

### Test Deployment
```bash
./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/ingress/18_test.yaml
```

### Rollback (if needed)
```bash
./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/ingress/19_rollback.yaml
```

## DNS Configuration

DNS is automatically configured by the dns-server playbook:
- Primary services: `*.thinkube.com` → Primary ingress LoadBalancer IP
- Knative services: `*.kn.thinkube.com` → Secondary ingress LoadBalancer IP

The BIND9 DNS server (deployed by dns-server playbook) creates wildcard DNS records pointing to the ingress controller LoadBalancer IPs.

## TLS Certificate Integration

The ingress controllers use wildcard TLS certificates created by acme-certificates:

1. **Certificate Source**: The acme-certificates playbook creates a wildcard certificate covering:
   - `thinkube.com` (base domain)
   - `*.thinkube.com` (wildcard)
   - `*.kn.thinkube.com` (Knative subdomain)

2. **Certificate Distribution**: The ingress deployment playbook (Play 3) copies the certificate from the default namespace to both ingress namespaces:
   - `default/thinkube-com-tls` → `ingress/ingress-tls-secret`
   - `default/thinkube-com-tls` → `ingress-kn/ingress-kn-tls-secret`

3. **Default TLS**: Both ingress controllers are configured with `default-ssl-certificate` argument pointing to their namespace-specific certificate secret, providing automatic TLS for all ingress resources.

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n ingress
kubectl get pods -n ingress-kn
```

### View Service External IPs
```bash
kubectl get svc -n ingress
kubectl get svc -n ingress-kn
```

### Check IngressClass Configuration
```bash
kubectl get ingressclass
```

### View Controller Logs
```bash
# Primary controller
kubectl logs -n ingress -l app.kubernetes.io/name=ingress-nginx

# Secondary controller
kubectl logs -n ingress-kn -l app.kubernetes.io/name=ingress-nginx
```

### Verify MetalLB Configuration
```bash
kubectl get configmap -n metallb-system config -o yaml
```

## Next Steps

After successful deployment:
1. Verify DNS resolution for `*.thinkube.com` and `*.kn.thinkube.com`
2. Deploy services with Ingress resources using appropriate IngressClass
3. Monitor ingress controller metrics (exposed on port 10254 with Prometheus annotations)
4. For Knative services, use `ingressClassName: nginx-kn` in Ingress resources

## Migration Notes

This component migrates from `thinkube-core/playbooks/core/40_setup_ingress.yaml` with:
- Updated to use k8s-snap kubectl and helm binaries
- Removed hardcoded IPs and domains
- Simplified configuration using inventory variables
- Removed cert validation dependencies (handled by cert-manager)
- Updated to use current ingress-nginx Helm chart