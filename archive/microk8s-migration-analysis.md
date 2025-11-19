# MicroK8s to Canonical Kubernetes Migration - Technical Analysis

**Date:** 2025-10-22
**Status:** Research completed, migration not started

## Executive Summary

**Found:** 110 MicroK8s-specific references across 35 files in the ansible repository

**Migration effort:** 40-60 hours estimated
- Research k8s-snap paths: 4-6 hours
- Update playbooks: 20-30 hours
- Testing: 10-15 hours
- Documentation: 3-5 hours
- Debugging: 3-4 hours

## Current MicroK8s Usage Analysis

### Actual Addons Used

From `40_thinkube/core/infrastructure/microk8s/10_install_microk8s.yaml`:

```yaml
microk8s_addons:
  required:
    - dns        # CoreDNS
    - storage    # Hostpath storage
    - helm3      # Helm binary
  optional:
    - dashboard  # Kubernetes dashboard

# Plus MetalLB with custom ZeroTier IP range
```

**Everything else deployed via Helm charts:**
- NGINX Ingress
- cert-manager
- GPU Operator (NVIDIA)
- ArgoCD
- Argo Workflows
- Gitea
- Harbor
- Keycloak
- JupyterHub
- JuiceFS CSI
- All optional services

### Canonical Kubernetes Equivalents

Canonical K8s includes by default:
- ✅ Cilium (CNI)
- ✅ MetalLB (LoadBalancer)
- ✅ CoreDNS (DNS)
- ✅ OpenEBS (storage, better than hostpath)
- ✅ Metrics Server

## MicroK8s Dependencies Found

### Summary by Type

| Type | Count | Files |
|------|-------|-------|
| `microk8s.kubectl` | 110+ | 24 files |
| `microk8s.helm3` | - | 9 files |
| `/var/snap/microk8s` paths | - | 33 files |
| Total unique files | - | 35 files |

### Files with `microk8s.kubectl` References

```
/40_thinkube/optional/opensearch/README.md
/40_thinkube/optional/jupyterhub/README.md
/40_thinkube/optional/jupyterhub/11_deploy.yaml
/40_thinkube/optional/jupyterhub/19_rollback.yaml
/40_thinkube/optional/weaviate/17_configure_discovery.yaml
/40_thinkube/optional/mlflow/17_configure_discovery.yaml
/40_thinkube/optional/cvat/10_deploy.yaml
/40_thinkube/core/argo-workflows/README.md
/40_thinkube/core/code-server/10_deploy.yaml
/40_thinkube/core/code-server/14_configure_shell.yaml
/40_thinkube/core/code-server/15_configure_environment.yaml
/40_thinkube/core/code-server/16_refresh_config.yaml
/40_thinkube/core/code-server/19_rollback.yaml
/40_thinkube/core/code-server/tasks/00_core_shell_setup.yml
/40_thinkube/core/code-server/tasks/01_starship_setup.yml
/40_thinkube/core/code-server/tasks/02_functions_system.yml
/40_thinkube/core/code-server/tasks/03_aliases_system.yml
/40_thinkube/core/code-server/tasks/04_fish_plugins.yml
/40_thinkube/core/code-server/tasks/05_shell_config.yml
/40_thinkube/core/infrastructure/ingress/10_deploy.yaml
/40_thinkube/core/infrastructure/microk8s/10_install_microk8s.yaml
/40_thinkube/core/infrastructure/microk8s/10_install_microk8s_fixed.yaml
/40_thinkube/core/infrastructure/microk8s/18_test_control.yaml
/40_thinkube/core/infrastructure/networking/10_pod_network_access.yaml
/40_thinkube/core/infrastructure/cert-manager/letsencrypt/20_request_production.yaml
/40_thinkube/core/infrastructure/cert-manager/letsencrypt/29_rollback_to_staging.yaml
/40_thinkube/core/infrastructure/acme-certificates/10_deploy.yaml
```

### Files with `microk8s.helm3` References

```
/40_thinkube/optional/jupyterhub/11_deploy.yaml
/40_thinkube/optional/jupyterhub/19_rollback.yaml
/40_thinkube/optional/cvat/10_deploy.yaml
/40_thinkube/core/juicefs/10_deploy.yaml
/40_thinkube/core/juicefs/19_rollback.yaml
/40_thinkube/core/infrastructure/microk8s/10_install_microk8s.yaml
/40_thinkube/core/infrastructure/microk8s/10_install_microk8s_fixed.yaml
/40_thinkube/core/infrastructure/ingress/10_deploy.yaml
```

### Files with `/var/snap/microk8s` Paths

```
/40_thinkube/optional/jupyterhub/10_configure_keycloak.yaml
/40_thinkube/optional/jupyterhub/11_deploy.yaml
/40_thinkube/optional/jupyterhub/12_configure_examples_sync.yaml
/40_thinkube/optional/jupyterhub/18_test.yaml
/40_thinkube/optional/jupyterhub/19_rollback.yaml
/40_thinkube/core/code-server/10_deploy.yaml
/40_thinkube/core/code-server/15_configure_environment.yaml
/40_thinkube/core/code-server/16_refresh_config.yaml
/40_thinkube/core/code-server/19_rollback.yaml
/40_thinkube/core/gitea/14_configure_sso_user.yaml
/40_thinkube/core/juicefs/10_deploy.yaml
/40_thinkube/core/thinkube-control/14_deploy_tk_package_version.yaml
/40_thinkube/core/infrastructure/coredns/10_deploy.yaml
/40_thinkube/core/infrastructure/coredns/15_configure_node_dns.yaml
/40_thinkube/core/infrastructure/coredns/18_test.yaml
/40_thinkube/core/infrastructure/coredns/19_rollback.yaml
/40_thinkube/core/infrastructure/dns-server/10_deploy.yaml
/40_thinkube/core/infrastructure/dns-server/18_test.yaml
/40_thinkube/core/infrastructure/dns-server/19_rollback.yaml
/40_thinkube/core/infrastructure/gpu_operator/10_deploy.yaml
/40_thinkube/core/infrastructure/gpu_operator/README.md
/40_thinkube/core/infrastructure/ingress/10_deploy.yaml
/40_thinkube/core/infrastructure/microk8s/19_rollback_control.yaml
/40_thinkube/core/infrastructure/microk8s/20_join_workers.yaml
/40_thinkube/core/infrastructure/microk8s/29_rollback_workers.yaml
/40_thinkube/core/infrastructure/acme-certificates/10_deploy.yaml
/40_thinkube/core/infrastructure/acme-certificates/18_test.yaml
/40_thinkube/core/infrastructure/acme-certificates/19_rollback.yaml
/40_thinkube/core/infrastructure/cert-manager/letsencrypt/20_request_production.yaml
/40_thinkube/core/infrastructure/cert-manager/letsencrypt/29_rollback_to_staging.yaml
```

## Specific Changes Required

### 1. Binary Path Variables

**Current patterns:**
```yaml
kubectl_bin: "/snap/bin/microk8s.kubectl"
helm_bin: "/snap/bin/microk8s.helm3"
kubectl_bin: "microk8s.kubectl"
```

**Need to change to:**
```yaml
kubectl_bin: "kubectl"  # or wherever k8s-snap places it
helm_bin: "helm"        # or wherever k8s-snap places it
```

### 2. Kubeconfig Path

**Current:**
```yaml
kubeconfig: "/var/snap/microk8s/current/credentials/client.config"
```

**Need to determine:** k8s-snap equivalent path

### 3. Wrapper Scripts

**Current** (`10_install_microk8s.yaml:387-409`):
```bash
# /usr/local/bin/kubectl wrapper
#!/bin/bash
exec /snap/bin/microk8s.kubectl "$@"

# /usr/local/bin/helm wrapper
#!/bin/bash
exec /snap/bin/microk8s.helm3 "$@"
```

**Need to update to:** Point to k8s-snap binaries

### 4. Direct Command Calls

**Current patterns in code-server tasks:**
```bash
microk8s.kubectl exec -n {{ code_server_namespace }} {{ codeserver_pod }} -- ...
microk8s.kubectl cp /tmp/file pod:/path
microk8s.kubectl get pods ...
microk8s.kubectl delete namespace ...
```

**Need to replace with:** Just `kubectl` (assuming wrapper or PATH)

### 5. GPU Operator Specific Paths

**Current** (`gpu_operator/10_deploy.yaml:122-124`):
```yaml
- name: CONTAINERD_CONFIG
  value: /var/snap/microk8s/current/args/containerd-template.toml
- name: CONTAINERD_SOCKET
  value: /var/snap/microk8s/common/run/containerd.sock
```

**Need to determine:** k8s-snap equivalent paths for containerd

### 6. JuiceFS CSI Kubelet Directory

**Current** (`juicefs/10_deploy.yaml:217`):
```bash
--set kubeletDir=/var/snap/microk8s/common/var/lib/kubelet
```

**Need to determine:** k8s-snap kubelet directory location

### 7. ACME Certificate Reload Command

**Current** (`acme-certificates/10_deploy.yaml:212`):
```bash
--reloadcmd "/snap/bin/microk8s.kubectl delete pod -n ingress -l app.kubernetes.io/name=nginx-ingress-microk8s"
```

**Need to update:** Binary path and possibly pod selector

## Technical Unknowns - Research Needed

These must be answered in Phase 1 (research):

### k8s-snap Installation & Paths

- [ ] How to install: `snap install k8s --classic`?
- [ ] Kubeconfig location: `/var/snap/k8s/...`? Or `~/.kube/config`?
- [ ] kubectl binary: `/snap/bin/k8s.kubectl`? Or symlinked to `/usr/local/bin/kubectl`?
- [ ] helm binary: Included? Or install separately?
- [ ] Snap service name: `snap.k8s.daemon`?

### Containerd Paths

- [ ] Containerd socket: `/var/snap/k8s/.../containerd.sock`?
- [ ] Containerd config: `/var/snap/k8s/.../containerd.toml`?
- [ ] Compatible with NVIDIA GPU Operator?

### Kubelet Paths

- [ ] Kubelet directory: `/var/snap/k8s/.../kubelet`?
- [ ] CSI plugin directory?
- [ ] Compatible with JuiceFS CSI driver?

### CNI Configuration

- [ ] Is Cilium pre-configured?
- [ ] How to configure Cilium for ZeroTier integration?
- [ ] BGP support for MetalLB?

### MetalLB Configuration

- [ ] How to configure IP address pools?
- [ ] L2 mode vs BGP mode?
- [ ] Integration with Cilium?

### Multi-node Clustering

- [ ] How to join worker nodes?
- [ ] Certificate management?
- [ ] High availability setup?

## Migration Checklist

### Phase 1: Research & Validation (4-6 hours)

- [ ] Install k8s-snap on test server
- [ ] Document all paths (create table below)
- [ ] Test basic kubectl/helm commands
- [ ] Deploy simple workload
- [ ] Test Cilium networking
- [ ] Test MetalLB LoadBalancer
- [ ] **Critical:** Test auth stability (Keycloak, API server access)
- [ ] Decision point: Proceed or abort?

**Path Documentation Table (to be filled):**

| Component | MicroK8s Path | k8s-snap Path |
|-----------|---------------|---------------|
| kubectl binary | `/snap/bin/microk8s.kubectl` | ? |
| helm binary | `/snap/bin/microk8s.helm3` | ? |
| kubeconfig | `/var/snap/microk8s/current/credentials/client.config` | ? |
| containerd socket | `/var/snap/microk8s/common/run/containerd.sock` | ? |
| containerd config | `/var/snap/microk8s/current/args/containerd-template.toml` | ? |
| kubelet dir | `/var/snap/microk8s/common/var/lib/kubelet` | ? |

### Phase 2: Core Infrastructure (20-30 hours)

#### Installation Playbooks

- [ ] Create new `10_install_k8s.yaml` playbook
- [ ] Install k8s snap
- [ ] Configure Cilium (if needed)
- [ ] Configure MetalLB IP pools
- [ ] Create kubectl/helm wrappers
- [ ] Test single-node cluster

#### Update All Playbooks

For each of the 35 files:

**Files with `kubectl_bin` variable:**
- [ ] `code-server/10_deploy.yaml`
- [ ] `code-server/15_configure_environment.yaml`
- [ ] `ingress/10_deploy.yaml` (3 instances)
- [ ] `weaviate/17_configure_discovery.yaml`

**Files with `helm_bin` variable:**
- [ ] `jupyterhub/11_deploy.yaml`
- [ ] `jupyterhub/19_rollback.yaml`
- [ ] `cvat/10_deploy.yaml`
- [ ] `juicefs/10_deploy.yaml`
- [ ] `ingress/10_deploy.yaml` (2 instances)

**Files with `kubeconfig` variable:**
- [ ] All 20 files listed in "Files with `/var/snap/microk8s` Paths" section

**Files with direct `microk8s.kubectl` commands:**
- [ ] `code-server/14_configure_shell.yaml` (rollout status)
- [ ] `code-server/16_refresh_config.yaml` (exec, delete pod, wait)
- [ ] `code-server/19_rollback.yaml` (delete commands)
- [ ] `code-server/tasks/03_aliases_system.yml` (cp, exec commands)
- [ ] `code-server/tasks/04_fish_plugins.yml` (exec commands)
- [ ] `code-server/tasks/05_shell_config.yml` (exec commands)
- [ ] `mlflow/17_configure_discovery.yaml` (cp commands)
- [ ] `networking/10_pod_network_access.yaml` (get pods, test commands)
- [ ] `acme-certificates/10_deploy.yaml` (reloadcmd)

**Special cases:**
- [ ] `gpu_operator/10_deploy.yaml` - Update containerd paths
- [ ] `juicefs/10_deploy.yaml` - Update kubelet directory

### Phase 3: Testing (10-15 hours)

#### Component Testing

- [ ] MicroK8s replacement (k8s-snap installation)
- [ ] MetalLB LoadBalancer services
- [ ] NGINX Ingress Controller
- [ ] cert-manager + Let's Encrypt
- [ ] GPU Operator (NVIDIA)
- [ ] JuiceFS CSI Driver
- [ ] Keycloak (auth stability test!)
- [ ] Gitea
- [ ] Harbor
- [ ] ArgoCD
- [ ] Argo Workflows
- [ ] Code Server
- [ ] JupyterHub

#### Full Platform Test

- [ ] Fresh install from scratch
- [ ] Deploy all core services
- [ ] Deploy sample optional services
- [ ] Test auth flows (no restart needed?)
- [ ] Test GPU workload
- [ ] Test persistent storage (JuiceFS)
- [ ] Test CI/CD pipeline (Argo Workflows)
- [ ] Multi-node cluster setup
- [ ] Worker node join

### Phase 4: Documentation (3-5 hours)

- [ ] Update `thinkube/README.md`
- [ ] Update `thinkube-installer/README.md`
- [ ] Update installation documentation
- [ ] Update architecture diagrams
- [ ] Document any behavioral differences
- [ ] Update troubleshooting guides
- [ ] Document Cilium-specific operations

### Phase 5: Installer Update (included in testing)

- [ ] Update installer backend to install k8s-snap
- [ ] Update installer UI if needed
- [ ] Test installer on fresh system
- [ ] Build new installer packages

## Known Issues to Watch For

### Calico Issues We're Escaping

From current MicroK8s/Calico deployment:
- Authorization failures requiring server restart
- BGP peering flakes
- iptables rule corruption with thousands of rules
- Conntrack table exhaustion
- NetworkManager interference

### Potential Cilium Issues to Test

From research:
- Network connectivity crashes (check if still an issue in 2025)
- eBPF program failures (kernel compatibility)
- Learning curve for debugging (different tools than iptables)

### Other Risks

- GPU Operator may need different containerd configuration
- JuiceFS CSI may need adjustments for kubelet paths
- Existing users would lose all data (why we MUST do this before v0.1.0)

## Success Criteria

Migration is successful when:

1. ✅ k8s-snap cluster deploys from scratch
2. ✅ All core services deploy successfully
3. ✅ GPU operator works with NVIDIA GPUs
4. ✅ JuiceFS CSI mounts persistent volumes
5. ✅ Auth flows work reliably (no random failures!)
6. ✅ Multi-node cluster formation works
7. ✅ No "microk8s" references remain in code
8. ✅ Installer deploys k8s-snap successfully
9. ✅ Performance is equal or better
10. ✅ **No server restarts needed for auth issues**

## References

- Canonical Kubernetes: https://github.com/canonical/k8s-snap
- Documentation: https://documentation.ubuntu.com/canonical-kubernetes/latest/
- Cilium: https://cilium.io/
- CNCF Conformance: k8s-snap is CNCF-conformant
- 12-year LTS: Starting with Kubernetes 1.32

## Next Steps

1. Create test environment
2. Install k8s-snap
3. Fill in "Path Documentation Table"
4. Validate Cilium networking stability
5. **Test auth stability extensively**
6. Make go/no-go decision
7. Begin Phase 2 if validated
