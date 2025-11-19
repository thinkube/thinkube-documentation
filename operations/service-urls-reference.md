# Thinkube Service URLs Reference

This document provides a comprehensive reference of all Thinkube services, their external URLs, protocols, and access methods.

## Purpose

All Thinkube services are exposed via external URLs (not internal Kubernetes DNS) to:
- **Validate the complete stack**: DNS → Ingress → TLS → Service → Backend
- **Enable external access**: Services accessible from outside the cluster
- **Simplify testing**: Tests use real-world URLs that users actually access
- **Ensure security**: All traffic goes through TLS-secured ingress

## URL Pattern

All services follow the pattern: `https://{service}.{domain_name}` or specific subdomains.

The `{domain_name}` is configured in your inventory (e.g., `thinkube.com`).

---

## Core Infrastructure Services

These services provide foundational infrastructure and MUST be tested.

### PostgreSQL
- **Purpose**: Primary relational database
- **URL**: `postgres.{domain_name}:5432`
- **Protocol**: PostgreSQL wire protocol (TCP passthrough via NGINX)
- **Authentication**: Username/password
- **Python SDK**: `psycopg2-binary`
- **Testing**: Required (core)

### Keycloak
- **Purpose**: Identity and access management (SSO/OIDC)
- **URL**: `https://auth.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: Admin credentials
- **Python SDK**: `requests` (REST API)
- **Testing**: Required (core)

### SeaweedFS
- **Purpose**: S3-compatible object storage
- **URLs**:
  - S3 API: `https://s3.{domain_name}`
  - Admin UI: `https://seaweedfs.{domain_name}`
- **Protocol**: HTTPS (S3-compatible API)
- **Authentication**: AWS access key/secret
- **Python SDK**: `boto3`
- **Testing**: Required (core)

### PgAdmin
- **Purpose**: PostgreSQL administration interface
- **URL**: `https://pgadmin.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: OAuth2 via Keycloak
- **Testing**: Optional (web UI)

---

## Core Platform Services

These services provide core platform functionality and MUST be tested.

### Kubernetes API
- **Purpose**: Container orchestration
- **Access**: Via `kubectl` CLI
- **Authentication**: Kubeconfig
- **Python SDK**: `kubernetes` (official client)
- **Testing**: Required (core)

### GitHub
- **Purpose**: Source code hosting (external)
- **URL**: `https://github.com`
- **Protocol**: HTTPS
- **Authentication**: Personal access token or OAuth
- **Python SDK**: `PyGithub` or `requests`
- **Testing**: Required (core)

### ArgoCD
- **Purpose**: GitOps continuous delivery
- **URLs**:
  - Web UI/REST API: `https://argocd.{domain_name}`
  - gRPC API: `https://argocd-grpc.{domain_name}`
- **Protocols**: HTTPS, gRPC
- **Authentication**: OAuth2 via Keycloak
- **Python SDK**: `requests` (REST API)
- **CLI**: `argocd`
- **Testing**: Required (core)

### Argo Workflows
- **Purpose**: Kubernetes-native workflow engine
- **URLs**:
  - Web UI/REST API: `https://argo.{domain_name}`
  - gRPC API: `https://grpc-argo.{domain_name}`
- **Protocols**: HTTPS, gRPC
- **Authentication**: Service account token
- **Python SDK**: `argo-workflows` or `requests`
- **CLI**: `argo`
- **Testing**: Required (core)

### Gitea
- **Purpose**: Self-hosted Git service
- **URL**: `https://git.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: OAuth2 via Keycloak
- **Python SDK**: `requests` (REST API)
- **CLI**: `tea`
- **Testing**: Required (core)

### Harbor
- **Purpose**: Container registry
- **URL**: `https://registry.{domain_name}`
- **Protocol**: HTTPS (Docker Registry v2 API)
- **Authentication**: Username/password or robot account
- **Python SDK**: `requests` (REST API)
- **CLI**: `podman` or `docker`
- **Testing**: Required (core)

### DevPi
- **Purpose**: Python package index (PyPI mirror/cache)
- **URLs**:
  - Web UI: `https://devpi.{domain_name}`
  - API: `https://devpi-api.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: Username/password
- **Python SDK**: `devpi-client` or `requests`
- **CLI**: `devpi`
- **Testing**: Required (core)

### Code-Server
- **Purpose**: VS Code in the browser
- **URL**: `https://code.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: OAuth2 via Keycloak
- **Testing**: Required (core)

### Thinkube Control
- **Purpose**: Thinkube management interface
- **URL**: `https://control.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: OAuth2 via Keycloak
- **Python SDK**: `requests`
- **Testing**: Required (core)

---

## Optional Data Services

These services provide data storage and management. May not be deployed in all installations.

### Valkey
- **Purpose**: Redis-compatible in-memory data store
- **URL**: `https://valkey.{domain_name}`
- **Protocol**: HTTPS (REST API) + Redis protocol on TCP
- **Authentication**: Password
- **Python SDK**: `redis` (redis-py)
- **Testing**: Optional

### Qdrant
- **Purpose**: Vector database for AI applications
- **URLs**:
  - REST API: `https://qdrant.{domain_name}` (port 6333)
  - gRPC API: `https://qdrant.{domain_name}:6334`
  - Dashboard: `https://qdrant-dashboard.{domain_name}`
- **Protocols**: HTTPS, gRPC
- **Authentication**: API key
- **Python SDK**: `qdrant-client`
- **Testing**: Optional

### OpenSearch
- **Purpose**: Search and analytics engine
- **URLs**:
  - API: `https://opensearch.{domain_name}`
  - Dashboards: `https://osd.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: Username/password
- **Python SDK**: `opensearch-py`
- **Testing**: Optional

### Weaviate
- **Purpose**: Vector database with semantic search
- **URLs**:
  - REST API: `https://weaviate.{domain_name}`
  - gRPC API: `https://weaviate-grpc.{domain_name}` or `:50051`
- **Protocols**: HTTPS, gRPC (since v1.23.7)
- **Authentication**: API key
- **Python SDK**: `weaviate-client` (v4 supports gRPC)
- **Testing**: Optional

### Chroma
- **Purpose**: Open-source embedding database
- **URL**: `https://chroma.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: Token
- **Python SDK**: `chromadb`
- **Testing**: Optional

### ClickHouse
- **Purpose**: Columnar database for analytics
- **URL**: `https://clickhouse.{domain_name}`
- **Protocols**: HTTPS (port 8123), Native TCP (port 9000)
- **Authentication**: Username/password
- **Python SDK**: `clickhouse-connect`
- **Testing**: Optional

### NATS
- **Purpose**: Message broker and streaming platform
- **URL**: `https://nats.{domain_name}`
- **Protocols**: Client port 4222, Monitoring HTTP port 8222
- **Authentication**: Token or credentials
- **Python SDK**: `nats-py`
- **Testing**: Optional

---

## Optional ML/AI Services

These services support machine learning and AI workflows.

### MLflow
- **Purpose**: ML experiment tracking and model registry
- **URL**: `https://mlflow.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: OAuth2 via Keycloak (browser initialization required)
- **Python SDK**: `mlflow`
- **Testing**: Optional

### JupyterHub
- **Purpose**: Multi-user Jupyter notebook server
- **URL**: `https://jupyter.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: OAuth2 via Keycloak
- **Python SDK**: N/A (web interface)
- **Testing**: Optional

### Argilla
- **Purpose**: Data labeling and annotation platform
- **URL**: `https://argilla.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: API key
- **Python SDK**: `argilla`
- **Testing**: Optional

### CVAT
- **Purpose**: Computer vision annotation tool
- **URL**: `https://cvat.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: Username/password
- **Python SDK**: `cvat-sdk`
- **CLI**: `cvat-cli`
- **Testing**: Optional

### LiteLLM
- **Purpose**: LLM proxy and unified API
- **URL**: `https://litellm.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: Master key
- **Python SDK**: `openai` (OpenAI-compatible)
- **Testing**: Optional

### Langfuse
- **Purpose**: LLM observability and tracing
- **URL**: `https://langfuse.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: Public/secret key pair
- **Python SDK**: `langfuse`
- **Testing**: Optional

---

## Monitoring Services

### Perses
- **Purpose**: Dashboard visualization and metrics exploration
- **URL**: `https://perses.{domain_name}`
- **Protocol**: HTTPS
- **Authentication**: OAuth2 via Keycloak
- **Python SDK**: `requests` (REST API)
- **CLI**: `percli`
- **Testing**: Optional

---

## Services with gRPC Support

The following services provide gRPC endpoints for high-performance communication:

| Service | gRPC URL | gRPC Port | Notes |
|---------|----------|-----------|-------|
| ArgoCD | `argocd-grpc.{domain_name}` | 443 (HTTPS) | Separate hostname |
| Argo Workflows | `grpc-argo.{domain_name}` | 443 (HTTPS) | Separate hostname |
| Qdrant | `qdrant.{domain_name}:6334` | 6334 | Same hostname, different port |
| Weaviate | `weaviate-grpc.{domain_name}` or `:50051` | 50051 | Stable since v1.23.7 |

---

## Services with Multiple Endpoints

Some services expose multiple endpoints for different purposes:

### DevPi
- **Dashboard**: `devpi.{domain_name}` - Web UI with OAuth2
- **API**: `devpi-api.{domain_name}` - Package API for pip/uv

### SeaweedFS
- **S3 API**: `s3.{domain_name}` - S3-compatible object storage
- **Admin UI**: `seaweedfs.{domain_name}` - Management interface

### Qdrant
- **API**: `qdrant.{domain_name}` - REST API on port 6333
- **gRPC**: `qdrant.{domain_name}:6334` - gRPC API
- **Dashboard**: `qdrant-dashboard.{domain_name}` - Web UI with OAuth2

### OpenSearch
- **API**: `opensearch.{domain_name}` - Search API
- **Dashboards**: `osd.{domain_name}` - Kibana-like UI

### ArgoCD
- **Web/API**: `argocd.{domain_name}` - Web UI and REST API
- **gRPC**: `argocd-grpc.{domain_name}` - gRPC API for CLI

### Argo Workflows
- **Web/API**: `argo.{domain_name}` - Web UI and REST API
- **gRPC**: `grpc-argo.{domain_name}` - gRPC API for CLI

---

## TCP Passthrough Services

These services use TCP passthrough via NGINX Ingress instead of HTTP:

- **PostgreSQL**: Port 5432 (PostgreSQL wire protocol)
- **Valkey**: Redis protocol port (in addition to HTTP management)
- **ClickHouse**: Port 9000 (Native TCP protocol)
- **NATS**: Port 4222 (NATS client protocol)

---

## Testing Requirements

**CRITICAL**: Tests must validate that **credentials are available AND work**, not just that services respond to pings.

Each test must:
1. **Check environment variables exist** (service URL, credentials)
2. **Authenticate with actual credentials** (no anonymous access)
3. **Perform a real operation** (query, create, list, etc.)
4. **Verify the operation succeeded** (not just HTTP 200)

### Test Examples

**BAD** - Only checks if endpoint responds:
```python
requests.get("https://postgres.thinkube.com")  # NOT ENOUGH
```

**GOOD** - Authenticates and performs actual operation:
```python
import psycopg2
conn = psycopg2.connect(
    host=os.environ['POSTGRES_HOST'],
    user=os.environ['POSTGRES_USER'],
    password=os.environ['POSTGRES_PASSWORD'],
    database=os.environ['POSTGRES_DB']
)
cursor = conn.cursor()
cursor.execute('SELECT version();')  # Real query
version = cursor.fetchone()
```

### Core Services (Must Test)
All core infrastructure and platform services must be validated in both code-server and Jupyter environments:
- PostgreSQL, Keycloak, SeaweedFS
- Kubernetes, GitHub, ArgoCD, Argo Workflows, Gitea, Harbor, DevPi
- Code-server, Thinkube Control

**Each test must authenticate and perform an actual operation to prove credentials work.**

### Optional Services (May Skip)
Optional services are tested only if deployed:
- Data services: Valkey, Qdrant, OpenSearch, Weaviate, Chroma, ClickHouse, NATS
- ML/AI services: MLflow, JupyterHub, Argilla, CVAT, LiteLLM, Langfuse
- Monitoring: Perses

**Tests skip with clear warning if service not configured or credentials missing.**

---

## Internal-Only Services

The following services are NOT exposed externally (used only by other services):

- **JuiceFS**: Distributed file system (used by JupyterHub and other services)
- **Cilium**: Kubernetes CNI (network plugin)
- **MetalLB**: Kubernetes load balancer
- **acme.sh**: TLS certificate management (Let's Encrypt)
- **GPU Operator**: NVIDIA GPU management
- **Prometheus**: Metrics collection (accessed internally by Perses and other services)

These are infrastructure components that don't require user-facing URLs.

---

## Authentication Methods Summary

| Method | Services |
|--------|----------|
| **OAuth2 (Keycloak)** | Keycloak, ArgoCD, Argo Workflows, Gitea, Code-server, Thinkube Control, PgAdmin, MLflow, JupyterHub, Perses |
| **Username/Password** | PostgreSQL, Harbor, DevPi, OpenSearch, CVAT, ClickHouse |
| **API Key** | Qdrant, Weaviate, Argilla, LiteLLM |
| **Token** | Chroma, Argo Workflows (service account), NATS |
| **AWS Credentials** | SeaweedFS (S3-compatible) |
| **Key Pair** | Langfuse (public/secret keys) |

---

## Environment Variables

All service URLs are exported as environment variables in:
- **Code-server**: `~/.thinkube_env` and `~/.config/thinkube/service-env.sh`
- **Jupyter notebooks**: Loaded via iPython startup script from same sources

Example variables:
```bash
export POSTGRES_HOST="postgres.thinkube.com"
export QDRANT_URL="https://qdrant.thinkube.com"
export QDRANT_GRPC_URL="https://qdrant.thinkube.com:6334"
export MLFLOW_TRACKING_URI="https://mlflow.thinkube.com"
export WEAVIATE_URL="https://weaviate.thinkube.com"
export WEAVIATE_GRPC_URL="https://weaviate-grpc.thinkube.com"
```

---

## Related Documentation

- **Testing**: See test scripts in code-server (`test-cli-tools.sh`) and Jupyter (`test-thinkube-services.ipynb`)
- **Deployment**: Each service has deployment playbooks in `ansible/40_thinkube/core/` or `ansible/40_thinkube/optional/`
- **Service Discovery**: Services register themselves via ConfigMaps with `thinkube.io/managed=true` label

---

**Document Version**: 1.0
**Last Updated**: 2025-10-13
**Maintainer**: Thinkube Platform Team

<!-- 🤖 AI-assisted -->
