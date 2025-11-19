# ADR-004: Container Registry (Harbor)

**Status**: Accepted
**Date**: Unknown
**Deciders**: Platform Team
**Technical Story**: Self-hosted container registry for platform images and user applications

## Context

Docker Hub introduced restrictive rate limits (100 pulls/6 hours for anonymous users, 200 pulls/6 hours for free accounts) and complex licensing policies that make it unsuitable for production platform deployments. A Kubernetes platform pulling images across multiple nodes can easily exhaust these limits during deployments.

Thinkube platform needs a self-hosted container registry to:
- **Avoid Docker Hub rate limits** - Mirror frequently-used public images locally
- **Avoid Docker licensing restrictions** - No Docker Desktop or Docker Engine dependencies
- Store custom-built platform images (base images, Jupyter, code-server)
- Host user application images
- Support CI/CD workflows with robot accounts
- Provide vulnerability scanning and image signing
- Integrate with platform SSO (Keycloak)

Requirements:
- OCI/Docker v2 compatibility
- Image mirroring from public registries (Docker Hub, Quay, GCR, etc.)
- Keycloak OIDC integration
- Robot accounts for CI/CD
- Vulnerability scanning (Trivy)
- Self-hosted (no cloud dependency)
- Works with Podman (no Docker required)

## Decision

Use **Harbor** as the enterprise container registry for the Thinkube platform.

Deployed as Component #16 at: `https://registry.{domain_name}` (or `harbor.{domain_name}`)

## Consequences

### Positive
- **No rate limits**: Eliminates Docker Hub's 100-200 pulls/6h limits by mirroring images locally
- **No Docker licensing issues**: Works with Podman, no Docker Desktop or Docker Engine required
- **Faster deployments**: Local registry reduces external network dependency
- **Vulnerability scanning**: Built-in Trivy scanner for CVE detection
- **Image signing**: Notary support for content trust
- **Keycloak integration**: Native OIDC authentication
- **Robot accounts**: Automated CI/CD access with scoped permissions
- **Policy enforcement**: Block images with vulnerabilities
- **PostgreSQL backend**: Integrates with platform database (#14)
- **Proven at scale**: CNCF graduated project, production-ready

### Negative
- **Resource usage**: Multiple components (core, portal, registry, scanner, database)
- **Complexity**: More features = more configuration
- **Storage requirements**: Images can grow large
- **Slower than DockerHub**: Self-hosted means local network speeds only

### Neutral
- Supports Docker and OCI image formats
- Compatible with all Kubernetes clusters
- Standard Docker CLI workflows

## Platform Integration

Harbor stores platform-critical images:

**Base Images** (`library/` project):
- `ubuntu-toolkit` - Base Ubuntu with common tools
- `python-base` - Python environments
- `cuda-base` - NVIDIA CUDA support

**Custom Images**:
- `jupyterlab-*` - JupyterHub notebook images (multiple variants)
- `code-server` - VS Code browser IDE
- `litellm`, `langfuse`, `cvat`, etc. - Optional service images

**Mirrored Images**:
- Public images cached locally for faster deployments
- Avoids Docker Hub rate limits during deployments

## Image Build Workflow

Harbor-images playbooks handle image building and mirroring:
- **13_mirror_public_images.yaml**: Mirrors 50+ essential public images from external registries
- **14_build_base_images.yaml**: Builds 12+ custom base images with pre-installed dependencies
- **15_build_jupyter_images.yaml**: Builds 3 Jupyter variants (ml-gpu, fine-tuning, agent-dev)
- **16_build_codeserver_image.yaml**: Builds code-server image (VS Code browser IDE with 31 CLI tools)

All image operations use **Podman** (daemonless, rootless container engine installed by playbook 11_install_podman.yaml).

## Alternatives Considered

### Alternative 1: Docker Hub
**Description**: Public container registry (docker.io)
**Pros**:
- No hosting required
- Fast global CDN
- Large ecosystem of public images

**Cons**:
- **Restrictive rate limits**: 100 pulls/6h anonymous, 200 pulls/6h free accounts
- **Licensing complexity**: Docker Desktop licensing, Docker Engine restrictions
- **No private images** on free tier
- **Cloud dependency**: Requires internet connectivity for all deployments
- **Kubernetes unfriendly**: Multi-node clusters quickly exhaust rate limits
- **No vulnerability scanning** on free tier
- **No SSO integration**

**Rejected because**: Rate limits make it unsuitable for Kubernetes deployments. A single deployment across 3 nodes can easily require 50+ image pulls, exhausting limits quickly. Docker licensing adds complexity for enterprise use.

### Alternative 2: GitLab Container Registry
**Description**: Registry built into GitLab
**Pros**:
- Integrated with Git workflow
- Good CI/CD integration

**Cons**:
- Requires full GitLab installation (heavier than Harbor)
- Less focus on registry features vs. Git features
- We already chose Gitea for Git hosting

**Rejected because**: Harbor provides better registry-specific features; Gitea is our Git solution

### Alternative 3: Quay
**Description**: Red Hat's container registry
**Pros**:
- Enterprise features
- Good security scanning

**Cons**:
- Red Hat ecosystem focus
- Less community support than Harbor
- More complex setup

**Rejected because**: Harbor has better community, CNCF backing, and simpler deployment

### Alternative 4: Simple Docker Registry (distribution/distribution)
**Description**: Official Docker registry v2
**Pros**:
- Minimal footprint
- Simple setup
- Fast

**Cons**:
- No UI
- No authentication built-in
- No vulnerability scanning
- No robot accounts
- No replication

**Rejected because**: Too basic for enterprise platform needs

## Security Features

Harbor provides:
- **Trivy scanner**: CVE detection in images
- **Notary**: Image signing and verification
- **RBAC**: Project-level and system-level permissions
- **Audit logs**: Track who pushed/pulled what
- **Quota management**: Prevent storage exhaustion
- **Content trust**: Only allow signed images

## References

- [Harbor Documentation](https://goharbor.io/docs/)
- [Harbor Component README](../components/16_core_harbor_README.md)
- [Custom Images Plan](../development/container-images-guide.md)
- [CNCF Harbor Project](https://www.cncf.io/projects/harbor/)

---

**Last Updated**: 2025-11-19
**Supersedes**: None
**Superseded By**: None
