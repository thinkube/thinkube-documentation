# NVIDIA GPU Operator

This component deploys the NVIDIA GPU Operator in the k8s-snap cluster, enabling GPU support for containerized workloads.

## Overview

The NVIDIA GPU Operator is a Kubernetes operator that automates the management of NVIDIA GPUs in Kubernetes clusters. It manages the installation and lifecycle of several components:

- NVIDIA drivers (pre-installed on host, not managed by operator)
- NVIDIA container toolkit (configures containerd for GPU access)
- NVIDIA Kubernetes device plugin (advertises GPUs to Kubernetes)
- NVIDIA DCGM exporter (GPU metrics)
- NVIDIA MIG manager (Multi-Instance GPU support, if applicable)

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster infrastructure with containerd runtime configuration

**Required by** (which components depend on this):
- GPU workloads - Any pod that needs `nvidia.com/gpu` resources
- JupyterHub with GPU notebooks
- ML/AI training workloads

**Deployment order**: #8 (optional component)

See [Deployment Dependency Graph](https://github.com/thinkube/thinkube-documentation/blob/main/architecture/deployment-dependency-graph.md) for complete dependency tree.

## Prerequisites

### Host Requirements
- k8s-snap cluster with at least one GPU-equipped node
- NVIDIA drivers >= 470.x installed on the host systems
- Verify drivers: `nvidia-smi` should show GPU information

### Software Requirements
- Kubernetes 1.34+ (provided by k8s-snap)
- Helm 3.x (provided by k8s-snap)
- kubectl CLI (provided by k8s-snap)
- jq for JSON parsing

### k8s-snap Containerd Configuration
The k8s installation playbook automatically creates `/etc/containerd/conf.d/00-k8s-runc.toml` which is required for GPU operator compatibility. This ensures the runc runtime persists alongside the nvidia runtime.

**Background**: See [k8s-snap issue #1991](https://github.com/canonical/k8s-snap/issues/1991) for details on why this configuration is necessary and how it prevents node failures after GPU operator installation.

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs the complete GPU operator installation:
- Imports 10_deploy.yaml - Deploys GPU operator
- Imports 15_configure_time_slicing.yaml - Configures GPU time-slicing (4 virtual GPUs per physical GPU)
- Imports 17_configure_discovery.yaml - Configures service discovery

### 10_deploy.yaml
Main deployment playbook that installs and configures GPU operator:

- **Docker GPU Configuration**:
  - Creates `/etc/docker/daemon.json` with nvidia runtime configuration
  - Enables GPU access for Docker containers (required for NVIDIA NIM on DGX Spark)
  - Restarts Docker to load NVIDIA runtime

- **GPU Operator Installation**:
  - Adds NVIDIA Helm repository (https://nvidia.github.io/gpu-operator)
  - Installs GPU operator via Helm with custom k8s-snap containerd configuration:
    - CONTAINERD_CONFIG: `/var/lib/k8s-containerd/k8s-containerd/etc/containerd/config.toml`
    - CONTAINERD_SOCKET: `/var/lib/k8s-containerd/k8s-containerd/run/containerd/containerd.sock`
    - RUNTIME_DROP_IN_CONFIG: `/var/lib/k8s-containerd/k8s-containerd/etc/containerd/conf.d/99-nvidia.toml`
  - Disables driver installation (`driver.enabled=false` - drivers pre-installed on host)
  - Mounts containerd config directories as volumes

- **nvidia-container-toolkit Configuration**:
  - Waits for nvidia-container-toolkit DaemonSet to create `99-nvidia.toml` runtime config
  - Restarts k8s-snap containerd to load nvidia runtime alongside runc runtime
  - Works with pre-existing `00-k8s-runc.toml` (created by k8s installation) to support both runtimes

- **GPU Discovery**:
  - Waits for nvidia-device-plugin-daemonset to advertise GPUs to Kubernetes
  - Waits for `nvidia.com/gpu` resources to appear on nodes
  - Verifies GPU count matches physical GPUs on each node

- **Validation**:
  - Deploys cuda-vectoradd test pod with `runtimeClassName: nvidia`
  - Runs CUDA vector-add test to verify GPU functionality
  - Cleans up test pod after successful validation

### 15_configure_time_slicing.yaml
GPU time-slicing configuration that enables multiple pods to share a single physical GPU:

- **Time-Slicing ConfigMap**:
  - Creates `time-slicing-config` ConfigMap in gpu-operator namespace
  - Configures virtual GPU replicas per physical GPU (default: 4, customizable via `gpu_time_slicing_replicas`)
  - Sets `failRequestsGreaterThanOne: false` to allow pods to request multiple virtual GPUs

- **ClusterPolicy Update**:
  - Patches GPU Operator ClusterPolicy to enable time-slicing
  - Sets default time-slicing profile to "any" (applies to all GPUs)
  - Triggers nvidia-device-plugin-daemonset restart to apply configuration

- **Result**:
  - Nodes advertise multiplied GPU count (e.g., 1 physical GPU becomes 4 virtual GPUs: `nvidia.com/gpu: 4`)
  - Multiple pods can request `nvidia.com/gpu: 1` and share the same physical GPU
  - GPU memory is shared - monitor total usage to avoid OOM

### 17_configure_discovery.yaml
Service discovery configuration that creates metadata for GPU operator:

- **Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in gpu-operator namespace
  - Labels service as core infrastructure (`thinkube.io/service-type: core`)
  - Defines service endpoints:
    - NVIDIA DCGM metrics exporter at `http://nvidia-dcgm-exporter.gpu-operator.svc.cluster.local:9400`
    - GPU Operator webhook at `http://gpu-operator.gpu-operator.svc.cluster.local:8080`
  - Categorizes service as AI infrastructure with scaling configuration

## Deployment

### Step 1: Deploy GPU Operator

```bash
cd ~/thinkube
./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/gpu_operator/00_install.yaml
```

This runs all three configuration playbooks (deploy, time-slicing, discovery).

### Step 2: Test Deployment

```bash
./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/gpu_operator/18_test.yaml
```

### Rollback (if needed)

```bash
./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/gpu_operator/19_rollback.yaml
```

## Configuration

The following inventory variables can be used to configure the GPU Operator:

| Variable | Description | Default |
|----------|-------------|---------|
| gpu_operator_version | Version of the GPU Operator to install | Latest |

### Automatic Docker GPU Configuration

The deployment playbook automatically configures Docker with NVIDIA runtime support for DGX Spark systems. This enables GPU access for Docker containers, which is required for:

- NVIDIA NIM (NVIDIA Inference Microservices) containers
- NVIDIA educational materials and examples
- Docker-based GPU development workflows

**Configuration created**: `/etc/docker/daemon.json`
```json
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
```

**Usage**:
```bash
# Run a GPU-enabled container with Docker
docker run --runtime=nvidia --gpus all nvidia/cuda:12.5.0-base-ubuntu22.04 nvidia-smi
```

### k8s-snap Containerd Runtime Configuration

The deployment playbook works in conjunction with the k8s-snap installation playbook to ensure proper GPU runtime configuration. The k8s-snap playbook creates `/etc/containerd/conf.d/00-k8s-runc.toml` which prevents the GPU operator's nvidia-container-toolkit from breaking containerd.

**How it works**:
1. k8s-snap installation creates `00-k8s-runc.toml` with base runc runtime configuration
2. GPU operator's nvidia-container-toolkit DaemonSet creates `99-nvidia.toml` with nvidia runtime
3. Both configurations coexist, providing both `runc` (default) and `nvidia` (for GPU pods) runtimes

This configuration supports automatic scaling - new GPU nodes joining the cluster will automatically receive both configurations without manual intervention.

**Technical Details**: See [k8s-snap issue #1991](https://github.com/canonical/k8s-snap/issues/1991) which documents this solution and explains why k8s-snap's config.d mechanism requires explicit runc runtime configuration to coexist with GPU operator.

## Testing

The 18_test.yaml playbook tests all aspects of the GPU Operator:

1. Checks if all components are installed and running
2. Verifies that GPU resources are available on the nodes
3. Runs a CUDA workload on each GPU node to validate functionality

## Troubleshooting

### GPU Operator Pods Not Running

If the deployment fails, check the following:

1. **Ensure NVIDIA drivers are correctly installed** on the host system:
   ```bash
   nvidia-smi
   # Should show GPU information and driver version
   ```

2. **Check GPU operator pod status**:
   ```bash
   kubectl get pods -n gpu-operator
   ```

   Expected pods:
   - `nvidia-device-plugin-daemonset-*`: Running (critical for GPU discovery)
   - `nvidia-container-toolkit-daemonset-*`: Running (critical for runtime config)
   - `nvidia-dcgm-exporter-*`: Running
   - `nvidia-operator-validator-*`: Completed or Running
   - `gpu-operator-*`: Running

3. **Examine logs of any pods in error state**:
   ```bash
   kubectl logs -n gpu-operator <pod-name>
   kubectl describe pod -n gpu-operator <pod-name>
   ```

### Node Becomes NotReady After GPU Operator Install

**Symptom**: Node shows `NotReady` status after GPU operator deploys.

**Root Cause**: Missing runc runtime configuration in containerd.

**Solution**: Verify that `/etc/containerd/conf.d/00-k8s-runc.toml` exists. This file should have been created during k8s-snap installation. If missing, create it manually:

```bash
sudo tee /etc/containerd/conf.d/00-k8s-runc.toml > /dev/null <<'EOF'
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      default_runtime_name = "runc"

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
EOF

# Restart k8s-snap containerd
sudo snap restart k8s.containerd
```

### GPUs Not Detected in Cluster

**Symptom**: `kubectl describe node` shows no `nvidia.com/gpu` resources.

**Check**:
1. **Verify nvidia-device-plugin-daemonset is running**:
   ```bash
   kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
   ```

2. **Check nvidia-container-toolkit-daemonset created runtime config**:
   ```bash
   cat /etc/containerd/conf.d/99-nvidia.toml
   # Should contain nvidia runtime configuration
   ```

3. **Verify both runtime configs exist**:
   ```bash
   ls -la /etc/containerd/conf.d/
   # Should show:
   # 00-k8s-runc.toml
   # 99-nvidia.toml
   ```

4. **Check containerd is using configs**:
   ```bash
   sudo k8s kubectl get nodes -o json | jq '.items[].status.allocatable'
   # Should show "nvidia.com/gpu": "1" or higher
   ```

### Docker GPU Access Not Working

**Symptom**: `docker run --runtime=nvidia` fails with "unknown runtime" error.

**Solution**:
1. **Verify daemon.json exists**:
   ```bash
   cat /etc/docker/daemon.json
   ```

2. **Restart Docker**:
   ```bash
   sudo systemctl restart docker
   ```

3. **Test GPU access**:
   ```bash
   docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.5.0-base-ubuntu22.04 nvidia-smi
   ```

### DGX Spark Specific Issues

**Expected Warning** (this is normal):
```
Ignoring error getting device memory: Not Supported
```

This warning appears in nvidia-dcgm-exporter logs on DGX Spark due to its Unified Memory Architecture (UMA). GPU functionality is not affected.

**Reference**: [DGX Spark Known Issues](https://docs.nvidia.com/dgx/dgx-spark/known-issues.html)

### Additional Verification

Check k8s-snap containerd configuration paths:
```bash
# Verify custom containerd paths (for Docker coexistence)
sudo k8s config get containerd-base-dir
# Should output: /var/lib/k8s-containerd

# Check containerd socket
ls -la /var/lib/k8s-containerd/k8s-containerd/run/containerd/containerd.sock
```