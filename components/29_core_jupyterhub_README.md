# JupyterHub

This component deploys [JupyterHub](https://jupyter.org/hub) - a multi-user notebook server for collaborative data science and machine learning.

## Overview

JupyterHub provides a scalable AI notebook environment with comprehensive platform integration:

- **Keycloak SSO**: Mandatory OIDC authentication with no fallback options
- **Dynamic Image Discovery**: Notebook images queried from thinkube-control at runtime
- **Dynamic Resource Allocation**: CPU, memory, GPU, and node selection via customizable profiles
- **Persistent Storage**: JuiceFS ReadWriteMany volumes for notebooks, datasets, and models
- **Service Discovery**: Automatic environment variable injection for all Thinkube services
- **GPU Support**: CUDA-enabled notebooks with automatic GPU allocation
- **Shared Workspace**: Common storage accessible across all user pods
- **Examples Repository**: Fresh examples cloned on each pod startup
- **Custom Branding**: Thinkube-themed interface with custom logo and colors

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster
- ingress (deployment order #13) - For web UI access
- acme-certificates (deployment order #12) - For TLS certificates
- keycloak (deployment order #15) - For OIDC authentication
- harbor (deployment order #16) - For custom Jupyter images
- juicefs (deployment order #22) - For ReadWriteMany persistent storage
- thinkube-control (deployment order #30) - For dynamic image and resource discovery

**Deployment order**: #29

## Prerequisites

**Required inventory variables** (example values shown):

```yaml
# JupyterHub configuration
jupyterhub_namespace: jupyterhub
jupyterhub_hostname: jupyter.example.com  # Replace with your domain
jupyterhub_chart_version: 3.5.0
jupyterhub_client_id: jupyterhub

# Storage configuration
jupyterhub_notebooks_capacity: 100Gi
jupyterhub_datasets_capacity: 500Gi
jupyterhub_models_capacity: 200Gi
jupyterhub_scratch_capacity: 100Gi
jupyterhub_examples_capacity: 1Gi

# Keycloak configuration (inherited)
keycloak_url: https://keycloak.example.com  # Replace with your domain
keycloak_realm: thinkube
admin_username: admin

# Harbor configuration (inherited)
harbor_registry: harbor.example.com  # Replace with your domain
harbor_project: library

# Kubernetes configuration (inherited)
domain_name: example.com  # Replace with your domain
kubeconfig: /var/snap/k8s/common/etc/admin.conf
kubectl_bin: /snap/k8s/current/bin/kubectl
helm_bin: /snap/k8s/current/bin/helm
```

**Required environment variables**:
- `ADMIN_PASSWORD`: Admin password for Keycloak authentication

**Required Harbor images**:
- Custom Jupyter images must be available in Harbor:
  - `{harbor_registry}/library/tk-jupyter-scipy:latest`
  - `{harbor_registry}/library/tk-jupyter-ml-cpu:latest`
  - `{harbor_registry}/library/tk-jupyter-ml-gpu:latest`

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all JupyterHub deployment playbooks in sequence:
- Imports 10_configure_keycloak.yaml - Configures Keycloak OAuth2 client
- Imports 11_deploy.yaml - Deploys JupyterHub via Helm chart
- Imports 17_configure_discovery.yaml - Configures service discovery

### 10_configure_keycloak.yaml
Keycloak OAuth2 client configuration for JupyterHub OIDC authentication:

- **Prerequisites Validation**:
  - Verifies admin_username is set
  - Verifies ADMIN_PASSWORD environment variable is available

- **Keycloak Authentication**:
  - Obtains admin token from Keycloak master realm
  - Uses password grant type with admin-cli client

- **Client Registration**:
  - Checks if jupyterhub client already exists (idempotent operation)
  - Creates new OAuth2 client only if not found:
    - Client ID: jupyterhub
    - Protocol: openid-connect
    - Redirect URI: `https://jupyter.example.com/hub/oauth_callback`
    - Standard flow enabled (with client authentication)
    - Direct access grants enabled (for token exchange)
    - Full scope allowed
    - Service accounts disabled
    - OAuth scopes: openid, profile, email

- **Client Secret Retrieval**:
  - Extracts client UUID from Keycloak API response
  - Fetches auto-generated client secret via Keycloak admin API

- **Kubernetes Secret Creation**:
  - Creates `jupyterhub` namespace if not exists
  - Creates `jupyterhub-oidc-secret` in jupyterhub namespace with:
    - client_id: jupyterhub
    - client_secret: Keycloak-generated secret

### 11_deploy.yaml
Main deployment playbook for JupyterHub with Zero to JupyterHub Helm chart:

- **OIDC Secret Retrieval**:
  - Reads `jupyterhub-oidc-secret` created by 10_configure_keycloak.yaml
  - Fails immediately if secret does not exist (no fallback authentication)

- **Namespace Setup**:
  - Creates `jupyterhub` namespace

- **Persistent Storage Volumes**:
  - Creates three JuiceFS ReadWriteMany PVCs:
    - **jupyterhub-notebooks-pvc**: 100Gi for user notebooks and projects
    - **jupyterhub-datasets-pvc**: 500Gi for shared datasets
    - **jupyterhub-models-pvc**: 200Gi for trained models
  - Storage class: juicefs-rwx (enables multi-node pod mobility)

- **TLS Certificate**:
  - Copies wildcard certificate from default namespace
  - Creates `jupyterhub-tls-secret` in jupyterhub namespace

- **Service Discovery RBAC**:
  - Creates `jupyter-service-discovery` ServiceAccount
  - Creates `jupyter-configmap-reader` ClusterRole with permissions:
    - Read ConfigMaps in all namespaces
    - Read Secrets in all namespaces
  - Creates `jupyter-service-discovery-binding` ClusterRoleBinding
  - Enables service discovery init container to query Thinkube services

- **Service Discovery Script**:
  - Creates `jupyter-service-discovery-script` ConfigMap
  - Contains shell script that:
    - Queries all ConfigMaps with label `thinkube.io/managed=true`
    - Extracts service endpoints and credentials
    - Generates `/home/jovyan/.config/thinkube/service-env.sh` with environment variables
    - Makes all Thinkube services discoverable to notebook kernels

- **Dynamic Image Discovery**:
  - Queries thinkube-control API: `http://backend.thinkube-control.svc.cluster.local:8000/api/v1/images/jupyter`
  - Verifies at least one Jupyter image is available
  - Fails deployment if thinkube-control unreachable or no images found (mandatory dependency)

- **Helm Repository**:
  - Adds JupyterHub Helm repository: `https://hub.jupyter.org/helm-chart/`
  - Updates repository index

- **Helm Values Template**:
  - Generates `jupyterhub-values.yaml` from Jinja2 template
  - **Hub Configuration**:
    - Base URL: `/hub/`
    - Concurrent spawn limit: 100
    - Admin users: `[admin_username]`
    - Shutdown on logout: true
    - Named servers: disabled
  - **Authentication** (GenericOAuthenticator):
    - Authenticator class: generic-oauth
    - Client ID: jupyterhub
    - Client secret: from jupyterhub-oidc-secret
    - OAuth callback URL: `https://jupyter.example.com/hub/oauth_callback`
    - Authorize URL: `{keycloak_url}/realms/{realm}/protocol/openid-connect/auth`
    - Token URL: `{keycloak_url}/realms/{realm}/protocol/openid-connect/token`
    - Userdata URL: `{keycloak_url}/realms/{realm}/protocol/openid-connect/userinfo`
    - Logout redirect URL: `{keycloak_url}/realms/{realm}/protocol/openid-connect/logout?redirect_uri=https://control.example.com`
    - Username claim: preferred_username
    - Scope: openid profile email
  - **Spawner Configuration** (KubeSpawner):
    - Default URL: `/lab/tree/thinkube/notebooks` (opens JupyterLab in notebooks directory)
    - Pod deletion grace period: 1 second
    - Start timeout: 120 seconds
    - HTTP timeout: 60 seconds
    - Startup command: Sources `/home/jovyan/.config/thinkube/service-env.sh` before starting jupyterhub-singleuser
  - **Dynamic Profile List** (Python function):
    - Queries thinkube-control APIs for:
      - Available Jupyter images (GET `/api/v1/images/jupyter`)
      - Cluster resource capacity (GET `/api/v1/cluster/resources`)
      - Default configuration (GET `/api/v1/jupyterhub/config`)
    - Generates single "Custom Resource Allocation" profile with 5 dropdowns:
      - **Image**: All available Jupyter images from thinkube-control
      - **Node**: Worker nodes with capacity information
      - **CPU Cores**: Dynamic range (1 to node maximum)
      - **Memory**: Dynamic range (2G to node maximum)
      - **GPU Count**: Dynamic range (0 to available GPUs)
    - Pre-spawn hook applies user selections to KubeSpawner
    - Loads defaults from thinkube-control if user selection missing
  - **Init Containers**:
    - **fix-permissions** (busybox):
      - Creates directory structure on JuiceFS volumes
      - Sets ownership to jovyan user (uid=1000, gid=100)
      - Creates `.thinkube-initialized` marker to skip on subsequent starts
    - **clone-examples** (alpine/git):
      - Clones `https://github.com/thinkube/thinkube-ai-examples.git`
      - Ensures examples are always current (fresh clone per pod)
      - Sets permissions for jovyan user
    - **service-discovery** (tk-service-discovery container):
      - Runs service-discovery-init.sh script
      - Queries all thinkube.io/managed ConfigMaps
      - Generates environment variables file
      - Mounted at `/home/jovyan/.config/thinkube/service-env.sh`
  - **Volume Mounts**:
    - `/home/jovyan/thinkube/notebooks`: jupyterhub-notebooks-pvc (persistent)
    - `/home/jovyan/thinkube/datasets`: jupyterhub-datasets-pvc (persistent)
    - `/home/jovyan/thinkube/models`: jupyterhub-models-pvc (persistent)
    - `/home/jovyan/scratch`: emptyDir with 100Gi sizeLimit (fast temporary storage)
    - `/home/jovyan/thinkube/examples-repo`: emptyDir (fresh examples clone)
    - `/home/jovyan/.config/thinkube`: emptyDir (service discovery variables)
  - **Branding**:
    - Logo file: tk_ai.svg (Thinkube logo)
    - Custom template: `/usr/local/share/jupyterhub/custom-templates/page.html`
    - CSS: `/usr/local/share/jupyterhub/static/css/thinkube.css`
    - Theme colors: --tk-teal (#006680), --tk-teal-light (#008bad), --tk-teal-dark (#004d5c)
    - Announcement banner: "Welcome to Thinkube AI Lab - Thinkube's intelligent notebook laboratory"
  - **Environment Variables**:
    - NVIDIA_DRIVER_CAPABILITIES: compute,utility
    - JUPYTER_ENABLE_LAB: yes
    - GRANT_SUDO: yes
    - JUPYTER_LAB_ENABLE_COLLABORATION: true
    - ANTHROPIC_API_KEY: from anthropic-api-key secret (if available)
  - **Lifecycle Hook** (postStart):
    - Adds service-env.sh to .bashrc for terminal access
    - Adds .secrets.env to .bashrc for thinkube-control API keys
  - **Resource Defaults** (overridden by dynamic profiles):
    - CPU limit: 4 cores, guarantee: 1 core
    - Memory limit: 8Gi, guarantee: 2Gi
    - GPU: None (users select via profile)
  - **Networking**:
    - Network policies: disabled (allow all ingress)
    - Privilege escalation: allowed (enables sudo in containers)
  - **Service Account**:
    - ServiceAccount: jupyter-service-discovery (for RBAC permissions)

- **JupyterHub Helm Deployment**:
  - Deploys or upgrades via Helm chart: jupyterhub/jupyterhub
  - Release name: jupyterhub
  - Namespace: jupyterhub
  - Values file: Generated jupyterhub-values.yaml
  - Waits for hub and proxy pods to be ready

- **Ingress**:
  - Host: `jupyter.example.com`
  - TLS enabled with jupyterhub-tls-secret
  - Annotations:
    - Proxy body size: unlimited (0)
    - Proxy read/send timeouts: 3600s (for long-running notebooks)
    - WebSocket support: enabled
  - Routes to proxy-public service port 80

- **Cleanup**:
  - Removes temporary directory containing values file

### 17_configure_discovery.yaml
Service discovery and platform integration:

- **Service Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in jupyterhub namespace
  - Labels: `thinkube.io/managed`, `thinkube.io/service-type: core`, `thinkube.io/service-name: jupyterhub`
  - Defines service metadata:
    - Display name: "Thinkube AI Lab"
    - Description: "AI-powered notebook environment for ML, agents, and data science"
    - Category: ai
    - Icon: /icons/tk_ai.svg
  - Endpoint configuration:
    - Web UI: `https://jupyter.example.com/hub/oauth_login?next=`
    - Health check: `https://jupyter.example.com/hub/api`
  - Scaling configuration: Deployment hub, minimum 1 replica, can disable

- **Code-Server Integration**:
  - Updates code-server environment variables via code_server_env_update role
  - Exports JupyterHub URL and status to code-server environment

## Deployment

JupyterHub is automatically deployed by the Thinkube installer at deployment order #29. The installer executes the orchestrator playbook (00_install.yaml) which runs all required playbooks in sequence.

No manual intervention is required during installation.

## Access Points

- **Web UI**: https://jupyter.example.com (Keycloak SSO authentication)

Replace `example.com` with your actual domain.

## Configuration

### Volume Mount Architecture

JupyterHub uses a specific volume mount strategy to preserve Python packages installed in Docker images while providing persistent storage:

```
/home/jovyan/                    # User home (NOT mounted - preserves .local/bin/)
├── .local/                      # Python packages from image (preserved)
│   └── bin/                     # Contains jupyterhub-singleuser binary
├── .config/thinkube/            # Service discovery variables (emptyDir)
│   └── service-env.sh           # Generated by init container
├── scratch/                     # Fast temporary storage (emptyDir, 100Gi)
└── thinkube/                    # Mount point for persistent volumes
    ├── notebooks/               # User's persistent notebooks (100Gi JuiceFS)
    ├── datasets/                # Shared datasets (500Gi JuiceFS)
    ├── models/                  # Shared models (200Gi JuiceFS)
    └── examples-repo/           # Fresh examples clone (emptyDir)
```

**Critical Design Decision**: Volumes mount at `/home/jovyan/thinkube/` subdirectories, NOT `/home/jovyan/`

**Why**: Docker's overlay filesystem hides everything under a mounted path. If we mount at `/home/jovyan/`, it hides `/home/jovyan/.local/bin/` where `jupyterhub-singleuser` is installed, causing pod startup failures.

**Solution**: Mount at subdirectories to preserve all image-installed packages while providing persistent storage.

### Available Images

Jupyter notebook images (versions queried dynamically from thinkube-control):

1. **tk-jupyter-scipy**: Scientific Python computing
   - Base: jupyter/scipy-notebook
   - Python 3.12
   - Includes: NumPy, Pandas, Matplotlib, Seaborn, Scikit-learn
   - All Thinkube service clients

2. **tk-jupyter-ml-cpu**: Machine Learning without GPU
   - Base: Ubuntu 24.04
   - Python 3.12
   - PyTorch CPU: 2.5.1+cpu
   - Includes: Transformers, Datasets, Accelerate
   - All Thinkube service clients

3. **tk-jupyter-ml-gpu**: Machine Learning with CUDA
   - Base: NVIDIA CUDA 12.6 with cuDNN
   - Python 3.12
   - PyTorch: 2.5.1 with CUDA 12.6
   - Includes: Transformers, Datasets, Accelerate
   - All Thinkube service clients

### Resource Selection

When spawning a notebook server, users can select:

- **Image**: Any Jupyter image available in Harbor (discovered dynamically)
- **Node**: Specific worker node to run on (shows resource capacity)
- **CPU**: 1 to maximum available cores on selected node
- **Memory**: 2Gi to maximum available memory on selected node
- **GPU**: 0 to maximum available GPUs on selected node

Defaults are loaded from thinkube-control if user doesn't specify.

### Service Discovery

All notebook kernels have automatic access to Thinkube services via environment variables:

```python
import os

# MLflow tracking
mlflow_uri = os.getenv('MLFLOW_TRACKING_URI')

# PostgreSQL database
pg_host = os.getenv('POSTGRES_HOST')
pg_port = os.getenv('POSTGRES_PORT')

# SeaweedFS S3 storage
s3_endpoint = os.getenv('S3_ENDPOINT')
s3_access_key = os.getenv('S3_ACCESS_KEY')

# And many more...
```

Variables are generated by the service-discovery init container on pod startup.

### Persistent Storage

Three shared JuiceFS volumes provide persistent storage across all pods:

- **Notebooks** (100Gi): Personal workspace, preserved across pod restarts
- **Datasets** (500Gi): Shared datasets accessible from any pod
- **Models** (200Gi): Trained models accessible from any pod

All volumes are ReadWriteMany, enabling multi-node access and pod mobility.

### Examples Repository

Example notebooks are cloned fresh on each pod startup from:
- Repository: https://github.com/thinkube/thinkube-ai-examples.git
- Location: `/home/jovyan/thinkube/examples-repo/`
- Always current (no stale cached versions)

## Troubleshooting

### Check JupyterHub pods
```bash
kubectl get pods -n jupyterhub
kubectl logs -n jupyterhub deploy/hub
kubectl logs -n jupyterhub deploy/proxy
```

### Verify OIDC configuration
```bash
# Check OIDC secret
kubectl get secret -n jupyterhub jupyterhub-oidc-secret -o yaml

# Check Keycloak client
# Navigate to Keycloak admin console → Realm → Clients → jupyterhub
# Verify redirect URI: https://jupyter.example.com/hub/oauth_callback
```

### Verify persistent volumes
```bash
# Check PVCs
kubectl get pvc -n jupyterhub

# Verify JuiceFS volumes are bound
kubectl get pvc -n jupyterhub jupyterhub-notebooks-pvc
kubectl get pvc -n jupyterhub jupyterhub-datasets-pvc
kubectl get pvc -n jupyterhub jupyterhub-models-pvc
```

### Check dynamic image discovery
```bash
# Test thinkube-control API
curl http://backend.thinkube-control.svc.cluster.local:8000/api/v1/images/jupyter

# Should return list of available images
```

### Verify service discovery
```bash
# Exec into a running notebook pod
kubectl exec -it -n jupyterhub jupyter-<username> -- /bin/bash

# Check service-env.sh was generated
cat ~/.config/thinkube/service-env.sh

# Check environment variables are sourced
source ~/.bashrc
env | grep -E '(MLFLOW|POSTGRES|S3|GITEA)'
```

### Check GPU availability
```bash
# Verify GPU node has resources
kubectl describe node <gpu-node-name>

# Check nvidia-smi in notebook pod
kubectl exec -it -n jupyterhub jupyter-<username> -- nvidia-smi
```

### Test authentication
```bash
# Access JupyterHub URL
curl -I https://jupyter.example.com  # Replace with your domain

# Should redirect to Keycloak for authentication
# Location: https://keycloak.example.com/realms/thinkube/protocol/openid-connect/auth...
```

### Check examples repository
```bash
# Verify examples were cloned
kubectl logs -n jupyterhub jupyter-<username> -c clone-examples

# Check examples directory in pod
kubectl exec -it -n jupyterhub jupyter-<username> -- ls -la /home/jovyan/thinkube/examples-repo/
```

### Volume mount issues
```bash
# Check if volumes are mounted correctly
kubectl exec -it -n jupyterhub jupyter-<username> -- df -h

# Verify directories exist
kubectl exec -it -n jupyterhub jupyter-<username> -- ls -la /home/jovyan/thinkube/

# Check permissions
kubectl exec -it -n jupyterhub jupyter-<username> -- ls -la /home/jovyan/.local/bin/
# Should show jupyterhub-singleuser executable
```

## References

- [JupyterHub Documentation](https://jupyterhub.readthedocs.io/)
- [Zero to JupyterHub with Kubernetes](https://zero-to-jupyterhub.readthedocs.io/)
- [KubeSpawner Documentation](https://jupyterhub-kubespawner.readthedocs.io/)
- [OAuthenticator Documentation](https://oauthenticator.readthedocs.io/)
