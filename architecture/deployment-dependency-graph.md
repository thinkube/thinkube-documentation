# Thinkube Deployment Dependency Graph

This document defines the complete dependency graph for all Thinkube platform components, showing the order in which components must be deployed and their interdependencies.

**Source**: Extracted from `thinkube-installer/frontend/src/pages/deploy.tsx` (lines 155-403)
**Last Updated**: 2025-11-18

## Overview

The Thinkube platform consists of 30 components deployed in 3 phases:
1. **Phase 1**: Initial Setup (4 components) - Environment preparation
2. **Phase 2**: Kubernetes Infrastructure (9 components) - Core infrastructure
3. **Phase 3**: Core Services (17 components) - Platform services

## Visual Dependency Graph

See D2 diagrams in [diagrams/](diagrams/):
- [Full Dependency Graph](diagrams/deployment-dependencies-full.d2) - All 30 components
- [Foundation Components](diagrams/foundation-components.d2) - The 6 critical components

## Deployment Order

### Phase 1: Initial Setup

Components that prepare the environment before Kubernetes installation.

| # | Component | Playbook | Dependencies |
|---|-----------|----------|--------------|
| 1 | env-setup | `ansible/00_initial_setup/20_setup_env.yaml` | None |
| 2 | python-setup | `ansible/40_thinkube/core/infrastructure/00_setup_python_k8s.yaml` | env-setup |
| 3 | github-cli | `ansible/00_initial_setup/40_setup_github_cli.yaml` | python-setup |
| 4 | zerotier OR tailscale | `ansible/30_networking/10_setup_zerotier.yaml`<br>`ansible/30_networking/11_setup_tailscale.yaml` | None |

**Notes**:
- zerotier/tailscale are **optional** (conditional: `networkMode=overlay`)
- python-setup appears twice in deployment (item 2 and 5) - appears to be intentional

### Phase 2: Kubernetes Infrastructure

Core Kubernetes and networking infrastructure.

| # | Component | Playbook | Dependencies | Required By |
|---|-----------|----------|--------------|-------------|
| 5 | setup-python-k8s | `ansible/40_thinkube/core/infrastructure/00_setup_python_k8s.yaml` | env-setup, python-setup | k8s |
| 6 | **k8s** ⭐ | `ansible/40_thinkube/core/infrastructure/k8s/10_install_k8s.yaml` | setup-python-k8s | **ALL** subsequent components |
| 7 | k8s-join-workers | `ansible/40_thinkube/core/infrastructure/k8s/20_join_workers.yaml` | k8s | Worker-scheduled pods |
| 8 | gpu-operator | `ansible/40_thinkube/core/infrastructure/gpu_operator/00_install.yaml` | k8s | GPU workloads |
| 9 | **dns-server** ⭐ | `ansible/40_thinkube/core/infrastructure/dns-server/10_deploy.yaml` | k8s | coredns, all services |
| 10 | **coredns** ⭐ | `ansible/40_thinkube/core/infrastructure/coredns/10_deploy.yaml` | k8s, dns-server | All services (DNS) |
| 11 | coredns-configure-nodes | `ansible/40_thinkube/core/infrastructure/coredns/15_configure_node_dns.yaml` | coredns | Node DNS resolution |
| 12 | **acme-certificates** ⭐ | `ansible/40_thinkube/core/infrastructure/acme-certificates/10_deploy.yaml` | k8s, coredns | **ALL HTTPS services** |
| 13 | **ingress** ⭐ | `ansible/40_thinkube/core/infrastructure/ingress/10_deploy.yaml` | k8s, acme-certificates | **ALL web services** |

**Notes**:
- k8s-join-workers is **optional** (conditional: `hasWorkers=true`)
- gpu-operator is **optional** (conditional: `needsGPUOperator=true`)
- Components marked ⭐ are **foundation components** - most services depend on them

### Phase 3: Core Services

Platform services providing database, authentication, registry, and application functionality.

#### Foundation Services

| # | Component | Playbook | Dependencies | Required By |
|---|-----------|----------|--------------|-------------|
| 14 | **postgresql** ⭐ | `ansible/40_thinkube/core/postgresql/00_install.yaml` | k8s, ingress, acme-certificates | keycloak, harbor, gitea, mlflow, juicefs |
| 15 | **keycloak** ⭐ | `ansible/40_thinkube/core/keycloak/00_install.yaml` | postgresql, ingress, acme-certificates | harbor, thinkube-control, authenticated services |
| 16 | **harbor** ⭐ | `ansible/40_thinkube/core/harbor/00_install.yaml` | postgresql, keycloak, ingress, acme-certificates | Custom images, image builds |

#### Harbor Image Building Chain

| # | Component | Playbook | Dependencies | Required By |
|---|-----------|----------|--------------|-------------|
| 17 | harbor-mirror-images | `ansible/40_thinkube/core/harbor-images/13_mirror_public_images.yaml` | harbor | harbor-build-base |
| 18 | harbor-build-base | `ansible/40_thinkube/core/harbor-images/14_build_base_images.yaml` | harbor, harbor-mirror-images | harbor-build-jupyter, harbor-build-codeserver |
| 19 | harbor-build-jupyter | `ansible/40_thinkube/core/harbor-images/15_build_jupyter_images.yaml` | harbor, harbor-build-base | jupyterhub |
| 20 | harbor-build-codeserver | `ansible/40_thinkube/core/harbor-images/16_build_codeserver_image.yaml` | harbor, harbor-build-base | code-server |

#### Storage Services

| # | Component | Playbook | Dependencies | Required By |
|---|-----------|----------|--------------|-------------|
| 21 | **seaweedfs** ⭐ | `ansible/40_thinkube/core/seaweedfs/00_install.yaml` | k8s | juicefs |
| 22 | juicefs | `ansible/40_thinkube/core/juicefs/00_install.yaml` | seaweedfs, postgresql | Distributed filesystem |

#### CI/CD Services

| # | Component | Playbook | Dependencies |
|---|-----------|----------|--------------|
| 23 | argo-workflows | `ansible/40_thinkube/core/argo-workflows/00_install.yaml` | k8s, ingress, acme-certificates |
| 24 | argocd | `ansible/40_thinkube/core/argocd/00_install.yaml` | k8s, ingress, acme-certificates |

#### Development Tools

| # | Component | Playbook | Dependencies |
|---|-----------|----------|--------------|
| 25 | devpi | `ansible/40_thinkube/core/devpi/00_install.yaml` | k8s, ingress, acme-certificates |
| 26 | gitea | `ansible/40_thinkube/core/gitea/00_install.yaml` | postgresql, ingress, acme-certificates |
| 27 | code-server | `ansible/40_thinkube/core/code-server/00_install.yaml` | harbor, harbor-build-codeserver, ingress, acme-certificates |

#### ML/AI Services

| # | Component | Playbook | Dependencies |
|---|-----------|----------|--------------|
| 28 | mlflow | `ansible/40_thinkube/core/mlflow/00_install.yaml` | postgresql, ingress, acme-certificates |
| 29 | jupyterhub | `ansible/40_thinkube/core/jupyterhub/00_install.yaml` | harbor, harbor-build-jupyter, ingress, acme-certificates |

#### Platform Management

| # | Component | Playbook | Dependencies |
|---|-----------|----------|--------------|
| 30 | thinkube-control | `ansible/40_thinkube/core/thinkube-control/00_install.yaml` | postgresql, keycloak, harbor, ingress, acme-certificates |

## Critical Dependency Chains

### The 6 Foundation Components

These components form the critical foundation that most services depend on:

1. **k8s** (Canonical Kubernetes)
   - Everything runs on Kubernetes
   - Required by: ALL subsequent components

2. **ingress** (Ingress Controller)
   - Provides HTTP/HTTPS access to services
   - Required by: ALL web-accessible services

3. **acme-certificates** (TLS Certificates)
   - Provides SSL/TLS certificates
   - Required by: ALL HTTPS services

4. **postgresql** (Database)
   - Shared database for platform services
   - Required by: keycloak, harbor, gitea, mlflow, juicefs

5. **keycloak** (SSO Authentication)
   - Centralized authentication
   - Required by: harbor, thinkube-control, other authenticated services

6. **harbor** (Container Registry)
   - Stores custom container images
   - Required by: code-server, jupyterhub, custom deployments

### Common Dependency Patterns

**Most web services require**:
- k8s (infrastructure)
- ingress (network access)
- acme-certificates (TLS)

**Database-backed services require**:
- k8s + ingress + acme-certificates (above)
- postgresql (database)

**Authenticated services require**:
- k8s + ingress + acme-certificates (above)
- postgresql (database)
- keycloak (authentication)

**Custom image services require**:
- k8s + ingress + acme-certificates (above)
- harbor (container registry)
- harbor-build-* (specific image)

## Deployment Strategy

### Sequential Deployment

Components MUST be deployed in order due to dependencies. The installer automatically:
1. Deploys components sequentially (1-30)
2. Waits for each component to be ready
3. Handles conditional components (workers, GPU, networking)
4. Provides rollback for failed components

### Rollback Mapping

Each component has a corresponding rollback playbook:

| Component | Rollback Playbook |
|-----------|-------------------|
| k8s | `ansible/40_thinkube/core/infrastructure/k8s/19_rollback_control.yaml` |
| k8s-join-workers | `ansible/40_thinkube/core/infrastructure/k8s/29_rollback_workers.yaml` |
| gpu-operator | `ansible/40_thinkube/core/infrastructure/gpu_operator/19_rollback.yaml` |
| dns-server | `ansible/40_thinkube/core/infrastructure/dns-server/19_rollback.yaml` |
| coredns | `ansible/40_thinkube/core/infrastructure/coredns/19_rollback.yaml` |
| acme-certificates | `ansible/40_thinkube/core/infrastructure/acme-certificates/19_rollback.yaml` |
| ingress | `ansible/40_thinkube/core/infrastructure/ingress/19_rollback.yaml` |
| postgresql | `ansible/40_thinkube/core/postgresql/19_rollback.yaml` |
| keycloak | `ansible/40_thinkube/core/keycloak/19_rollback.yaml` |
| harbor | `ansible/40_thinkube/core/harbor/19_rollback.yaml` |
| seaweedfs | `ansible/40_thinkube/core/seaweedfs/19_rollback.yaml` |
| juicefs | `ansible/40_thinkube/core/juicefs/19_rollback.yaml` |
| argo-workflows | `ansible/40_thinkube/core/argo-workflows/19_rollback.yaml` |
| argocd | `ansible/40_thinkube/core/argocd/19_rollback.yaml` |
| devpi | `ansible/40_thinkube/core/devpi/19_rollback.yaml` |
| gitea | `ansible/40_thinkube/core/gitea/19_rollback.yaml` |
| code-server | `ansible/40_thinkube/core/code-server/19_rollback.yaml` |
| mlflow | `ansible/40_thinkube/core/mlflow/19_rollback.yaml` |
| jupyterhub | `ansible/40_thinkube/core/jupyterhub/19_rollback.yaml` |
| thinkube-control | `ansible/40_thinkube/core/thinkube-control/19_rollback.yaml` |

**Note**: Not all components have rollback playbooks (e.g., initial setup steps, image building steps).

## Conditional Deployments

Some components are deployed conditionally based on cluster configuration:

### Network Mode
- **Overlay network** (`networkMode=overlay`):
  - Deploys zerotier OR tailscale based on `overlayProvider`
- **Standard network**:
  - Skips overlay network setup

### Worker Nodes
- **Multi-node cluster** (`hasWorkers=true`):
  - Deploys k8s-join-workers
- **Single-node cluster**:
  - Skips worker join

### GPU Support
- **GPU nodes detected** (`needsGPUOperator=true`):
  - Deploys gpu-operator
- **No GPU**:
  - Skips GPU operator

## Component README Locations

For detailed component documentation, see:

```
thinkube/ansible/40_thinkube/core/
├── infrastructure/
│   ├── k8s/README.md
│   ├── gpu_operator/README.md
│   ├── dns-server/README.md
│   ├── coredns/README.md
│   ├── acme-certificates/README.md
│   └── ingress/README.md
├── postgresql/README.md
├── keycloak/README.md
├── harbor/README.md
├── seaweedfs/README.md
├── juicefs/README.md
├── argo-workflows/README.md
├── argocd/README.md
├── devpi/README.md
├── gitea/README.md
├── code-server/README.md
├── mlflow/README.md
├── jupyterhub/README.md
└── thinkube-control/README.md
```

All component READMEs follow the [component README template](../development/component-readme-template.md).

## Integration Points

### How Components Interact

**PostgreSQL** → Used by:
- Keycloak (user database)
- Harbor (registry database)
- Gitea (repository metadata)
- MLflow (experiment tracking)
- JuiceFS (metadata)

**Keycloak** → Used by:
- Harbor (SSO authentication)
- Thinkube Control (user authentication)
- Other services requiring SSO

**Harbor** → Used by:
- Code-Server (custom image)
- JupyterHub (custom image)
- Custom application deployments

**Ingress + ACME** → Used by:
- ALL web-accessible services for HTTPS

## Troubleshooting Dependency Issues

### Component Won't Deploy

1. **Check dependencies are deployed**:
   ```bash
   # Verify namespace exists
   kubectl get ns

   # Check pods in dependency namespace
   kubectl get pods -n NAMESPACE
   ```

2. **Verify dependency is healthy**:
   ```bash
   # Check service endpoints
   kubectl get svc -n NAMESPACE

   # Check ingress
   kubectl get ingress -n NAMESPACE
   ```

3. **Review deployment order**:
   - Ensure all dependencies (#1-X) are deployed before component #Y
   - Check conditional deployments are appropriate for your cluster

### Rollback Cascade

When rolling back a component, consider dependent components:
- Rolling back postgresql affects keycloak, harbor, gitea, mlflow
- Rolling back harbor affects code-server, jupyterhub
- Rolling back keycloak affects harbor, thinkube-control

**Best practice**: Roll back in reverse order of deployment.

## References

- [Component README Template](../development/component-readme-template.md)
- [Documentation Standards](../development/documentation-standards.md)
- [Thinkube Installer Source](https://github.com/thinkube/thinkube-installer/blob/main/frontend/src/pages/deploy.tsx)

---

**Version**: 1.0
**Source Data**: thinkube-installer v0.1.0+ (React version)
**Last Updated**: 2025-11-18
