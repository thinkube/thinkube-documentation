# MLflow

This component deploys [MLflow](https://mlflow.org/) - an open-source platform for managing the ML lifecycle, including experimentation, reproducibility, deployment, and model registry.

## Overview

MLflow provides a comprehensive ML lifecycle management platform with:

- **Experiment Tracking**: Log parameters, metrics, tags, and compare runs
- **Model Registry**: Version control, stage transitions, and lineage tracking for ML models
- **Artifact Storage**: Store models, datasets, and files in S3-compatible storage
- **Keycloak SSO**: Built-in OIDC authentication with role-based access control
- **PostgreSQL Backend**: Reliable metadata storage with shared database
- **SeaweedFS S3 Storage**: Apache 2.0 licensed S3-compatible artifact storage
- **Custom Group Detection**: Keycloak plugin for automatic role mapping from realm roles
- **Shared Models PVC**: JuiceFS ReadWriteMany volume for model sharing across pods

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster
- ingress (deployment order #13) - For web UI access
- acme-certificates (deployment order #12) - For TLS certificates
- postgresql (deployment order #14) - For metadata storage
- keycloak (deployment order #15) - For SSO authentication
- harbor (deployment order #16) - For custom MLflow image
- seaweedfs (deployment order #21) - For S3-compatible artifact storage
- juicefs (deployment order #22) - For shared models storage

**Deployment order**: #28

## Prerequisites

**Required inventory variables** (example values shown):

```yaml
# MLflow configuration
mlflow_namespace: mlflow
mlflow_hostname: mlflow.example.com  # Replace with your domain
mlflow_capacity: 1Gi
mlflow_db_name: mlflow
mlflow_db_user: admin
mlflow_artifacts_bucket: mlflow
mlflow_client_id: mlflow

# Storage configuration
storage_class_name: k8s-hostpath

# PostgreSQL configuration (inherited)
postgres_namespace: postgres
postgres_release_name: postgresql-official
postgres_hostname: postgresql-official.postgres.svc.cluster.local

# SeaweedFS configuration (inherited)
seaweedfs_namespace: seaweedfs
seaweedfs_s3_secret: seaweedfs-s3-config
seaweedfs_s3_hostname: s3.example.com  # Replace with your domain

# Keycloak configuration (inherited)
keycloak_url: https://keycloak.example.com  # Replace with your domain
keycloak_realm: thinkube
admin_username: admin
auth_realm_username: tkadmin

# Harbor configuration (inherited)
harbor_registry: harbor.example.com  # Replace with your domain
harbor_project: library
harbor_robot_name: thinkube-deployer

# Kubernetes configuration (inherited)
domain_name: example.com  # Replace with your domain
kubeconfig: /var/snap/k8s/common/etc/admin.conf
kubectl_bin: /snap/k8s/current/bin/kubectl
primary_ingress_class: nginx
```

**Required environment variables**:
- `ADMIN_PASSWORD`: Admin password for PostgreSQL, Keycloak, and MLflow authentication

**Required Harbor image**:
- Custom MLflow image with OIDC support must be available at: `{harbor_registry}/library/mlflow-custom:latest`

**Required in ~/.env**:
- `HARBOR_ROBOT_TOKEN`: Harbor robot account token (created during Harbor setup)

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all MLflow deployment playbooks in sequence:
- Imports 10_configure_keycloak.yaml - Configures Keycloak OAuth2 client
- Imports 11_deploy.yaml - Deploys MLflow tracking server
- Imports 17_configure_discovery.yaml - Configures service discovery

### 10_configure_keycloak.yaml
Keycloak OAuth2 client configuration for MLflow OIDC authentication:

- **Realm Roles Creation**:
  - Creates realm roles via keycloak/keycloak_bulk_roles role:
    - `mlflow-admin`: MLflow administrator role
    - `mlflow-user`: MLflow standard user role

- **Keycloak Client Setup**:
  - Creates MLflow OIDC client via keycloak/keycloak_setup role:
    - Client ID: mlflow
    - Protocol: openid-connect
    - Standard flow enabled, implicit flow disabled
    - Direct access grants enabled
    - Public client: false
    - Redirect URIs:
      - `https://mlflow.example.com/*`
      - `https://mlflow.example.com/oauth2/callback`
      - `https://mlflow.example.com/callback`
    - Web origins: `https://mlflow.example.com`, `+`
    - Access token lifespan: 3600 seconds
    - Post-logout redirect URIs: `+`
    - Default client scopes: email, profile, roles, openid, offline_access
    - Optional client scopes: address, phone

- **Protocol Mappers**:
  - **mlflow-realm-role-mapper**: Maps realm roles to token claims
    - Claim name: realm_access.roles
    - Included in ID token, access token, userinfo token
    - Multivalued: true
  - **mlflow-audience-mapper**: Adds audience to access token
    - Included client audience: mlflow
    - Custom audience: mlflow
    - Access token only
  - **mlflow-client-role-mapper**: Maps client-specific roles
    - Claim name: resource_access.${client_id}.roles
    - Client ID: mlflow
    - Included in ID token, access token, userinfo token

- **User Role Assignment**:
  - Assigns mlflow-admin role to auth_realm_username user

### 11_deploy.yaml
Main deployment playbook for MLflow tracking server:

- **Harbor Credentials**:
  - Loads HARBOR_ROBOT_TOKEN from ~/.env file
  - Sets Harbor robot username: `robot${harbor_robot_name}`
  - Verifies token is available before deployment

- **Namespace Setup**:
  - Creates `mlflow` namespace

- **Keycloak Integration**:
  - Obtains Keycloak admin token for API access
  - Retrieves MLflow client UUID by client ID
  - Fetches OAuth2 client secret from Keycloak API
  - Stores client secret as fact for deployment configuration

- **TLS Certificate**:
  - Retrieves wildcard certificate from default namespace
  - Copies to mlflow namespace as `mlflow-tls-secret`

- **Harbor Pull Secret**:
  - Creates `harbor-registry-secret` in mlflow namespace
  - Type: kubernetes.io/dockerconfigjson
  - Contains base64-encoded Docker config with Harbor credentials

- **Database Setup**:
  - Checks if mlflow database exists in PostgreSQL
  - Creates database if not exists using psql command
  - Database name: mlflow
  - Owner: admin user (from ADMIN_PASSWORD)

- **SeaweedFS Integration**:
  - Retrieves S3 credentials from `seaweedfs-s3-config` secret in seaweedfs namespace
  - Extracts access_key and secret_key
  - Creates mlflow bucket in SeaweedFS using s3cmd:
    - Bucket name: mlflow
    - Endpoint: `https://{seaweedfs_s3_hostname}`
    - Signature: v2
    - SSL verification disabled (internal traffic)

- **Kubernetes Secrets**:
  - **mlflow-db-secret**: PostgreSQL connection details
    - DB_HOST: `{postgres_release_name}.{postgres_namespace}.svc.cluster.local`
    - DB_PORT: 5432
    - DB_NAME: mlflow
    - DB_USER: admin username
    - DB_PASSWORD: admin password
  - **mlflow-s3-secret**: SeaweedFS S3 credentials
    - AWS_ACCESS_KEY_ID: S3 access key
    - AWS_SECRET_ACCESS_KEY: S3 secret key
    - S3_ENDPOINT_URL: `http://seaweedfs-filer.{seaweedfs_namespace}.svc.cluster.local:8333`
  - **oauth2-proxy-secret**: OIDC client credentials
    - client-id: mlflow
    - client-secret: Keycloak client secret

- **Storage Volumes**:
  - **mlflow-storage PVC**: Local artifacts storage
    - Capacity: 1Gi
    - Access mode: ReadWriteOnce
    - Storage class: k8s-hostpath
  - **thinkube-models PVC**: Shared models storage
    - Capacity: 500Gi
    - Access mode: ReadWriteMany
    - Storage class: juicefs-rwx
    - Labels: app.kubernetes.io/name=ml-models, managed-by=thinkube

- **Custom Group Detection Plugin**:
  - Creates `mlflow-group-plugin` ConfigMap
  - Contains custom Python plugin: mlflow_keycloak_groups.py
  - Enables automatic role detection from Keycloak realm roles

- **MLflow Deployment**:
  - Image: `{harbor_registry}/library/mlflow-custom:latest`
  - Image pull secret: harbor-registry-secret
  - Replicas: 1
  - Command: `mlflow server`
  - Arguments:
    - `--host=0.0.0.0`
    - `--port=5000`
    - `--backend-store-uri=postgresql://{user}:{password}@{host}:{port}/{db}`
    - `--default-artifact-root=file:///models/mlflow-artifacts`
    - `--app-name=oidc-auth`
  - Volume mounts:
    - `/mlflow/local-artifacts`: mlflow-storage PVC
    - `/models`: thinkube-models PVC (JuiceFS)
    - `/mlflow/plugins`: mlflow-group-plugin ConfigMap
  - Environment variables:
    - **PYTHONPATH**: /mlflow/plugins
    - **Database**: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD (from mlflow-db-secret)
    - **S3 Storage**: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, MLFLOW_S3_ENDPOINT_URL (from mlflow-s3-secret)
    - **S3 Configuration**: MLFLOW_S3_IGNORE_TLS=true
    - **OIDC Configuration**:
      - OIDC_DISCOVERY_URL: `{keycloak_url}/realms/{realm}/.well-known/openid-configuration`
      - OIDC_CLIENT_ID: mlflow
      - OIDC_CLIENT_SECRET: from oauth2-proxy-secret
      - OIDC_PROVIDER_DISPLAY_NAME: "Login with Keycloak"
      - OIDC_SCOPE: "openid profile email"
      - OIDC_REDIRECT_URI: `https://{mlflow_hostname}/callback`
      - OIDC_GROUP_NAME: mlflow-user
      - OIDC_ADMIN_GROUP_NAME: mlflow-admin
      - OIDC_GROUPS_ATTRIBUTE: realm_access.roles
      - OIDC_GROUP_DETECTION_PLUGIN: mlflow_keycloak_groups
      - AUTOMATIC_LOGIN_REDIRECT: true
      - DEFAULT_LANDING_PAGE_IS_PERMISSIONS: false
    - **SECRET_KEY**: Random 32-character string
  - Ports: 5000 (HTTP)
  - Liveness probe: HTTP GET / on port 5000, 60s initial delay, 5s timeout
  - Readiness probe: HTTP GET / on port 5000, 30s initial delay, 5s timeout
  - Resource requests: 100m CPU, 256Mi memory
  - Resource limits: 500m CPU, 1Gi memory

- **Service**:
  - ClusterIP service exposing port 5000
  - Selector: app=mlflow

- **Ingress**:
  - Host: `mlflow.example.com`
  - TLS enabled with mlflow-tls-secret
  - Annotation: proxy-body-size unlimited (0)
  - IngressClass: nginx
  - Routes to mlflow service port 5000

### 17_configure_discovery.yaml
Service discovery and code-server integration:

- **MLflow Client Secret Retrieval**:
  - Retrieves oauth2-proxy-secret from mlflow namespace
  - Extracts client-secret for environment variable configuration

- **Service Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in mlflow namespace
  - Labels: `thinkube.io/managed`, `thinkube.io/service-type: core`, `thinkube.io/service-name: mlflow`
  - Defines service metadata:
    - Display name: "MLflow"
    - Description: "ML experiment tracking and model registry"
    - Category: ai
    - Icon: /icons/tk_ai.svg
  - Endpoint configuration:
    - Web UI: `https://mlflow.example.com`
    - Health check: `https://mlflow.example.com/health`
  - Dependencies: postgres, seaweedfs, keycloak
  - Scaling configuration: Deployment mlflow, minimum 1 replica, can disable
  - Environment variables:
    - MLFLOW_TRACKING_URI: `https://mlflow.example.com`
    - MLFLOW_AUTH_USERNAME: auth_realm_username
    - MLFLOW_AUTH_PASSWORD: ADMIN_PASSWORD
    - MLFLOW_KEYCLOAK_TOKEN_URL: Keycloak token endpoint
    - MLFLOW_KEYCLOAK_CLIENT_ID: mlflow
    - MLFLOW_CLIENT_SECRET: from oauth2-proxy-secret

- **Code-Server Integration**:
  - Updates code-server environment variables via code_server_env_update role
  - Creates MLflow authentication helper scripts from templates:
    - **mlflow-auth.sh**: Bash version for obtaining Keycloak tokens
    - **mlflow-auth.fish**: Fish shell version
  - Copies scripts to code-server pod at `/home/thinkube/`
  - Scripts enable programmatic MLflow API access with Keycloak authentication

## Deployment

MLflow is automatically deployed by the Thinkube installer at deployment order #28. The installer executes the orchestrator playbook (00_install.yaml) which runs all required playbooks in sequence.

No manual intervention is required during installation.

## Access Points

- **Web UI**: https://mlflow.example.com (Keycloak SSO authentication)

Replace `example.com` with your actual domain.

## Configuration

### Authentication

Users must have one of the following Keycloak realm roles to access MLflow:
- `mlflow-admin`: Full administrative access to all experiments and models
- `mlflow-user`: Standard user access for creating experiments and tracking runs

The auth_realm_username user is automatically assigned the mlflow-admin role during deployment.

### Python Client Usage

Use MLflow from Python code with automatic Keycloak authentication:

```python
import mlflow

# Set tracking URI
mlflow.set_tracking_uri("https://mlflow.example.com")  # Replace with your domain

# Create experiment
mlflow.create_experiment("my-experiment")
mlflow.set_experiment("my-experiment")

# Start a run
with mlflow.start_run():
    # Log parameters
    mlflow.log_param("learning_rate", 0.01)
    mlflow.log_param("batch_size", 32)

    # Log metrics
    mlflow.log_metric("accuracy", 0.95)
    mlflow.log_metric("loss", 0.05)

    # Log model
    mlflow.sklearn.log_model(model, "model")
```

### Keycloak Token Authentication

For programmatic API access from code-server, use the provided helper scripts:

```bash
# Bash
source ~/mlflow-auth.sh
# Sets MLFLOW_TRACKING_TOKEN environment variable

# Fish shell
source ~/mlflow-auth.fish
# Sets MLFLOW_TRACKING_TOKEN environment variable
```

### Model Registry

Register and manage models:

```python
import mlflow

# Register model from run
mlflow.register_model(
    model_uri="runs:/{run_id}/model",
    name="my-model"
)

# Transition model stage
from mlflow.tracking import MlflowClient
client = MlflowClient()
client.transition_model_version_stage(
    name="my-model",
    version=1,
    stage="Production"
)
```

### Artifact Storage

Artifacts are automatically stored in SeaweedFS S3:

- **Bucket**: mlflow
- **Location**: `/models/mlflow-artifacts` (JuiceFS shared storage)
- **Local cache**: `/mlflow/local-artifacts` (1Gi PVC)

Artifacts include:
- Model files and weights
- Training datasets
- Metrics plots and visualizations
- Configuration files

## Troubleshooting

### Check MLflow pods
```bash
kubectl get pods -n mlflow
kubectl logs -n mlflow deploy/mlflow
```

### Verify database connection
```bash
# Check database secret
kubectl get secret -n mlflow mlflow-db-secret -o yaml

# Test database connection
kubectl run -it --rm psql --image=postgres:15 --restart=Never -- \
  psql -h postgresql-official.postgres.svc.cluster.local -U admin -d mlflow  # Replace admin with your username
```

### Verify S3 storage
```bash
# Check S3 secret
kubectl get secret -n mlflow mlflow-s3-secret -o yaml

# Test SeaweedFS bucket access
s3cmd --config=/dev/null \
  --access_key="<access-key>" \
  --secret_key="<secret-key>" \
  --host="https://s3.example.com" \  # Replace with your domain
  --no-ssl-certificate-check \
  --signature-v2 \
  ls s3://mlflow/
```

### Verify OIDC configuration
```bash
# Check OAuth2 secret
kubectl get secret -n mlflow oauth2-proxy-secret -o yaml

# Check Keycloak client in admin console
# Navigate to Realm → Clients → mlflow
# Verify redirect URIs and scopes are correct
```

### Check custom group detection plugin
```bash
# Verify ConfigMap exists
kubectl get configmap -n mlflow mlflow-group-plugin -o yaml

# Check plugin is loaded
kubectl logs -n mlflow deploy/mlflow | grep keycloak_groups
```

### Test MLflow API
```bash
# From code-server, get authentication token
source ~/mlflow-auth.sh

# Test API endpoint
curl -H "Authorization: Bearer $MLFLOW_TRACKING_TOKEN" \
  https://mlflow.example.com/api/2.0/mlflow/experiments/list  # Replace with your domain
```

### Check role assignments
```bash
# Login to Keycloak admin console
# Navigate to Realm → Users → Select user → Role Mappings
# Verify mlflow-admin or mlflow-user realm role is assigned
```

### Verify PVC mounts
```bash
# Check PVCs
kubectl get pvc -n mlflow

# Verify mlflow-storage PVC
kubectl get pvc -n mlflow mlflow-storage

# Verify thinkube-models PVC (JuiceFS)
kubectl get pvc -n mlflow thinkube-models
```

## References

- [MLflow Documentation](https://mlflow.org/docs/latest/index.html)
- [MLflow Tracking](https://mlflow.org/docs/latest/tracking.html)
- [MLflow Model Registry](https://mlflow.org/docs/latest/model-registry.html)
- [MLflow Python API](https://mlflow.org/docs/latest/python_api/index.html)
