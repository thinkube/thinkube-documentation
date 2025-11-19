# ADR-001: Kubernetes Distribution Selection (k8s-snap)

**Status**: Accepted
**Date**: 2025-11
**Deciders**: Platform Team
**Technical Story**: Selection of Kubernetes distribution for Thinkube platform

## Context

The Thinkube platform was initially deployed on MicroK8s but required migration to support **Cilium CNI**, which provides significantly better stability than Calico and enables future multi-cluster networking capabilities critical for the platform roadmap.

The platform requires a Kubernetes distribution that:
- **Supports Cilium CNI** for stable networking and future multi-cluster support
- Runs on single-node and multi-node configurations
- Supports GPU workloads (NVIDIA GPUs)
- Provides easy installation and maintenance
- Works well in homelab/edge environments
- Uses 100% upstream Kubernetes (no vendor modifications)

## Decision

We will use **Canonical Kubernetes (k8s-snap)** as the standard Kubernetes distribution for Thinkube.

k8s-snap is installed via:
```bash
sudo snap install k8s --classic --channel=1.34/stable
```

## Consequences

### Positive
- **Cilium CNI support**: Built-in Cilium CNI provides better stability than Calico and enables future multi-cluster networking
- **Standard Kubernetes**: 100% upstream Kubernetes, no vendor-specific modifications
- **Built-in components**: Includes Cilium, MetalLB, CoreDNS, OpenEBS, Metrics Server by default
- **GPU support**: Works seamlessly with NVIDIA GPU Operator
- **Future-proof networking**: Cilium enables multi-cluster mesh, service mesh, and advanced network policies
- **Easy management**: Snap-based installation with automatic updates
- **Multi-node ready**: Simple worker node joining process
- **Production-ready**: Canonical support available if needed

### Negative
- **Snap dependency**: Requires snapd on the host system
- **Less addons**: Fewer built-in addons compared to MicroK8s (but we deploy everything via Helm anyway)
- **Migration effort**: Required migrating from MicroK8s (110+ references across 35 files, 40-60 hour effort)

### Neutral
- All platform services deployed via Helm charts (not distribution-specific addons)
- Standard kubectl and Helm tooling works identically
- Storage provided by OpenEBS instead of hostpath

## Alternatives Considered

### Alternative 1: MicroK8s (Previous Platform)
**Description**: Lightweight Kubernetes from Canonical with many built-in addons
**Pros**:
- Rich addon ecosystem (DNS, storage, Helm, dashboard, MetalLB built-in)
- Proven track record in edge/IoT deployments
- Easy single-command setup

**Cons**:
- **No Cilium support**: Uses Calico CNI which has stability issues:
  - Authorization failures requiring server restarts
  - BGP peering flakes
  - iptables rule corruption with thousands of rules
  - Conntrack table exhaustion
  - NetworkManager interference
- **No multi-cluster roadmap**: Calico doesn't provide the multi-cluster mesh capabilities needed for future platform features
- Non-standard API server configuration
- Addon-based architecture less flexible than Helm-based deployments
- Path references (`/var/snap/microk8s/`) scattered throughout codebase

**Rejected because**: Cannot support Cilium CNI, which is essential for network stability (avoiding Calico auth failures and restarts) and future multi-cluster capabilities

### Alternative 2: K3s
**Description**: Lightweight Kubernetes from Rancher
**Pros**:
- Very small footprint (< 100MB)
- Built-in storage and load balancer
- Popular in edge deployments

**Cons**:
- Rancher/SUSE ecosystem lock-in
- Non-standard directory structure
- Some Kubernetes features disabled by default

**Rejected because**: Canonical k8s-snap provides full Kubernetes features with Canonical support alignment

### Alternative 3: Kubeadm
**Description**: Official Kubernetes cluster bootstrapping tool
**Pros**:
- Official Kubernetes project
- Maximum flexibility
- Standard tooling

**Cons**:
- Manual CNI, storage, load balancer setup required
- More complex to maintain
- Overkill for single-node deployments

**Rejected because**: Too complex for homelab/edge use cases; k8s-snap provides better out-of-box experience

## Implementation Notes

### Migration from MicroK8s
The platform was migrated from MicroK8s to k8s-snap, requiring:
- Updating all `microk8s.kubectl` → `kubectl` references
- Updating all `microk8s.helm3` → `helm` references
- Updating config paths from `/var/snap/microk8s/` to `/var/snap/k8s/`
- Testing all 45 platform components after migration

### Component Compatibility
All platform components work identically on k8s-snap:
- GPU Operator for NVIDIA GPUs
- NGINX Ingress Controller
- acme.sh for TLS certificates
- Harbor container registry
- All core and optional services

## References

- [Canonical Kubernetes Documentation](https://documentation.ubuntu.com/canonical-kubernetes/)
- [k8s-snap GitHub Repository](https://github.com/canonical/k8s-snap)
- [Platform Component Matrix](../operations/component-matrix.md)
- [MicroK8s Migration Analysis](../archive/microk8s-to-k8s-migration-analysis.md) (if moved to archive)

---

**Last Updated**: 2025-11-19
**Supersedes**: None
**Superseded By**: None
