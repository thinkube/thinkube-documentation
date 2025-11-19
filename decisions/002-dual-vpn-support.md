# ADR-002: Dual VPN Support (ZeroTier + Tailscale)

**Status**: Accepted
**Date**: 2025-10
**Deciders**: Platform Team
**Technical Story**: Support for both ZeroTier and Tailscale VPN providers

## Context

Thinkube platform needs secure remote access for:
- Remote cluster management
- Developer access to services
- Multi-site connectivity

Different users have different VPN preferences and requirements:
- DGX Spark systems may have Tailscale pre-installed
- Existing users may prefer ZeroTier
- Corporate environments may mandate specific VPN solutions

## Decision

Support **BOTH ZeroTier and Tailscale** as first-class VPN providers in the Thinkube platform.

Users can choose during installation:
```yaml
network_mode: overlay
overlay_provider: zerotier  # or tailscale
```

## Consequences

### Positive
- **User choice**: Flexibility to use preferred VPN solution
- **DGX Spark alignment**: Native support for systems with Tailscale pre-installed
- **Migration path**: Easy switching between VPN providers
- **Vendor independence**: Not locked into single VPN provider

### Negative
- **Maintenance burden**: Must maintain playbooks for both providers
- **Testing complexity**: Need to test both configurations
- **Documentation overhead**: Dual documentation paths
- **Code duplication**: Some networking logic duplicated

### Neutral
- Only one VPN provider active per deployment
- Similar configuration patterns between providers
- Both use overlay networking concepts

## Implementation Details

### ZeroTier Support
- Playbook: `ansible/30_networking/10_setup_zerotier.yaml`
- Network ID required
- API token for automated management
- Layer 2 bridged networking

### Tailscale Support
- Playbook: `ansible/30_networking/11_setup_tailscale.yaml`
- OAuth credentials or auth key
- ACL-based access control
- MagicDNS support

### Shared Components
- MetalLB IP allocation from VPN subnet
- Ingress Controller external IP configuration
- DNS integration (both support custom DNS)

## Alternatives Considered

### Alternative 1: ZeroTier Only
**Description**: Single VPN provider (ZeroTier)
**Pros**:
- Simpler maintenance
- Less code to maintain
- Single testing path

**Cons**:
- Vendor lock-in
- No DGX Spark alignment
- Forces VPN choice on users

**Rejected because**: Flexibility and DGX Spark alignment more valuable than simplicity

### Alternative 2: WireGuard
**Description**: Self-hosted VPN solution
**Pros**:
- No third-party dependency
- Maximum control
- Open source

**Cons**:
- Manual key management
- No central control plane
- Harder to set up for non-technical users
- No built-in DNS/discovery

**Rejected because**: Managed VPN services provide better user experience for homelab scenarios

### Alternative 3: Cloudflare Tunnel
**Description**: Cloudflare Zero Trust tunnel
**Pros**:
- No VPN needed
- Built-in security
- Global network

**Cons**:
- Requires Cloudflare account
- Cloud dependency
- May not work for all use cases (e.g., GPU workloads)

**Rejected because**: VPN provides more direct connectivity for low-latency workloads

## Complexity Assessment

From internal analysis, Tailscale support adds:
- **8-12 hours development**: Playbook creation, testing
- **Low runtime complexity**: Similar to ZeroTier once configured
- **High strategic value**: DGX Spark alignment critical for business model

## References

- [ZeroTier Documentation](https://docs.zerotier.com/)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Networking Component README](../components/04_core_networking_README.md)
- [Tailscale Support Complexity Assessment](../archive/tailscale-support-analysis.md) (if moved to archive)

---

**Last Updated**: 2025-11-19
**Supersedes**: None
**Superseded By**: None
