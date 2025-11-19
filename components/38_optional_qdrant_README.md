# Qdrant

## Overview

Qdrant is a high-performance vector database designed for semantic search and AI applications. Deployed with OAuth2 Proxy authentication for dashboard access and open API access for application integration, Qdrant provides efficient similarity search, filtering, and payload storage for machine learning workloads.

**Key Features**:
- **High Performance**: Optimized for billion-scale vector search
- **Rich Filtering**: Combine vector similarity with metadata filters
- **Multiple Distance Metrics**: Cosine, Euclidean, Dot Product
- **gRPC and REST APIs**: High-performance gRPC and standard REST
- **OAuth2 Dashboard**: Keycloak-protected web interface
- **Persistent Storage**: 150Gi for vector data
- **CORS Support**: Configured for cross-origin dashboard access

## Dependencies

**Core Components** (always available):
- Kubernetes (#1) - k8s-snap 1.34.0
- Keycloak (#5) - OAuth2/OIDC authentication for dashboard
- Ingress (#7) - NGINX Ingress Controller
- Cert-manager (#8) - Wildcard TLS certificates
- Harbor (#14) - Container registry for Qdrant and Valkey images

**Optional Components**:
- None (Qdrant is a foundational AI service)

## Prerequisites

```yaml
requirements:
  kubernetes:
    version: "1.34.0"
    provider: "k8s-snap"

  authentication:
    dashboard: "OAuth2 Proxy + Keycloak"
    api: "No authentication (open)"
    admin_password: "ADMIN_PASSWORD environment variable"

  storage:
    persistence: true
    size: "150Gi"
    storage_class: "default"
    access_mode: "ReadWriteOnce"

  networking:
    dashboard_hostname: "qdrant-dashboard.example.com"
    api_hostname: "qdrant.example.com"
    rest_port: 6333
    grpc_port: 6334

  resources:
    requests:
      cpu: "2"
      memory: "4Gi"
    limits:
      cpu: "4"
      memory: "8Gi"

  harbor:
    qdrant_image: "library/qdrant:v1.15.4"
    valkey_image: "library/valkey:latest"
```

## Playbooks

### **Main Deployment**
**File**: [10_deploy.yaml](10_deploy.yaml)

Comprehensive deployment with OAuth2 Proxy, ephemeral Valkey, and dual ingress:

#### **Step 1: Namespace and TLS Setup**

- **Namespace Creation**
  - Creates `qdrant` namespace

- **TLS Certificate Setup**
  - Retrieves wildcard certificate from `default` namespace
  - Secret name: `{domain_name}-tls` (dots replaced with hyphens)
  - Copies to `qdrant` namespace as `qdrant-tls-secret`

#### **Step 2: Ephemeral Valkey Deployment**

- **Deploys Valkey via Role** (`valkey/ephemeral_valkey`)
  - Registry: `{harbor_registry}/library`
  - Purpose: Session storage for OAuth2 Proxy
  - Deployment name: `ephemeral-valkey`
  - Service name: `ephemeral-valkey`
  - No persistence (ephemeral sessions)
  - **Note**: Uses Valkey instead of Redis for licensing compliance

#### **Step 3: Keycloak CORS Configuration**

- **Admin Token Retrieval**
  - Authenticates to Keycloak master realm
  - Client: `admin-cli`
  - Grant type: `password`
  - Credentials: `admin_username` and `ADMIN_PASSWORD`

- **Realm CORS Settings**
  - Gets current realm configuration
  - Updates realm attributes:
    - `_browser_header.xFrameOptions`: `ALLOW-FROM https://qdrant-dashboard.example.com`
    - `_browser_header.contentSecurityPolicy`: `frame-src https://*.example.com;`
    - `_browser_header.accessControlAllowOrigin`: `https://qdrant-dashboard.example.com`
    - `_browser_header.accessControlAllowMethods`: `GET, POST, OPTIONS`
    - `_browser_header.accessControlAllowHeaders`: `Origin, X-Requested-With, Content-Type, Accept, Authorization`
    - `_browser_header.accessControlAllowCredentials`: `true`
  - **Critical**: Allows Qdrant dashboard to embed Keycloak auth flows

- **Client CORS Settings**
  - Gets `qdrant-dashboard` client details
  - Updates client configuration:
    - `webOrigins`: `['*', 'https://qdrant-dashboard.example.com', '+']`
    - `access.token.lifespan`: `3600` seconds

#### **Step 4: OAuth2 Proxy Deployment**

- **Deploys OAuth2 Proxy via Role** (`oauth2_proxy`)
  - Client ID: `qdrant-dashboard`
  - Namespace: `qdrant`
  - Dashboard host: `qdrant-dashboard.example.com`
  - OIDC issuer: `{keycloak_url}/realms/{realm}`
  - Cookie domain: `.example.com`
  - Redirect URL: `https://qdrant-dashboard.example.com/oauth2/callback`
  - **Session Store**: Valkey (Redis-compatible)
  - Session service: `ephemeral-valkey`
  - Cookie SameSite: `none` (cross-domain compatibility)
  - Ingress enabled: creates `/oauth2` ingress
  - Keycloak debug: true

#### **Step 5: Qdrant Helm Deployment**

- **Helm Repository Setup**
  - Adds repository: `https://qdrant.to/helm`
  - Updates repositories

- **Helm Deployment**
  - Release name: `qdrant`
  - Chart: `qdrant/qdrant`
  - Namespace: `qdrant`

  - **Image Configuration**:
    - Repository: `{harbor_registry}/library/qdrant`
    - Tag: `v1.15.4`
    - Pull policy: `IfNotPresent`

  - **Persistence**:
    - Enabled: true
    - Storage class: empty string (default)
    - Access mode: ReadWriteOnce
    - Size: 150Gi

  - **Replica Count**: 1 (single node)

  - **Resources**:
    - Requests: 2 CPU, 4Gi memory
    - Limits: 4 CPU, 8Gi memory

  - **Service Configuration**:
    - gRPC enabled: true
    - gRPC port: 6334

  - **CORS Configuration**:
    - Enabled: true
    - Allowed origins: `https://qdrant-dashboard.example.com`

#### **Step 6: Dashboard Ingress (Authenticated)**

- **Creates `qdrant-http-ingress`**
  - Host: `qdrant-dashboard.example.com`
  - Annotations:
    - Proxy body size: unlimited (0)
    - Backend protocol: HTTP
    - **Auth URL**: `https://$host/oauth2/auth` (OAuth2 Proxy auth check)
    - **Auth signin**: `https://$host/oauth2/start?rd=$escaped_request_uri` (redirect to login)
  - TLS: `qdrant-tls-secret`
  - Backend: `qdrant:6333` (REST API)
  - **Result**: All requests to dashboard require OAuth2 authentication

#### **Step 7: Root Redirect Ingress**

- **Creates `qdrant-root-redirect`**
  - Path: `/` (Exact match only)
  - Annotations:
    - Permanent redirect: `https://qdrant-dashboard.example.com/dashboard`
    - Redirect code: 301
  - **Purpose**: Automatically redirects root to dashboard UI

#### **Step 8: API Ingress (No Authentication)**

- **Creates `qdrant-api-ingress`**
  - Host: `qdrant.example.com`
  - Annotations:
    - Proxy body size: unlimited
    - Backend protocol: HTTP
    - **No auth annotations** (open API access)
  - TLS: `qdrant-tls-secret`
  - Backend: `qdrant:6333`
  - **Result**: API accessible without authentication for application integration

#### **Step 9: Verification and Testing**

- **Lists Ingresses**
  - Displays all ingress resources in namespace for verification

- **API Readiness Check**
  - Tests `https://qdrant.example.com/collections`
  - Method: GET
  - Retries: 12 × 5s = 60s timeout
  - Status: 200

- **Test Collection Creation**
  - Creates `test_collection`
  - Vector size: 4 dimensions
  - Distance metric: Cosine
  - Status codes: 200 (created), 201 (created), 409 (already exists)

- **Deployment Summary Display**
  - API endpoint URL
  - Dashboard URL

### **Service Discovery**
**File**: [17_configure_discovery.yaml](17_configure_discovery.yaml)

Registers Qdrant with Thinkube service discovery system:

- **ConfigMap Creation** (`thinkube-service-config` in `qdrant` namespace)
  - Service type: `optional`
  - Category: `ai`
  - Icon: `/icons/tk_vector.svg`
  - Component version: `0.1.0` (from VERSION file)

- **Endpoints Registered**:
  - Primary: Dashboard (authenticated) at `https://qdrant-dashboard.example.com` (health: `/`)
  - Secondary: API (open) at `https://qdrant.example.com` (health: `/collections`)
  - Internal: REST API at `http://qdrant.qdrant.svc.cluster.local:6333`
  - Internal: gRPC API at `qdrant.qdrant.svc.cluster.local:6334`

- **Scaling Configuration**:
  - Resource type: StatefulSet `qdrant-0`
  - Namespace: `qdrant`
  - Min replicas: 1
  - Can disable: true

- **Metadata**:
  - Authentication: `oauth2` (dashboard), `none` (API)
  - Persistence: `true`
  - License: `Apache-2.0`

- **Environment Variables**:
  - `QDRANT_API_URL`: `https://qdrant.example.com`
  - `QDRANT_DASHBOARD_URL`: `https://qdrant-dashboard.example.com`
  - `QDRANT_GRPC_HOST`: `qdrant.qdrant.svc.cluster.local`
  - `QDRANT_GRPC_PORT`: `6334`

- **Code-Server Integration**:
  - Updates code-server environment variables via `code_server_env_update` role

## Deployment

This component is automatically deployed via the **thinkube-control Optional Components interface**:

1. Navigate to https://thinkube.example.com/optional-components
2. Locate the **Qdrant** card in the **AI** section
3. Click **Install** to deploy the component
4. Monitor real-time deployment progress via WebSocket streaming
5. Verify deployment status in the dashboard

The deployment executes the orchestrator playbook at `/ansible/40_thinkube/optional/qdrant/00_install.yaml`.

**Deployment Sequence**:
1. Create namespace and copy TLS certificate
2. Deploy ephemeral Valkey for session storage
3. Configure Keycloak CORS for OAuth2
4. Deploy OAuth2 Proxy with Keycloak integration
5. Add Qdrant Helm repository
6. Deploy Qdrant via Helm (150Gi storage)
7. Create dashboard ingress (authenticated)
8. Create root redirect ingress
9. Create API ingress (no authentication)
10. Test API endpoint
11. Register with service discovery

**Important**: Set `ADMIN_PASSWORD` environment variable before deployment for OAuth2 Proxy configuration.

## Access Points

### Dashboard (Authenticated)

```
https://qdrant-dashboard.example.com
```

- **Authentication**: OAuth2 via Keycloak
- **Root redirect**: `/` → `/dashboard`
- **Protected**: All requests require login

### API (No Authentication)

```
https://qdrant.example.com
```

- **Authentication**: None (open access)
- **REST API**: Port 6333
- **Purpose**: Application integration

### Internal Cluster Access

**REST API**:
```
http://qdrant.qdrant.svc.cluster.local:6333
```

**gRPC API**:
```
qdrant.qdrant.svc.cluster.local:6334
```

## Configuration

### Storage

- **Size**: 150Gi persistent volume
- **Access mode**: ReadWriteOnce
- **Storage class**: Default

To increase:
```bash
kubectl edit statefulset qdrant-0 -n qdrant
# Update PVC size
```

### Resources

Default resources suitable for moderate workloads:

```yaml
requests:
  cpu: 2
  memory: 4Gi
limits:
  cpu: 4
  memory: 8Gi
```

Adjust via Helm values:
```bash
helm upgrade qdrant qdrant/qdrant -n qdrant \
  --set resources.requests.cpu=4 \
  --set resources.requests.memory=8Gi \
  --set resources.limits.cpu=8 \
  --set resources.limits.memory=16Gi
```

### CORS

Configured for dashboard origin: `https://qdrant-dashboard.example.com`

To add origins:
```bash
helm upgrade qdrant qdrant/qdrant -n qdrant \
  --set cors.allowedOrigins='{https://qdrant-dashboard.example.com,https://other-app.example.com}'
```

## Usage

### REST API

#### Health Check
```bash
curl https://qdrant.example.com/
```

#### List Collections
```bash
curl https://qdrant.example.com/collections
```

#### Create Collection
```bash
curl -X PUT https://qdrant.example.com/collections/my_collection \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "size": 768,
      "distance": "Cosine"
    }
  }'
```

#### Upsert Points
```bash
curl -X PUT https://qdrant.example.com/collections/my_collection/points \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": [0.1, 0.2, 0.3, ...],
        "payload": {"text": "example document", "category": "tech"}
      }
    ]
  }'
```

#### Search Vectors
```bash
curl -X POST https://qdrant.example.com/collections/my_collection/points/search \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, 0.3, ...],
    "limit": 10,
    "with_payload": true,
    "with_vector": false
  }'
```

#### Search with Filter
```bash
curl -X POST https://qdrant.example.com/collections/my_collection/points/search \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, 0.3, ...],
    "filter": {
      "must": [
        {"key": "category", "match": {"value": "tech"}}
      ]
    },
    "limit": 5
  }'
```

### Python Client

Install client:
```bash
pip install qdrant-client
```

Basic usage:
```python
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

# Connect (REST API)
client = QdrantClient(
    url="https://qdrant.example.com",
    prefer_grpc=False
)

# Or use internal gRPC for better performance
# client = QdrantClient(
#     host="qdrant.qdrant.svc.cluster.local",
#     grpc_port=6334,
#     prefer_grpc=True
# )

# Create collection
client.create_collection(
    collection_name="my_collection",
    vectors_config=VectorParams(size=768, distance=Distance.COSINE)
)

# Upsert points
client.upsert(
    collection_name="my_collection",
    points=[
        PointStruct(
            id=1,
            vector=[0.1, 0.2, 0.3, ...],  # 768 dimensions
            payload={"text": "example document", "category": "tech"}
        ),
        PointStruct(
            id=2,
            vector=[0.4, 0.5, 0.6, ...],
            payload={"text": "another document", "category": "science"}
        )
    ]
)

# Search
results = client.search(
    collection_name="my_collection",
    query_vector=[0.1, 0.2, 0.3, ...],
    limit=5,
    query_filter={
        "must": [
            {"key": "category", "match": {"value": "tech"}}
        ]
    }
)

for result in results:
    print(f"ID: {result.id}, Score: {result.score}, Payload: {result.payload}")
```

### LangChain Integration

```python
from langchain.vectorstores import Qdrant
from langchain.embeddings import OpenAIEmbeddings
from qdrant_client import QdrantClient

# Initialize client
client = QdrantClient(
    url="https://qdrant.example.com",
    prefer_grpc=False
)

# Create vector store
embeddings = OpenAIEmbeddings()
vectorstore = Qdrant(
    client=client,
    collection_name="langchain_docs",
    embeddings=embeddings
)

# Add documents
texts = ["Document 1", "Document 2", "Document 3"]
metadatas = [{"source": "file1"}, {"source": "file2"}, {"source": "file3"}]
vectorstore.add_texts(texts, metadatas=metadatas)

# Similarity search
results = vectorstore.similarity_search("query text", k=3)
print(results)
```

### LlamaIndex Integration

```python
from llama_index import VectorStoreIndex, SimpleDirectoryReader
from llama_index.vector_stores import QdrantVectorStore
from llama_index.storage.storage_context import StorageContext
from qdrant_client import QdrantClient

# Initialize client
client = QdrantClient(
    host="qdrant.qdrant.svc.cluster.local",
    grpc_port=6334,
    prefer_grpc=True
)

# Create vector store
vector_store = QdrantVectorStore(
    client=client,
    collection_name="llamaindex"
)

storage_context = StorageContext.from_defaults(vector_store=vector_store)

# Load documents and create index
documents = SimpleDirectoryReader("./data").load_data()
index = VectorStoreIndex.from_documents(
    documents,
    storage_context=storage_context
)

# Query
query_engine = index.as_query_engine()
response = query_engine.query("What is the main topic?")
print(response)
```

## Integration

### JupyterHub Notebooks

From notebooks, use internal gRPC endpoint for best performance:

```python
from qdrant_client import QdrantClient

client = QdrantClient(
    host="qdrant.qdrant.svc.cluster.local",
    grpc_port=6334,
    prefer_grpc=True
)

# Now use as normal
collection = client.get_collection("my_collection")
print(f"Collection has {collection.points_count} points")
```

### MLflow Model Serving

Store embeddings for model recommendations:

```python
import mlflow
from qdrant_client import QdrantClient

client = QdrantClient(url="https://qdrant.example.com")

# Store model embeddings
model_embedding = get_model_embedding(model_uri)
client.upsert(
    collection_name="model_embeddings",
    points=[PointStruct(
        id=model_version,
        vector=model_embedding,
        payload={"model_uri": model_uri, "stage": "production"}
    )]
)

# Find similar models
similar = client.search(
    collection_name="model_embeddings",
    query_vector=query_embedding,
    limit=5
)
```

## Monitoring

### Check Deployment Status

```bash
kubectl get all -n qdrant
kubectl get pvc -n qdrant
kubectl get ingress -n qdrant
```

### View Logs

Qdrant:
```bash
kubectl logs -n qdrant -l app.kubernetes.io/name=qdrant -f
```

OAuth2 Proxy:
```bash
kubectl logs -n qdrant -l app=oauth2-proxy -f
```

Valkey:
```bash
kubectl logs -n qdrant -l app=ephemeral-valkey -f
```

### Collection Stats

```python
from qdrant_client import QdrantClient

client = QdrantClient(url="https://qdrant.example.com")

# Get collection info
collection = client.get_collection("my_collection")
print(f"Points: {collection.points_count}")
print(f"Vectors: {collection.vectors_count}")
print(f"Indexed: {collection.indexed_vectors_count}")
```

### Health Check

```bash
curl https://qdrant.example.com/
# Returns: {"title":"qdrant - vector search engine","version":"1.15.4"}
```

## Troubleshooting

### Verify Deployment

Check StatefulSet:
```bash
kubectl get statefulset -n qdrant
kubectl describe statefulset qdrant-0 -n qdrant
```

Check services:
```bash
kubectl get svc -n qdrant
```

Should show:
- `qdrant` (ClusterIP for REST and gRPC)
- `qdrant-headless` (headless service)
- `oauth2-proxy` (OAuth2 Proxy service)
- `ephemeral-valkey` (Valkey session store)

### Dashboard Access Issues

**Issue**: Cannot access dashboard
- **Solution**: Check OAuth2 Proxy logs: `kubectl logs -n qdrant -l app=oauth2-proxy`
- **Solution**: Verify Keycloak CORS settings
- **Solution**: Check browser console for CORS errors

Test OAuth2 auth endpoint:
```bash
curl -v https://qdrant-dashboard.example.com/oauth2/auth
# Should return 401 or redirect to Keycloak
```

### API Access Issues

**Issue**: API returns errors
- **Solution**: Check Qdrant logs: `kubectl logs -n qdrant -l app.kubernetes.io/name=qdrant`
- **Solution**: Verify ingress: `kubectl get ingress qdrant-api-ingress -n qdrant`

Test internal API:
```bash
kubectl run -it --rm test --image=curlimages/curl --restart=Never -- \
  curl http://qdrant.qdrant.svc.cluster.local:6333/collections
```

### Storage Issues

**Issue**: Pod stuck in Pending
- **Solution**: Check PVC status
```bash
kubectl get pvc -n qdrant
kubectl describe pvc data-qdrant-0 -n qdrant
```

Check storage usage:
```bash
kubectl exec -n qdrant qdrant-0 -- df -h /qdrant/storage
```

### Performance Issues

**Issue**: Slow search queries
- **Solution**: Use gRPC instead of REST
- **Solution**: Increase CPU/memory resources
- **Solution**: Enable payload indexing for frequently filtered fields
- **Solution**: Optimize vector dimensionality

### OAuth2 Session Issues

**Issue**: Login loop or session expired
- **Solution**: Check Valkey is running: `kubectl get pods -n qdrant -l app=ephemeral-valkey`
- **Solution**: Restart OAuth2 Proxy: `kubectl rollout restart deployment oauth2-proxy -n qdrant`

### Common Issues

**Issue**: CORS errors in dashboard
- **Solution**: Verify Keycloak CORS configuration
- **Solution**: Check Qdrant CORS allowed origins in Helm values

**Issue**: gRPC connection refused
- **Solution**: Verify gRPC port 6334 is enabled in Helm values
- **Solution**: Use internal endpoint for in-cluster access

**Issue**: Collection creation fails
- **Solution**: Check disk space: `kubectl exec -n qdrant qdrant-0 -- df -h`
- **Solution**: Verify collection doesn't already exist

## Testing

The test playbook [18_test.yaml](18_test.yaml) verifies:
- Namespace exists
- Qdrant pod is running
- OAuth2 Proxy is running
- Valkey is running
- Services are configured
- PVC is bound
- Ingresses are created
- API endpoint responds
- Can create collection
- Can upsert and search vectors

## Rollback

To uninstall Qdrant:

```bash
cd ~/thinkube
./scripts/tk_ansible ansible/40_thinkube/optional/qdrant/19_rollback.yaml
```

**Warning**: This deletes all vector data. Backup collections before uninstalling.

### Backup Collections

```python
from qdrant_client import QdrantClient
import json

client = QdrantClient(url="https://qdrant.example.com")

# Get all collections
collections = client.get_collections().collections

for collection in collections:
    # Get all points
    points = client.scroll(collection_name=collection.name, limit=10000)[0]

    # Save to file
    with open(f"{collection.name}_backup.json", "w") as f:
        json.dump([p.dict() for p in points], f)
```

## Performance Considerations

- **gRPC vs REST**: gRPC is 2-3x faster for bulk operations
- **Indexing**: Enable HNSW indexing for faster search (default)
- **Batch Operations**: Use batch upsert for multiple points
- **Payload Indexing**: Index frequently filtered payload fields
- **Memory**: Vectors cached in memory; size RAM accordingly

## Security Considerations

**Current Configuration**:
- Dashboard: OAuth2 authentication via Keycloak
- API: No authentication (open for application access)
- HTTPS enabled for all external access
- CORS configured for dashboard origin

**For Production**:
1. Enable API authentication with API keys
2. Use NetworkPolicies to restrict API access
3. Implement rate limiting on ingress
4. Enable audit logging
5. Rotate OAuth2 secrets regularly
6. Use separate collections for different tenants

## References

- [Qdrant Official Documentation](https://qdrant.tech/documentation/)
- [Qdrant Python Client](https://github.com/qdrant/qdrant-client)
- [Qdrant REST API](https://qdrant.github.io/qdrant/redoc/index.html)
- [LangChain Qdrant Integration](https://python.langchain.com/docs/integrations/vectorstores/qdrant)
- [LlamaIndex Qdrant Integration](https://docs.llamaindex.ai/en/stable/examples/vector_stores/QdrantIndexDemo.html)

🤖 [AI-assisted]
