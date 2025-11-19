# JuiceFS Distributed Filesystem

This component deploys JuiceFS distributed filesystem providing true ReadWriteMany (RWX) storage capabilities for the Kubernetes cluster. JuiceFS separates metadata and data storage, using PostgreSQL for metadata and SeaweedFS S3 for data storage.

## Overview

JuiceFS provides true ReadWriteMany (RWX) storage across multiple nodes by separating metadata and data storage:
- **Metadata Engine**: PostgreSQL for filesystem metadata
- **Data Storage**: SeaweedFS S3 API for object storage
- **CSI Driver**: Kubernetes CSI driver for dynamic provisioning
- **POSIX Compatible**: Full POSIX filesystem semantics
- **Multi-node Consistency**: Files written on one node are immediately visible on all nodes
- **Production Ready**: Used in production AI/ML workloads
- **Apache 2.0 License**: Fully compatible with platform licensing

### Architecture

```
JuiceFS CSI Driver (Kubernetes)
├── Metadata → PostgreSQL (existing core component)
└── Data → SeaweedFS S3 API (existing core component)
```

### Why JuiceFS?

JuiceFS solves the multi-node RWX storage problem that SeaweedFS CSI driver cannot reliably provide:

- **SeaweedFS CSI Issue**: FUSE cache causes multi-node inconsistency
- **JuiceFS Solution**: Uses SeaweedFS via S3 API (no FUSE), with PostgreSQL metadata engine
- **Result**: True shared filesystem across all GPU nodes for JupyterHub, AI models, datasets, etc.

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster with k8s-snap
- postgresql (deployment order #14) - PostgreSQL database for metadata storage
- seaweedfs (deployment order #21) - SeaweedFS S3 API for object storage

**Required by** (which components depend on this):
- Optional: JupyterHub for shared notebooks and examples across GPU nodes
- Optional: AI/ML workloads requiring multi-node model access

**Deployment order**: #22

See [Deployment Dependency Graph](https://github.com/thinkube/thinkube-documentation/blob/main/architecture/deployment-dependency-graph.md) for complete dependency tree.

## Prerequisites

**Required inventory variables** (example values shown):
```yaml
# JuiceFS configuration
juicefs_namespace: juicefs                              # Namespace for JuiceFS CSI driver
juicefs_volume_name: thinkube-shared                   # JuiceFS volume name
juicefs_storage_class_name: juicefs-rwx               # StorageClass name for RWX volumes
juicefs_csi_version: 0.30.0                           # JuiceFS CSI driver version

# PostgreSQL configuration (inherited)
postgres_namespace: postgres                           # PostgreSQL namespace
admin_username: admin                                  # PostgreSQL admin username
postgres_database: juicefs                            # Database name for JuiceFS metadata

# SeaweedFS configuration (inherited)
seaweedfs_namespace: seaweedfs                        # SeaweedFS namespace
s3_bucket: juicefs-data                              # S3 bucket name for JuiceFS data

# Kubernetes configuration (inherited)
kubeconfig: ~/.kube/config                            # Kubernetes config file
kubectl_bin: /snap/k8s/current/bin/kubectl           # kubectl binary path
helm_bin: /snap/k8s/current/bin/helm                 # Helm binary path
domain_name: example.com                              # Base domain for dashboard (replace with your domain)
harbor_registry: registry.example.com                 # Harbor registry for CSI images (replace with your domain)
```

**Environment variables**:
- `ADMIN_PASSWORD`: Required for PostgreSQL database access

**Required infrastructure**:
1. Kubernetes cluster with k8s-snap
2. PostgreSQL deployed and accessible
3. SeaweedFS deployed with S3 API configured
4. Helm installed on control plane

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all JuiceFS deployment playbooks in sequence:
- Imports 10_deploy.yaml - Deploys JuiceFS CSI driver
- Imports 12_create_models_pvc.yaml - Creates shared ML models PVC
- Imports 17_configure_discovery.yaml - Configures service discovery

This provides a single entry point for complete JuiceFS installation.

### 10_deploy.yaml
Main deployment playbook that deploys JuiceFS distributed filesystem:

- **Kubelet Directories Preparation** (on all nodes):
  - Creates `/var/snap/k8s/common/var/lib/kubelet/plugins_registry` for CSI plugin registration

- **Namespace and Prerequisites**:
  - Creates `juicefs` namespace
  - Verifies PostgreSQL is accessible via connection test
  - Verifies SeaweedFS S3 credentials secret exists
  - Retrieves S3 access key and secret key from SeaweedFS

- **PostgreSQL Database Setup**:
  - Checks if `juicefs` database exists in PostgreSQL
  - Creates `juicefs` database if not present

- **SeaweedFS S3 Bucket Setup**:
  - Gets SeaweedFS filer pod
  - Creates `juicefs-data` bucket in SeaweedFS via weed shell

- **Helm Repository Configuration**:
  - Adds JuiceFS Helm repository (`https://juicedata.github.io/charts/`)
  - Updates Helm repository index

- **JuiceFS Configuration Secret**:
  - Creates `juicefs-secret` in juicefs namespace with:
    - Volume name: `thinkube-shared`
    - Metadata URL: PostgreSQL connection string (postgres://...)
    - Storage type: S3
    - Bucket: Internal SeaweedFS S3 endpoint with `juicefs-data` bucket
    - S3 access credentials from SeaweedFS

- **CSI Driver Deployment**:
  - Installs JuiceFS CSI driver v0.30.0 via Helm in kube-system namespace
  - Uses Harbor-mirrored images for all components:
    - juicefs-csi-driver
    - livenessprobe
    - csi-node-driver-registrar
    - csi-provisioner
    - juicefs-mount
  - Configures kubelet directory: `/var/snap/k8s/common/var/lib/kubelet`
  - Disables default StorageClass creation (will create custom one)

- **CSI Driver Health Checks**:
  - Waits for juicefs-csi-controller StatefulSet to be ready
  - Waits for juicefs-csi-node DaemonSet to be ready on all nodes

- **StorageClass Creation**:
  - Creates `juicefs-rwx` StorageClass
  - Provisioner: csi.juicefs.com
  - References juicefs-secret for provisioning and mounting
  - ReclaimPolicy: Retain
  - VolumeBindingMode: Immediate

- **JuiceFS Volume Formatting**:
  - Checks if JuiceFS volume is already formatted via `juicefs status` command
  - Cleans up orphaned S3 data if format check fails
  - Formats JuiceFS volume with PostgreSQL metadata engine and S3 backend if not already formatted

- **S3 Gateway Deployment**:
  - Deploys juicefs-gateway Deployment in juicefs namespace (1 replica)
  - Exposes JuiceFS as S3-compatible API on port 9000
  - Uses admin credentials for MinIO root user/password
  - Creates ClusterIP Service for gateway access

- **Dashboard Configuration**:
  - Patches juicefs-csi-dashboard Deployment to use English locale (LANG=en_US.UTF-8)
  - Waits for dashboard to restart after locale change

- **Dashboard Ingress**:
  - Creates Ingress for JuiceFS dashboard at `juicefs.{{ domain_name }}`
  - Uses nginx IngressClass
  - TLS via cert-manager with Let's Encrypt
  - Routes to juicefs-csi-dashboard service on port 8088

### 12_create_models_pvc.yaml
Creates shared ML models storage PVC for multi-node access:

- **AI Workloads Namespace**:
  - Creates `thinkube-ai` namespace
  - Labels: app.kubernetes.io/name=thinkube-ai, app.kubernetes.io/component=ml-infrastructure

- **Shared Models PVC**:
  - Creates `thinkube-models` PVC in thinkube-ai namespace
  - Access Mode: ReadWriteMany (multi-node access)
  - Storage Class: juicefs-rwx
  - Capacity: 500Gi
  - Labels: app.kubernetes.io/name=ml-models, managed-by=thinkube

- **PVC Binding Verification**:
  - Waits for PVC to be bound (up to 150 seconds)
  - Verifies JuiceFS provisioning succeeded

- **Recommended Directory Structure**:
  - `/models/huggingface/` - HuggingFace models
  - `/models/tensorrt/` - TensorRT engines
  - `/models/onnx/` - ONNX models

### 17_configure_discovery.yaml
Service discovery configuration playbook:

- **Service Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in kube-system namespace
  - Labels: thinkube.io/managed, thinkube.io/service-type: core, thinkube.io/service-name: juicefs

- **Service Metadata**:
  - Display name: "JuiceFS"
  - Description: "Distributed RWX filesystem for multi-node storage"
  - Category: storage
  - Icon: /icons/tk_data.svg

- **Endpoint Configuration**:
  - Dashboard: `https://juicefs.{{ domain_name }}`

- **Dependencies Declaration**:
  - postgresql (for metadata storage)
  - seaweedfs (for S3 object storage)

- **Scaling Configuration**:
  - Resource type: StatefulSet
  - Resource name: juicefs-csi-controller
  - Namespace: kube-system
  - Minimum replicas: 1

## Deployment

JuiceFS is automatically deployed by the Thinkube installer at deployment order #22. The installer executes the orchestrator playbook (00_install.yaml) which runs all required playbooks in sequence.

No manual intervention is required during installation.

## Configuration

JuiceFS is configured via inventory variables shown in the Prerequisites section. No additional manual configuration is required.

## Using JuiceFS in Your Applications

### StorageClass

JuiceFS provides a `juicefs-rwx` StorageClass for ReadWriteMany volumes:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-data
  namespace: my-app
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: juicefs-rwx
  resources:
    requests:
      storage: 10Gi
```

### Example: Multi-node Shared Volume

```yaml
---
# PVC with RWX access
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ml-models
  namespace: ai-workloads
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: juicefs-rwx
  resources:
    requests:
      storage: 50Gi
---
# Pod 1 on node A
apiVersion: v1
kind: Pod
metadata:
  name: trainer-gpu1
  namespace: ai-workloads
spec:
  nodeSelector:
    gpu: "rtx-3090"
  containers:
    - name: trainer
      image: pytorch/pytorch:latest
      volumeMounts:
        - name: models
          mountPath: /models
  volumes:
    - name: models
      persistentVolumeClaim:
        claimName: ml-models
---
# Pod 2 on node B (accessing same data)
apiVersion: v1
kind: Pod
metadata:
  name: trainer-gpu2
  namespace: ai-workloads
spec:
  nodeSelector:
    gpu: "gtx-1080ti"
  containers:
    - name: trainer
      image: pytorch/pytorch:latest
      volumeMounts:
        - name: models
          mountPath: /models
  volumes:
    - name: models
      persistentVolumeClaim:
        claimName: ml-models
```

## Data Storage

### Metadata

Metadata is stored in PostgreSQL database `juicefs` in the existing PostgreSQL instance:

```bash
# Connect to PostgreSQL
PGPASSWORD='{{ admin_password }}' psql -h postgres.{{ domain_name }} -U {{ admin_username }} -d juicefs
```

### Data

Data is stored in SeaweedFS S3 bucket `juicefs-data`:

```bash
# List bucket contents
s3cmd --access_key={{ s3_access_key }} --secret_key={{ s3_secret_key }} \
  --host=s3.{{ domain_name }} ls s3://juicefs-data/
```

## Performance Characteristics

- **Latency**: Metadata operations via PostgreSQL (low latency)
- **Throughput**: Data operations via SeaweedFS S3 (high throughput)
- **Consistency**: Strong consistency via PostgreSQL metadata
- **Scalability**: Horizontal scaling via SeaweedFS object storage

## Troubleshooting

### Check CSI Driver Status

```bash
# Check controller pod
kubectl get statefulset -n kube-system juicefs-csi-controller

# Check node pods (should be on each node)
kubectl get daemonset -n kube-system juicefs-csi-node

# View CSI driver logs
kubectl logs -n kube-system -l app.kubernetes.io/name=juicefs-csi-driver
```

### Check Volume Mount Status

```bash
# List mount pods for a volume
kubectl get pods -n kube-system -l app.kubernetes.io/name=juicefs-mount

# Check mount pod logs
kubectl logs -n kube-system <mount-pod-name>
```

### Common Issues

#### PVC stuck in Pending

**Cause**: JuiceFS secret missing or PostgreSQL/SeaweedFS not accessible

**Solution**:
```bash
# Check secret exists
kubectl get secret juicefs-secret -n juicefs

# Test PostgreSQL connection
kubectl exec -n postgres statefulset/postgresql-official -- \
  psql -U {{ admin_username }} -d juicefs -c "SELECT 1"

# Test SeaweedFS S3 API
kubectl get secret seaweedfs-s3-credentials -n seaweedfs
```

#### Mount fails with "connection refused"

**Cause**: PostgreSQL or SeaweedFS not accessible from mount pod

**Solution**:
```bash
# Check PostgreSQL service
kubectl get svc -n postgres postgresql-official

# Check SeaweedFS filer service
kubectl get svc -n seaweedfs seaweedfs-filer

# Verify DNS resolution from mount pod
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup postgresql-official.postgres.svc.cluster.local
```

## Backup and Recovery

### Metadata Backup

Metadata is stored in PostgreSQL and can be backed up using standard PostgreSQL tools:

```bash
# Backup JuiceFS metadata
kubectl exec -n postgres statefulset/postgresql-official -- \
  pg_dump -U {{ admin_username }} juicefs > juicefs-metadata-backup.sql

# Restore JuiceFS metadata
cat juicefs-metadata-backup.sql | kubectl exec -i -n postgres statefulset/postgresql-official -- \
  psql -U {{ admin_username }} juicefs
```

### Data Backup

Data is stored in SeaweedFS and can be backed up using S3 tools:

```bash
# Sync JuiceFS data to external backup
s3cmd sync s3://juicefs-data/ /backup/juicefs-data/
```

## Migration from SeaweedFS CSI

If you have existing volumes using SeaweedFS CSI driver with RWX issues:

1. **Stop applications** using the broken RWX volumes
2. **Copy data** from SeaweedFS CSI volumes to JuiceFS volumes:
   ```bash
   kubectl run -it --rm data-migration --image=busybox --restart=Never -- \
     sh -c "cp -r /old-volume/* /new-volume/"
   ```
3. **Update applications** to use new JuiceFS PVCs
4. **Verify** multi-node access works correctly
5. **Clean up** old SeaweedFS CSI volumes

## Security

- JuiceFS uses PostgreSQL for metadata (secured with admin credentials)
- SeaweedFS S3 API uses access keys (stored in Kubernetes secrets)
- All credentials stored in Kubernetes secrets (not in code)
- CSI driver runs with minimal permissions

## Additional Resources

- [JuiceFS Documentation](https://juicefs.com/docs/community/)
- [JuiceFS CSI Driver](https://github.com/juicedata/juicefs-csi-driver)
- [JuiceFS Architecture](https://juicefs.com/docs/community/architecture/)

---

🤖 This component was designed and implemented with AI assistance to solve the multi-node RWX storage challenge in Thinkube's GPU cluster.
