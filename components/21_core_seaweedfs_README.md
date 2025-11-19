# SeaweedFS Deployment

SeaweedFS is a distributed file storage system with S3-compatible API for object storage.

## Overview

SeaweedFS provides:
- S3-compatible API for artifact storage
- Distributed file storage with replication
- Web UI with file browser
- WebDAV support
- POSIX-compatible FUSE mount

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6)
- ingress (deployment order #13) - For web UI and S3 API access
- acme-certificates (deployment order #12) - For TLS certificates
- keycloak (deployment order #15) - For OAuth2 authentication on web UI

**Deployment order**: #21

## Prerequisites

**Required inventory variables** (example values shown):

```yaml
seaweedfs_namespace: seaweedfs
domain_name: example.com  # Replace with your domain
admin_username: admin  # Keycloak admin username for OAuth2 proxy
```

## Components

1. **Master Server**: Manages cluster topology and metadata
2. **Volume Server**: Stores actual file data
3. **Filer**: Provides S3 API, WebDAV, and web UI
4. **OAuth2 Proxy**: Keycloak integration for web UI authentication

## Implementation Details

### Secure S3 Authentication

The deployment implements a secure approach to S3 authentication that addresses the security concern of credentials being stored in plaintext in SeaweedFS's persistent storage:

1. **Helm Chart Limitation**: The SeaweedFS Helm chart v4.0.0 doesn't support passing the `-s3.config` parameter
2. **Post-Deployment Patching**: After Helm deployment, the playbook patches the StatefulSet to:
   - Add the `-s3.config=/etc/seaweedfs/s3-config.json` parameter to the filer command
   - Mount the S3 configuration from a Kubernetes secret as a volume
   - Check for existing volumes/mounts to avoid duplicates during re-runs
3. **Fallback Mechanism**: The configuration playbook checks if the config file is mounted and only uses `s3.configure` command as a fallback

This implementation ensures that S3 credentials are managed by Kubernetes RBAC and not stored in the filer's persistent volume.

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all SeaweedFS deployment playbooks in sequence:
- Imports 10_deploy.yaml - Deploys SeaweedFS cluster
- Imports 15_configure.yaml - Configures S3 access and creates buckets
- Imports 17_configure_discovery.yaml - Configures service discovery

**Note**: CSI driver deployment was removed - JuiceFS now provides RWX storage using SeaweedFS S3 API instead, as the SeaweedFS CSI FUSE driver has multi-node consistency issues.

### 10_deploy.yaml
Main deployment playbook that deploys SeaweedFS distributed storage:

- **Namespace Setup**:
  - Creates `seaweedfs` namespace

- **Helm Deployment**:
  - Adds SeaweedFS Helm repository
  - Deploys SeaweedFS v4.0.0 via Helm chart
  - Configures components:
    - Master server: Manages cluster topology and metadata
    - Volume server: Stores actual file data with replication
    - Filer: Provides S3 API, WebDAV, and web UI
  - Configures persistent storage for volumes

- **S3 Security Configuration** (post-Helm patching):
  - Creates Kubernetes secret `seaweedfs-s3-config` with S3 credentials
  - Patches filer StatefulSet to mount S3 config from secret
  - Adds `-s3.config=/etc/seaweedfs/s3-config.json` parameter to filer command
  - Ensures credentials are not stored in persistent volume

- **OAuth2 Proxy Deployment**:
  - Deploys OAuth2 proxy for Keycloak integration
  - Configures authentication for web UI access
  - Creates cookie secret for session management

- **Ingress Configuration**:
  - Web UI ingress: `seaweedfs.{{ domain_name }}` (Keycloak protected via OAuth2 proxy)
  - S3 API ingress: `s3.{{ domain_name }}` (API key authentication)
  - WebDAV ingress: `webdav.{{ domain_name }}` (if enabled)

### 15_configure.yaml
S3 configuration playbook that sets up S3 access and buckets:

- **S3 Credential Verification**:
  - Checks if S3 config file is mounted in filer pod
  - Verifies credentials from seaweedfs-s3-config secret

- **Initial Bucket Creation**:
  - Creates buckets for platform services:
    - `argo-artifacts`: Argo Workflows artifact storage
    - `harbor-storage`: Harbor registry backend storage
    - Other application buckets as configured

- **Argo Workflows Integration**:
  - Configures Argo Workflows to use SeaweedFS for artifact storage
  - Updates Argo ConfigMap with S3 endpoint and credentials

### 17_configure_discovery.yaml
Service discovery configuration playbook that creates discovery metadata:

- **Service Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in seaweedfs namespace
  - Labels: `thinkube.io/managed`, `thinkube.io/service-type: core`, `thinkube.io/service-name: seaweedfs`
  - Defines service metadata:
    - Display name: "SeaweedFS"
    - Category: storage
    - Icon: /icons/tk_data.svg
  - Endpoint configuration:
    - Web UI: https://seaweedfs.{{ domain_name }}
    - S3 API: https://s3.{{ domain_name }}
    - Internal filer: http://seaweedfs-filer.seaweedfs.svc.cluster.local:8333
  - Scaling configuration: StatefulSet for master, volume, filer components

## Deployment

SeaweedFS is automatically deployed by the Thinkube installer at deployment order #21. The installer executes the orchestrator playbook (00_install.yaml) which runs all required playbooks in sequence.

No manual intervention is required during installation.

## Access Points

- **Web UI**: https://seaweedfs.{{ domain_name }} (Keycloak protected)
- **S3 API**: https://s3.{{ domain_name }} (API key required)
- **WebDAV**: https://webdav.{{ domain_name }} (if enabled)

## S3 Configuration

### Security Implementation

SeaweedFS S3 credentials are securely managed through Kubernetes secrets:

1. **Credentials Storage**: S3 access credentials are stored in the `seaweedfs-s3-config` secret
2. **Config File Mount**: The S3 configuration is mounted as `/etc/seaweedfs/s3-config.json` in the filer pod
3. **No Persistent Storage**: Unlike the default `s3.configure` command approach, credentials are NOT stored in `/etc/iam/identity.json` in the persistent volume
4. **Post-Deployment Patching**: The deployment playbook patches the SeaweedFS StatefulSet after Helm deployment to add the `-s3.config` parameter

This approach ensures credentials remain in Kubernetes secrets and are not exposed in persistent storage.

### For Applications

Use the internal endpoint for better performance:
```yaml
endpoint: http://seaweedfs-filer.seaweedfs.svc.cluster.local:8333
access_key: <from seaweedfs-s3-config secret>
secret_key: <from seaweedfs-s3-config secret>
```

### For External Access

```bash
# Get credentials from Kubernetes secret
kubectl get secret -n seaweedfs seaweedfs-s3-config -o jsonpath='{.data.access_key}' | base64 -d
kubectl get secret -n seaweedfs seaweedfs-s3-config -o jsonpath='{.data.secret_key}' | base64 -d

# Configure s3cmd
cat > ~/.s3cfg << EOF
[default]
access_key = <access_key>
secret_key = <secret_key>
host_base = s3.{{ domain_name }}
host_bucket = s3.{{ domain_name }}/%(bucket)s
use_https = True
check_ssl_certificate = False
signature_v2 = True
use_path_style = True
EOF

# List buckets
s3cmd ls

# Upload file
s3cmd put file.txt s3://bucket-name/
```

## Integration Examples

### Argo Workflows
The configuration playbook automatically sets up Argo to use SeaweedFS for artifacts. The `13_setup_artifacts.yaml` playbook in the Argo Workflows component:
- Retrieves S3 credentials from the SeaweedFS secret
- Creates the `argo-artifacts` bucket
- Configures the artifact repository with path-style URLs
- Updates the Argo ConfigMap with SeaweedFS endpoints

### Harbor Registry
```yaml
storage:
  s3:
    accesskey: <access_key>
    secretkey: <secret_key>
    region: us-east-1
    endpoint: http://seaweedfs-filer.seaweedfs.svc.cluster.local:8333
    bucket: harbor-storage
    secure: false
    v4auth: true
```

### Backup Scripts
```bash
#!/bin/bash
# Backup to SeaweedFS
s3cmd sync /data/ s3://backup/$(date +%Y%m%d)/
```

## Monitoring

Check component health:
```bash
# Master status
curl http://seaweedfs-master.seaweedfs.svc.cluster.local:9333/cluster/status

# Volume status  
curl http://seaweedfs-volume.seaweedfs.svc.cluster.local:8080/status

# Filer metrics
curl http://seaweedfs-filer.seaweedfs.svc.cluster.local:8888/metrics
```

## Scaling

To add more volume servers:
1. Edit `volume_replicas` in the deployment playbook
2. Re-run the deployment
3. SeaweedFS automatically rebalances data

## Troubleshooting

### Check logs
```bash
# Master logs
kubectl logs -n seaweedfs sts/seaweedfs-master

# Volume logs
kubectl logs -n seaweedfs sts/seaweedfs-volume

# Filer logs (Note: filer is also a StatefulSet after patching)
kubectl logs -n seaweedfs sts/seaweedfs-filer
```

### Verify S3 Config Mount
```bash
# Check if config file is mounted
kubectl exec -n seaweedfs seaweedfs-filer-0 -- ls -la /etc/seaweedfs/s3-config.json

# Verify S3 config parameter in running process
kubectl exec -n seaweedfs seaweedfs-filer-0 -- ps aux | grep s3.config

# Check that NO identity.json exists in persistent storage
kubectl exec -n seaweedfs seaweedfs-filer-0 -- ls -la /etc/iam/
# Should return: No such file or directory
```

### S3 API issues
- Ensure bucket exists
- Check credentials in secret: `kubectl get secret -n seaweedfs seaweedfs-s3-config -o yaml`
- Verify endpoint URL (internal vs external)
- Use `signature_v2 = True` and `use_path_style = True` for s3cmd
- For signature errors, ensure the secret key matches what's in the mounted config

### Storage issues
- Check PVC status: `kubectl get pvc -n seaweedfs`
- Verify volume server has space
- Check replication settings

### Patching Issues
If the StatefulSet patching fails:
1. Check for duplicate volumes/mounts
2. Verify the original command format
3. Check rollout status: `kubectl rollout status sts/seaweedfs-filer -n seaweedfs`

## License

SeaweedFS is Apache 2.0 licensed, making it suitable for commercial use without concerns about AGPL requirements.