# Component Deployment Matrix

Complete reference for all Thinkube platform components in deployment order.

**Source**: Extracted from thinkube-installer/frontend/src/pages/deploy.tsx
**Last Updated**: 2025-11-18

## Matrix Legend

- ✅ Complete and follows template
- 📝 Exists but needs review/update
- ❌ Missing
- ⏭️ Not applicable (build/configuration step, not a deployed component)

## Phase 1: Initial Setup

| # | Component | Playbook | README | Dependencies | Notes |
|---|-----------|----------|--------|--------------|-------|
| 1 | env-setup | `ansible/00_initial_setup/20_setup_env.yaml` | 📝 | None | Environment preparation |
| 2 | python-setup | `ansible/40_thinkube/core/infrastructure/00_setup_python_k8s.yaml` | ⏭️ | env-setup | Python venv setup (no dir README) |
| 3 | github-cli | `ansible/00_initial_setup/40_setup_github_cli.yaml` | 📝 | python-setup | Covered by initial-setup README |
| 4 | networking | `ansible/30_networking/10_setup_zerotier.yaml`<br>`ansible/30_networking/11_setup_tailscale.yaml` | 📝 | None | Optional overlay networking (zerotier OR tailscale) |
| 5 | setup-python-k8s | `ansible/40_thinkube/core/infrastructure/00_setup_python_k8s.yaml` | ⏭️ | python-setup | Duplicate of #2 |

**Phase 1 Status**: 5 components - initial-setup and networking READMEs exist

## Phase 2: Kubernetes Infrastructure

| # | Component | Playbook | README | Dependencies | Type |
|---|-----------|----------|--------|--------------|------|
| 6 | **k8s** | `ansible/40_thinkube/core/infrastructure/k8s/10_install_k8s.yaml` | 📝 | setup-python-k8s | Foundation ⭐ |
| 7 | k8s-join-workers | `ansible/40_thinkube/core/infrastructure/k8s/20_join_workers.yaml` | ⏭️ | k8s | Optional (same README as k8s) |
| 8 | gpu-operator | `ansible/40_thinkube/core/infrastructure/gpu_operator/00_install.yaml` | 📝 | k8s | Optional (conditional on GPU) |
| 9 | dns-server | `ansible/40_thinkube/core/infrastructure/dns-server/10_deploy.yaml` | 📝 | k8s | Foundation ⭐ |
| 10 | coredns | `ansible/40_thinkube/core/infrastructure/coredns/10_deploy.yaml` | 📝 | k8s, dns-server | Foundation ⭐ |
| 11 | coredns-configure-nodes | `ansible/40_thinkube/core/infrastructure/coredns/15_configure_node_dns.yaml` | ⏭️ | coredns | Config step (same README) |
| 12 | acme-certificates | `ansible/40_thinkube/core/infrastructure/acme-certificates/10_deploy.yaml` | 📝 | k8s, coredns | Foundation ⭐ |
| 13 | ingress | `ansible/40_thinkube/core/infrastructure/ingress/10_deploy.yaml` | 📝 | k8s, acme-certificates | Foundation ⭐ |

**Phase 2 Status**: 6/8 components have unique READMEs

## Phase 3: Core Services

### Foundation Services

| # | Component | Playbook | README | Dependencies | Type |
|---|-----------|----------|--------|--------------|------|
| 14 | **postgresql** | `ansible/40_thinkube/core/postgresql/00_install.yaml` | ✅ | k8s, ingress, acme | Foundation ⭐ |
| 15 | **keycloak** | `ansible/40_thinkube/core/keycloak/00_install.yaml` | ✅ | postgresql, ingress, acme | Foundation ⭐ |
| 16 | **harbor** | `ansible/40_thinkube/core/harbor/00_install.yaml` | ✅ | postgresql, keycloak, ingress, acme | Foundation ⭐ |
| 17 | harbor-mirror-images | `ansible/40_thinkube/core/harbor-images/13_mirror_public_images.yaml` | ⏭️ | harbor | Build step (#17-20) |
| 18 | harbor-images | `ansible/40_thinkube/core/harbor-images/` | 📝 | harbor-mirror | README covers all build steps |

### Harbor Image Building (detailed)

| Step | Playbook | Description |
|------|----------|-------------|
| #17 | `13_mirror_public_images.yaml` | Mirror public container images |
| #18 | `14_build_base_images.yaml` | Build base images |
| #19 | `15_build_jupyter_images.yaml` | Build Jupyter notebook images |
| #20 | `16_build_codeserver_image.yaml` | Build code-server image |

**Note**: Components #17-20 share one README. Numbering jumps to #22 after harbor-images.

### Storage Services

| # | Component | Playbook | README | Dependencies | Type |
|---|-----------|----------|--------|--------------|------|
| 22 | **seaweedfs** | `ansible/40_thinkube/core/seaweedfs/00_install.yaml` | 📝 | k8s | Foundation ⭐ |
| 23 | juicefs | `ansible/40_thinkube/core/juicefs/00_install.yaml` | 📝 | seaweedfs, postgresql | Service |

### CI/CD Services

| # | Component | Playbook | README | Dependencies | Type |
|---|-----------|----------|--------|--------------|------|
| 24 | argo-workflows | `ansible/40_thinkube/core/argo-workflows/00_install.yaml` | 📝 | k8s, ingress, acme | Service |
| 25 | argocd | `ansible/40_thinkube/core/argocd/00_install.yaml` | 📝 | k8s, ingress, acme | Service |

### Development Tools

| # | Component | Playbook | README | Dependencies | Type |
|---|-----------|----------|--------|--------------|------|
| 26 | devpi | `ansible/40_thinkube/core/devpi/00_install.yaml` | 📝 | k8s, ingress, acme | Service |
| 27 | gitea | `ansible/40_thinkube/core/gitea/00_install.yaml` | 📝 | postgresql, ingress, acme | Service |
| 28 | code-server | `ansible/40_thinkube/core/code-server/00_install.yaml` | 📝 | harbor, harbor-codeserver, ingress, acme | Service |

### ML/AI Services

| # | Component | Playbook | README | Dependencies | Type |
|---|-----------|----------|--------|--------------|------|
| 29 | mlflow | `ansible/40_thinkube/core/mlflow/00_install.yaml` | 📝 | postgresql, ingress, acme | Service |
| 30 | jupyterhub | `ansible/40_thinkube/core/jupyterhub/00_install.yaml` | 📝 | harbor, harbor-jupyter, ingress, acme | Service |

### Platform Management

| # | Component | Playbook | README | Dependencies | Type |
|---|-----------|----------|--------|--------------|------|
| 31 | thinkube-control | `ansible/40_thinkube/core/thinkube-control/00_install.yaml` | 📝 | postgresql, keycloak, harbor, ingress, acme | Service |

**Phase 3 Status**: All 18 deployable components have READMEs (14-31, gap at 19-21 for harbor build steps)

## Phase 4: Optional Components

| # | Component | Playbook | README | Dependencies | Category |
|---|-----------|----------|--------|--------------|----------|
| 32 | prometheus | `ansible/40_thinkube/optional/prometheus/10_deploy.yaml` | 📝 | k8s | Monitoring |
| 33 | nats | `ansible/40_thinkube/optional/nats/10_deploy.yaml` | 📝 | k8s | Messaging |
| 34 | knative | `ansible/40_thinkube/optional/knative/10_deploy.yaml` | 📝 | k8s | Serverless |
| 35 | clickhouse | `ansible/40_thinkube/optional/clickhouse/10_deploy.yaml` | 📝 | k8s | Database |
| 36 | opensearch | `ansible/40_thinkube/optional/opensearch/10_deploy.yaml` | 📝 | k8s | Search/Analytics |
| 37 | valkey | `ansible/40_thinkube/optional/valkey/10_deploy.yaml` | 📝 | k8s | Cache/Storage |
| 38 | chroma | `ansible/40_thinkube/optional/chroma/10_deploy.yaml` | 📝 | k8s | Vector DB |
| 39 | qdrant | `ansible/40_thinkube/optional/qdrant/10_deploy.yaml` | 📝 | k8s | Vector DB |
| 40 | weaviate | `ansible/40_thinkube/optional/weaviate/10_deploy.yaml` | 📝 | k8s | Vector DB |
| 41 | perses | `ansible/40_thinkube/optional/perses/10_deploy.yaml` | 📝 | k8s | Monitoring |
| 42 | pgadmin | `ansible/40_thinkube/optional/pgadmin/10_deploy.yaml` | 📝 | postgresql | Database Tools |
| 43 | litellm | `ansible/40_thinkube/optional/litellm/10_deploy.yaml` | ✅ | k8s | AI/LLM |
| 44 | langfuse | `ansible/40_thinkube/optional/langfuse/10_deploy.yaml` | ✅ | postgresql | AI/LLM |
| 45 | argilla | `ansible/40_thinkube/optional/argilla/10_deploy.yaml` | ✅ | k8s | AI/Data Labeling |
| 46 | cvat | `ansible/40_thinkube/optional/cvat/10_deploy.yaml` | ✅ | postgresql, valkey, clickhouse | AI/Data Labeling |

**Phase 4 Status**: 15/15 optional components have READMEs (litellm, langfuse, argilla, cvat are ✅ template compliant)

## Summary

### Overall Status

- **Total Core Components**: 31 (components #1-31, with numbering gap at 19-21)
- **Total Optional Components**: 15 (components #32-46)
- **Total Components**: 46
- **Deployable Core Components**: 25 (have unique READMEs)
- **Deployable Optional Components**: 15 (all have READMEs)
- **Total READMEs**: 40 (25 core + 15 optional)
- **Template Compliant**: 7 (postgresql, keycloak, harbor, litellm, langfuse, argilla, cvat)
- **Need Review**: 33 (infrastructure + core services + most optional components)

### Foundation Components (6)

These are the critical components most services depend on:

| Component | README Status | Notes |
|-----------|---------------|-------|
| k8s | 📝 Very comprehensive | Needs dependency references added |
| ingress | 📝 Good | Needs dependency references |
| acme-certificates | 📝 Good | Needs dependency references |
| postgresql | ✅ Excellent | Template compliant |
| keycloak | ✅ Excellent | Template compliant |
| harbor | ✅ Excellent | Template compliant |

### Documentation Quality Levels

**✅ Excellent (3)**:
- postgresql - Complete, follows template
- keycloak - Complete, follows template
- harbor - Complete, follows template

**📝 Good - Needs Minor Updates (19)**:
All have comprehensive READMEs but need:
- Explicit Dependencies section referencing deployment order
- Link to deployment dependency graph
- Standardized section ordering per template

**⏭️ Not Applicable (6)**:
- Setup steps without unique READMEs (python-setup #2, setup-python-k8s #5)
- Sub-steps sharing parent READMEs (k8s-join-workers #7, coredns-configure-nodes #11, harbor build steps #17-20)

## README Review Checklist

For each component marked 📝, verify:

- [ ] **Dependencies section** - References deployment order and dependency graph
- [ ] **Prerequisites section** - Environment variables, configuration, requirements
- [ ] **Playbooks section** - Description of 00_install, 18_test, 19_rollback
- [ ] **Deployment section** - Step-by-step with actual commands
- [ ] **Configuration section** - Available options documented
- [ ] **Testing section** - How to verify deployment
- [ ] **Troubleshooting section** - Common issues and solutions
- [ ] **Rollback section** - How to cleanly remove
- [ ] **Integration section** (if applicable) - How other components use this
- [ ] **Platform-specific notes** (if applicable) - ARM64, GPU, DGX Spark

## Next Steps

### Immediate

1. ✅ Create component matrix (this document)
2. ⏭️ Add dependencies section to infrastructure component READMEs
3. ⏭️ Add dependencies section to core service READMEs
4. ⏭️ Standardize section ordering across all READMEs
5. ⏭️ Add cross-references to deployment dependency graph

### Future Enhancements

- Add "Last Tested" dates to component READMEs
- Create troubleshooting knowledge base from component issues
- Add performance tuning guides
- Document upgrade procedures
- Create quick reference cards for common operations

## References

- [Deployment Dependency Graph](../architecture/deployment-dependency-graph.md)
- [Component README Template](../development/component-readme-template.md)
- [Documentation Standards](../development/documentation-standards.md)

---

**Last Updated**: 2025-11-18
**Total Components Tracked**: 46 (31 core + 15 optional)
**Documentation Coverage**: 40 README files copied
**Component Numbering**: #1-46 with gaps at #2, #3, #6, #19-21 (no unique READMEs or shared READMEs)
