# PostgreSQL Database

This component deploys a PostgreSQL database server in Kubernetes, providing a centralized data store for platform services including Keycloak, Harbor, MLflow, and other components.

## Overview

PostgreSQL is deployed as a StatefulSet with persistent storage, providing reliable database services for the Thinkube platform. External access is enabled via TCP passthrough on the primary NGINX ingress controller.

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster with k8s-hostpath storage class
- acme-certificates (deployment order #12) - Wildcard TLS certificate in default namespace
- ingress (deployment order #13) - Primary NGINX ingress controller for TCP passthrough

**Required by** (which components depend on this):
- keycloak - Identity and access management
- harbor - Container registry
- mlflow - Machine learning platform
- Other platform services requiring PostgreSQL

**Deployment order**: #14

See [Deployment Dependency Graph](https://github.com/thinkube/thinkube-documentation/blob/main/architecture/deployment-dependency-graph.md) for complete dependency tree.

## Features

- Official PostgreSQL 18-alpine image from AWS ECR (no Docker Hub dependency)
- StatefulSet with persistent storage via volumeClaimTemplates
- TCP passthrough enabled via NGINX ingress controller
- Database persistence across pod restarts
- Configurable resource limits (CPU: 250m-1000m, Memory: 256Mi-1Gi)
- Comprehensive tests for functionality verification
- Clean rollback procedure

## Prerequisites

**Required inventory variables**:
```yaml
# PostgreSQL configuration
postgres_hostname: postgres.thinkube.com  # DNS name for external access
postgres_namespace: postgres               # Namespace for PostgreSQL deployment
admin_username: admin                      # PostgreSQL admin username
admin_password: <set-via-env>              # Set via ADMIN_PASSWORD env var

# Ingress configuration (inherited)
ingress_namespace: ingress                 # Primary ingress namespace
primary_ingress_service: primary-ingress-ingress-nginx-controller

# Domain configuration
domain_name: thinkube.com                  # Base domain for certificate lookup
```

**Environment variables**:
- `ADMIN_PASSWORD`: PostgreSQL admin password (required)

**Required infrastructure**:
1. Kubernetes cluster with k8s-hostpath storage class
2. Wildcard TLS certificate in default namespace (from acme-certificates)
3. Primary NGINX ingress controller deployed (from ingress playbook)

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all PostgreSQL deployment playbooks in sequence:
- Imports 10_deploy.yaml - Deploys PostgreSQL StatefulSet
- Imports 17_configure_discovery.yaml - Configures service discovery

### 10_deploy.yaml
Main deployment playbook that deploys PostgreSQL database:

- **Namespace and Certificate Setup**:
  - Creates `postgres` namespace
  - Copies wildcard certificate from default namespace to postgres namespace as `postgres-tls-secret`
  - Verifies ADMIN_PASSWORD environment variable is set

- **StatefulSet Deployment**:
  - Deploys PostgreSQL 18-alpine from AWS ECR (`public.ecr.aws/docker/library/postgres:18-alpine`)
  - Creates StatefulSet with 1 replica
  - Configures volumeClaimTemplates (PVC created automatically by StatefulSet):
    - Storage class: k8s-hostpath
    - Size: 10Gi
    - Access mode: ReadWriteOnce
    - Mount path: `/var/lib/postgresql`
  - Environment variables: POSTGRES_USER (admin_username), POSTGRES_PASSWORD (admin_password), POSTGRES_DB (postgres), PGDATA
  - Resource limits: CPU 250m-1000m, Memory 256Mi-1Gi
  - Security context: fsGroup 999 (PostgreSQL UID)

- **Service Creation**:
  - Creates ClusterIP service `postgresql-official` in postgres namespace
  - Exposes port 5432 for internal cluster access

- **Health Verification**:
  - Waits for StatefulSet rollout
  - Waits for pod to reach Running state
  - Checks for error states (CrashLoopBackOff, ImagePullBackOff)
  - Additional 10-second pause for initialization

- **TCP Passthrough Configuration** (for external access):
  - Creates/updates ConfigMap `nginx-ingress-tcp-k8s-conf` in ingress namespace
  - Maps external port 5432 → postgres/postgresql-official:5432
  - Patches primary ingress controller Deployment to expose port 5432 with hostPort
  - Patches primary ingress controller Service to add TCP port 5432
  - Waits 15 seconds for ingress changes to propagate

### 17_configure_discovery.yaml
Service discovery configuration playbook that creates discovery metadata:

- **Service Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in postgres namespace
  - Labels: `thinkube.io/managed`, `thinkube.io/service-type: core`, `thinkube.io/service-name: postgresql`
  - Defines service metadata:
    - Display name: "PostgreSQL"
    - Category: storage
    - Icon: /icons/tk_data.svg
  - Endpoint configuration:
    - Database URL: `postgresql://postgresql-official.postgres.svc.cluster.local:5432`
    - Health URL: Same with /postgres database
  - Scaling configuration: StatefulSet `postgresql-official` in postgres namespace, min 1 replica
  - Environment variables for client connection:
    - POSTGRES_HOST: postgres.{{ domain_name }}
    - POSTGRES_PORT: 5432
    - POSTGRES_USER: {{ admin_username }}
    - POSTGRES_PASSWORD: {{ admin_password }}
    - POSTGRES_DB: mydatabase

## Deployment

```bash
# Set admin password
export ADMIN_PASSWORD="your-secure-password"

# Deploy PostgreSQL
cd ~/thinkube
./scripts/run_ansible.sh ansible/40_thinkube/core/postgresql/10_deploy.yaml

# Test the deployment
./scripts/run_ansible.sh ansible/40_thinkube/core/postgresql/18_test.yaml

# Rollback if needed (WARNING: destroys data)
./scripts/run_ansible.sh ansible/40_thinkube/core/postgresql/19_rollback.yaml
```

## Accessing PostgreSQL

### From within the cluster

Applications can access PostgreSQL using the service name:

```
Host: postgresql-official.postgres
Port: 5432
User: {{ admin_username }}
Password: {{ admin_password }}
Database: mydatabase
```

### From outside the cluster

External access is available via the ingress TCP passthrough:

```
Host: {{ postgres_hostname }}
Port: 5432
User: {{ admin_username }}
Password: {{ admin_password }}
Database: mydatabase
```

### Sample connection command

```bash
PGPASSWORD='{{ admin_password }}' psql -h {{ postgres_hostname }} -p 5432 -U {{ admin_username }} -d mydatabase
```

## Data Persistence

PostgreSQL data is stored in a persistent volume created via StatefulSet volumeClaimTemplates:
- Volume name: `data-postgresql-official-0` (auto-generated by StatefulSet)
- Storage class: `k8s-hostpath`
- Size: 10Gi
- Access mode: ReadWriteOnce
- Mount path: `/var/lib/postgresql`

The StatefulSet automatically creates and manages the PVC, ensuring data survives pod restarts and redeployments.

**Important**: The rollback playbook will DELETE the PVC and all data. Always backup before running rollback.

For complete data protection, implement a backup strategy using:

1. `pg_dump` for logical backups
2. Volume snapshots for physical backups
3. PostgreSQL replication for high availability

## Backup Strategy

### Logical Backups

```bash
# Create a backup
kubectl exec -n postgres postgresql-official-0 -- \
  pg_dump -U {{ admin_username }} -d mydatabase > backup.sql

# Restore from backup
cat backup.sql | kubectl exec -i -n postgres postgresql-official-0 -- \
  psql -U {{ admin_username }} -d mydatabase
```

### Volume Snapshots

If your storage class supports snapshots:

```bash
# Create a snapshot of the PostgreSQL PVC
kubectl create -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-data-snapshot
  namespace: postgres
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: postgres-data
EOF
```

## Resource Limits

The deployment includes the following resource limits:

- CPU: 250m request, 1000m limit
- Memory: 256Mi request, 1Gi limit
- Storage: 10Gi (configurable)

## Security Notes

- **Authentication**: PostgreSQL admin credentials use `admin_username` and `admin_password` variables
- **Password Management**: Admin password must be set via `ADMIN_PASSWORD` environment variable
- **Certificate Storage**: Wildcard TLS certificate is copied to postgres namespace as `postgres-tls-secret` (though not currently used for PostgreSQL connections)
- **Network Access**:
  - Internal: Via ClusterIP service `postgresql-official.postgres:5432`
  - External: Via TCP passthrough on primary ingress controller port 5432
- **Security Context**: Sets fsGroup 999 (PostgreSQL UID) for proper file permissions
- **Resource Limits**: Enforced CPU and memory limits prevent resource exhaustion