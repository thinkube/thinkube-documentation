# DNS Server Component

This component deploys BIND9 as the network-wide DNS server for Thinkube infrastructure, providing DNS resolution for all platform services.

## Overview

The Thinkube platform uses two separate DNS systems:

1. **CoreDNS** (Kubernetes internal)
   - Handles `*.cluster.local` domains
   - Provides service discovery for pods
   - Runs as part of k8s-snap DNS
   - ClusterIP: 10.152.183.10

2. **BIND9** (Network DNS) - THIS COMPONENT
   - Handles `*.thinkube.com` domains
   - Forwards external queries to public DNS
   - Provides DNS for all network clients
   - LoadBalancer IP: 10.200.0.205

## Why Separate DNS Systems?

- **Separation of concerns**: Each DNS server handles what it's designed for
- **Reliability**: Kubernetes DNS issues don't affect network DNS and vice versa
- **Proper recursion**: BIND9 handles recursive queries correctly for external domains
- **Proven pattern**: This architecture worked successfully in the pre-LXD setup

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster infrastructure
- MetalLB load balancer (enabled in k8s deployment) - Provides external IP for DNS service

**Required by** (which components depend on this):
- coredns (deployment order #10) - Kubernetes DNS configuration
- All services - Network-wide DNS resolution
- Node DNS configuration (15_configure_node_dns.yaml)

**Deployment order**: #9

See [Deployment Dependency Graph](https://github.com/thinkube/thinkube-documentation/blob/main/architecture/deployment-dependency-graph.md) for complete dependency tree.

## Prerequisites

### Network Configuration
- ZeroTier or local network configured
- DNS external IP address assigned from MetalLB IP range
- Ingress IP addresses configured

### Inventory Variables
From `inventory/group_vars/k8s.yml`:
```yaml
domain_name: thinkube.com                # Base domain for all services
dns_external_ip_octet: 205               # Last octet for DNS LoadBalancer IP
primary_ingress_ip_octet: 200            # Last octet for main ingress
secondary_ingress_ip_octet: 201          # Last octet for Knative ingress
network_mode: overlay                     # or 'local'
```

## Playbooks

### 10_deploy.yaml
Main deployment playbook that configures network-wide DNS:

- **Container Image Build**:
  - Installs Podman for container image building
  - Builds custom BIND9 container image based on Ubuntu 24.04
  - Exports image to tar and imports into k8s-snap containerd at `localhost/thinkube-bind9:latest`
  - Image includes bind9, bind9-utils, dnsutils packages

- **Namespace and Configuration**:
  - Creates `dns-system` namespace
  - Generates BIND9 named.conf with:
    - Forwarders to 8.8.8.8 and 8.8.4.4 for external DNS
    - Recursion enabled for all clients
    - DNSSEC validation disabled
  - Creates zones.conf for domain configurations
  - Creates ConfigMap `bind9-config` with named.conf and zones.conf

- **DNS Zone Configuration**:
  - Main domain zone (`domain_name`):
    - Wildcard `*` → primary ingress IP (for all services)
    - Specific records for DNS server and all cluster nodes (hostname → ZeroTier IP)
  - Knative domain zone (`kn.domain_name`):
    - Wildcard `*` → secondary ingress IP (for Knative services)
  - Creates ConfigMap `bind9-zones` with zone files

- **BIND9 Deployment**:
  - Deploys single-replica Deployment pinned to control plane node
  - Image pull policy: Never (uses locally imported image)
  - Mounts bind9-config ConfigMap to `/etc/bind/named.conf` and `/etc/bind/zones.conf`
  - Mounts bind9-zones ConfigMap to `/etc/bind/zones/`
  - EmptyDir volume for `/var/cache/bind`
  - Resource limits: 256Mi-512Mi memory, 100m-500m CPU
  - Liveness/readiness probes using `dig` command to test DNS resolution

- **Services**:
  - LoadBalancer service `bind9-external`:
    - External IP from `dns_external_ip_octet` (e.g., 10.200.0.205)
    - Exposes DNS on port 53 UDP/TCP for network-wide access
  - ClusterIP service `bind9-internal`:
    - Internal cluster access at `bind9-internal.dns-system.svc.cluster.local`
    - Port 53 UDP/TCP

- **Verification**:
  - Waits for deployment to be ready
  - Waits for LoadBalancer IP assignment
  - Tests DNS resolution for external domains (google.com) from BIND9 pod

## Deployment

```bash
cd ~/thinkube
./scripts/run_ansible.sh ansible/40_thinkube/core/dns-server/10_deploy.yaml
```

## Configuration

The BIND9 server is configured with:

- **Wildcard domains**:
  - `*.thinkube.com` → 10.200.0.200 (primary ingress)
  - `*.kn.thinkube.com` → 10.200.0.201 (secondary ingress)

- **Specific records**:
  - `dns.thinkube.com` → 10.200.0.205
  - Node hostnames → Their ZeroTier IPs

- **Forwarding**:
  - External queries forwarded to 8.8.8.8, 8.8.4.4
  - Recursion enabled for all clients

## Testing

```bash
# Run test playbook
./scripts/run_ansible.sh ansible/40_thinkube/core/dns-server/18_test.yaml

# Manual tests
dig @10.200.0.205 test.thinkube.com
dig @10.200.0.205 google.com
```

## Troubleshooting

### DNS not responding

1. Check if BIND9 pod is running:
   ```bash
   kubectl get pods -n dns-system
   ```

2. Check BIND9 logs:
   ```bash
   kubectl logs -n dns-system deploy/bind9
   ```

3. Verify LoadBalancer IP is assigned:
   ```bash
   kubectl get svc -n dns-system bind9-external
   ```

### Wrong IP resolution

1. Check ConfigMaps:
   ```bash
   kubectl describe cm -n dns-system bind9-zones
   ```

2. Restart BIND9:
   ```bash
   kubectl rollout restart -n dns-system deploy/bind9
   ```

## Rollback

If needed, remove the DNS server:

```bash
./scripts/run_ansible.sh ansible/40_thinkube/core/dns-server/19_rollback.yaml
```

## Integration with Other Components

After deploying BIND9, update node DNS configuration:

```bash
./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/coredns/15_configure_node_dns.yaml
```

This configures all nodes to use BIND9 for DNS resolution.