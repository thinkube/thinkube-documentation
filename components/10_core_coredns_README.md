# CoreDNS Configuration Component

This component configures CoreDNS for Kubernetes internal DNS resolution and coordinates with the BIND9 DNS server for platform-wide domain resolution.

## Overview

CoreDNS is the built-in DNS server for k8s-snap that handles Kubernetes internal DNS. This playbook configures it to:
- Handle internal Kubernetes service resolution (*.cluster.local)
- Enable hairpin routing for ingress controllers
- Route Knative service domains to the secondary ingress controller (if installed)
- Forward upstream DNS queries to public DNS (8.8.8.8, 8.8.4.4)
- Configure worker nodes to use BIND9 DNS server for platform domain resolution

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster with CoreDNS
- dns-server (deployment order #9) - BIND9 DNS server for network-wide resolution
- Optional: ingress controllers (for hairpin routing configuration)

**Required by** (which components depend on this):
- acme-certificates - Needs DNS resolution for certificate validation
- All services - Kubernetes internal DNS and domain resolution

**Deployment order**: #10

See [Deployment Dependency Graph](https://github.com/thinkube/thinkube-documentation/blob/main/architecture/deployment-dependency-graph.md) for complete dependency tree.

## Prerequisites

### Required Inventory Variables
- `domain_name`: Base domain (e.g., "thinkube.com")
- `network_mode`: Network mode (`overlay` or `local`)
- `dns_external_ip_octet`: Last octet for BIND9 DNS external IP
- `primary_ingress_ip_octet`: Last octet for primary ingress IP
- `secondary_ingress_ip_octet`: Last octet for secondary ingress IP (Knative)
- `metallb_ip_start_octet` and `metallb_ip_end_octet`: MetalLB IP range
- `k8s_workers`: Group containing worker nodes

### Conditional Variables
- `zerotier_subnet_prefix`: Required if `network_mode == 'overlay'`
- `network_cidr`: Required if `network_mode == 'local'`

## Playbooks

### 10_deploy.yaml
Main CoreDNS configuration playbook that sets up Kubernetes internal DNS:

- **CoreDNS Verification**:
  - Verifies CoreDNS deployment exists and is ready (deployed by default in k8s-snap)
  - Confirms DNS is running in kube-system namespace

- **Ingress Controller Detection**:
  - Detects primary ingress controller ClusterIP (`primary-ingress-ingress-nginx-controller` in ingress namespace)
  - Detects secondary ingress controller ClusterIP (`secondary-ingress-ingress-nginx-controller` in ingress-kn namespace)
  - Detects Kourier service IPs if Knative is installed (`kourier` and `kourier-internal` in kourier-system namespace)

- **CoreDNS Configuration**:
  - Generates Corefile from template with ingress controller hairpin routing
  - Creates/updates ConfigMap `ck-dns-coredns` in kube-system namespace
  - Configures DNS forwarding to upstream servers (8.8.8.8, 8.8.4.4)
  - Enables Kubernetes service discovery for cluster.local domain
  - Restarts CoreDNS pods to apply new configuration

- **System Certificates**:
  - Installs ca-certificates package
  - Updates system CA certificates with `update-ca-certificates`
  - Creates ConfigMap `system-certificates` in kube-system namespace with `/etc/ssl/certs/ca-certificates.crt`

- **Worker Node DNS Configuration**:
  - Configures systemd-resolved on worker nodes to use BIND9 DNS
  - Creates `/etc/systemd/resolved.conf.d/coredns-external.conf` with:
    - DNS server: BIND9 external IP from `dns_external_ip_octet`
    - Domain forwarding for platform domain
  - Restarts systemd-resolved on all workers

### 15_configure_node_dns.yaml
Node DNS configuration playbook that updates all nodes to use BIND9:

- **systemd-resolved Configuration**:
  - Creates `/etc/systemd/resolved.conf.d/` directory
  - Removes conflicting DNS configuration files (`dns.conf`)
  - Creates `/etc/systemd/resolved.conf.d/10-thinkube.conf` with:
    - Primary DNS: BIND9 at external IP
    - Fallback DNS: 8.8.8.8, 8.8.4.4
    - DNSStubListener enabled
  - Configures both Kubernetes and non-Kubernetes nodes

- **Kubernetes DNS Settings**:
  - Creates ConfigMap `lxd-dns-config` in kube-system namespace
  - Contains resolve.conf for Kubernetes pods with:
    - Nameserver: CoreDNS ClusterIP (10.152.183.10)
    - Search domains: default.svc.cluster.local, svc.cluster.local, cluster.local
    - Options: ndots:5

- **Netplan Configuration** (for LXD VMs):
  - Updates `/etc/netplan/50-cloud-init.yaml` to use BIND9
  - Replaces default DNS (8.8.8.8) with BIND9 external IP

- **DNS Verification Service**:
  - Creates systemd service `dns-config-verify.service`
  - Ensures DNS configuration persists after network restart
  - Runs after network-online.target and systemd-resolved.service

- **DNS Testing**:
  - Tests internal cluster.local resolution (for Kubernetes nodes)
  - Tests platform domain resolution
  - Tests external domain resolution (acme-v02.api.letsencrypt.org, github.com)
  - Validates FQDN resolution with trailing dot

## Deployment

1. Deploy CoreDNS configuration:
   ```bash
   cd ~/thinkube
   ./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/coredns/10_deploy.yaml
   ```

2. Test the deployment:
   ```bash
   ./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/coredns/18_test.yaml
   ```

## Functionality

### DNS Routing

The configuration implements:
1. **Kubernetes Internal**: Routes `*.cluster.local` to internal kubernetes DNS
2. **Domain Forwarding**: Forwards `*.thinkube.com` to ZeroTier DNS server
3. **Knative Routing**: Maps `*.kn.thinkube.com` to secondary ingress IP
4. **Hairpin Support**: Enables external access to route back to internal services
5. **External Domain Resolution**: Ensures external domains resolve correctly

### Worker Node Configuration

Worker nodes are configured with:
- systemd-resolved configuration for domain forwarding
- ZeroTier DNS server for domain resolution

## Testing

The test playbook verifies:
- CoreDNS pods are running
- Internal Kubernetes service resolution
- Domain forwarding to ZeroTier DNS
- Knative domain resolution (if installed)
- Worker node DNS resolution

## Rollback

To rollback to default configuration:
```bash
./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/coredns/19_rollback.yaml
```

This will:
- Restore default CoreDNS configuration
- Remove custom DNS forwarding rules
- Reset worker node DNS configuration
- Remove system certificates ConfigMap

## Implementation Notes

This is a migration from `thinkube-core/playbooks/core/50_setup_coredns.yaml` with:
- All hardcoded values moved to inventory variables
- Compliance with variable handling policy
- Fully qualified module names
- Preserved original functionality

## References

- Original playbook: `thinkube-core/playbooks/core/50_setup_coredns.yaml`
- Issue: #39 (CORE-003b: Configure CoreDNS)