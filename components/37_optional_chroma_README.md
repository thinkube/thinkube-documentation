# Chroma

## Overview

Chroma is an open-source embedding database designed for AI applications, providing efficient storage and retrieval of vector embeddings with metadata. It enables semantic search, similarity matching, and RAG (Retrieval-Augmented Generation) applications through a simple REST API.

**Key Features**:
- **Vector Storage**: Store embeddings with associated documents and metadata
- **Similarity Search**: Query by embedding similarity using various distance metrics
- **Collections**: Organize embeddings into named collections
- **Token Authentication**: Secure API access with token-based auth
- **Persistent Storage**: Data persists across restarts with PVC
- **REST API**: Simple HTTP API for all operations (v1 and v2)
- **Multi-modal Support**: Text and other embedding types
- **LangChain Integration**: Native support for RAG applications

## Dependencies

**Core Components** (always available):
- Kubernetes (#1) - k8s-snap 1.34.0
- Ingress (#7) - NGINX Ingress Controller
- Cert-manager (#8) - Wildcard TLS certificates
- Harbor (#14) - Container registry for Chroma image

**Optional Components**:
- None (Chroma is a foundational AI service)

## Prerequisites

```yaml
requirements:
  kubernetes:
    version: "1.34.0"
    provider: "k8s-snap"

  authentication:
    admin_password: "ADMIN_PASSWORD environment variable"
    token_header: "X-Chroma-Token"

  storage:
    persistence: true
    size: "10Gi"
    storage_class: "k8s-hostpath"
    access_mode: "ReadWriteOnce"

  networking:
    hostname: "chroma.example.com"
    ingress_class: "nginx"
    https: true

  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "2Gi"
      cpu: "1"

  harbor:
    image: "library/chroma:latest"
```

## Playbooks

### **Main Deployment**
**File**: [10_deploy.yaml](10_deploy.yaml)

Deploys Chroma vector database with token authentication:

- **Variable Validation**
  - Verifies `domain_name`, `admin_username`, `primary_ingress_class`, `kubeconfig` defined
  - Checks `ADMIN_PASSWORD` environment variable is set
  - Fails deployment if requirements not met

- **Namespace Creation**
  - Creates `chroma` namespace
  - Labels: `thinkube.io/managed: true`, `thinkube.io/service-type: optional`

- **TLS Certificate Setup**
  - Retrieves wildcard certificate from `default` namespace
  - Secret name: `{domain_name}-tls` (dots replaced with hyphens)
  - Copies to `chroma` namespace as `chroma-tls-secret`

- **Authentication Secret**
  - Creates `chroma-auth` secret
  - Contains `auth-token` (admin password) and `admin-username`
  - Used for token-based API authentication

- **Persistent Volume Claim**
  - Name: `chroma-data-pvc`
  - Access mode: ReadWriteOnce
  - Storage class: `k8s-hostpath`
  - Size: 10Gi
  - Mount path: `/data` in container

- **Chroma StatefulSet Deployment**
  - Replicas: 1 (single instance)
  - Service name: `chromadb-headless`
  - Image: `{harbor_registry}/library/chroma:latest` (from Harbor)
  - Port: 8000 (HTTP)

  - **Environment Variables**:
    - `CHROMA_SERVER_AUTH_CREDENTIALS_PROVIDER`: `chromadb.auth.token.TokenConfigServerAuthCredentialsProvider`
    - `CHROMA_SERVER_AUTH_PROVIDER`: `chromadb.auth.token.TokenAuthServerProvider`
    - `CHROMA_SERVER_AUTH_TOKEN_TRANSPORT_HEADER`: `X-Chroma-Token`
    - `CHROMA_SERVER_AUTH_CREDENTIALS`: from `chroma-auth` secret
    - `ANONYMIZED_TELEMETRY`: `FALSE` (privacy)

  - **Volume Mount**: PVC `chroma-data-pvc` at `/data`

  - **Resources**:
    - Requests: 512Mi memory, 250m CPU
    - Limits: 2Gi memory, 1 CPU

  - **Health Probes**:
    - Liveness: `/api/v2/heartbeat` (30s initial delay, 10s period)
    - Readiness: `/api/v2/heartbeat` (10s initial delay, 5s period)

- **Headless Service**
  - Name: `chromadb-headless`
  - ClusterIP: None
  - Port: 8000
  - Purpose: StatefulSet pod identification

- **ClusterIP Service**
  - Name: `chromadb-svc`
  - Type: ClusterIP
  - Port: 80 (maps to container port 8000)
  - Selector: `app=chroma`

- **Ingress Creation**
  - Host: `chroma.example.com`
  - Annotations:
    - Proxy body size: 100m (large embedding uploads)
    - Proxy timeouts: 600s read/send
    - SSL redirect: true
  - TLS: `chroma-tls-secret`
  - Backend: `chromadb-svc:80`

- **Readiness Wait**
  - Waits for StatefulSet ready replicas: 1
  - Retries: 30 × 10s = 5 minutes

- **Deployment Status Display**
  - API endpoint: `https://chroma.example.com`
  - Authentication: Token-based (X-Chroma-Token header)
  - Usage examples

### **Service Discovery**
**File**: [17_configure_discovery.yaml](17_configure_discovery.yaml)

Registers Chroma with Thinkube service discovery system:

- **Retrieves Auth Token**
  - Gets `chroma-auth` secret from `chroma` namespace
  - Decodes `auth-token` from base64

- **ConfigMap Creation** (`thinkube-service-config` in `chroma` namespace)
  - Service type: `optional`
  - Category: `ai`
  - Icon: `/icons/tk_vector.svg`
  - Component version: `0.1.0` (from VERSION file)

- **Endpoints Registered**:
  - Primary: API at `https://chroma.example.com` (health: `/api/v2/heartbeat`)

- **Scaling Configuration**:
  - Resource type: StatefulSet `chroma`
  - Namespace: `chroma`
  - Min replicas: 1
  - Can disable: true

- **Metadata**:
  - Authentication: `token`
  - Persistence: `true`
  - License: `Apache-2.0`

- **Environment Variables**:
  - `CHROMA_API_URL`: `https://chroma.example.com`
  - `CHROMA_AUTH_TOKEN`: decoded auth token from secret

- **Code-Server Integration**:
  - Updates code-server environment variables via `code_server_env_update` role

## Deployment

This component is automatically deployed via the **thinkube-control Optional Components interface**:

1. Navigate to https://thinkube.example.com/optional-components
2. Locate the **Chroma** card in the **AI** section
3. Click **Install** to deploy the component
4. Monitor real-time deployment progress via WebSocket streaming
5. Verify deployment status in the dashboard

The deployment executes the orchestrator playbook at `/ansible/40_thinkube/optional/chroma/00_install.yaml`.

**Deployment Sequence**:
1. Validate environment variables
2. Create namespace
3. Copy TLS certificate
4. Create authentication secret
5. Create persistent volume claim (10Gi)
6. Deploy Chroma StatefulSet
7. Create headless service
8. Create ClusterIP service
9. Create ingress with HTTPS
10. Wait for pod ready
11. Register with service discovery

**Important**: Set `ADMIN_PASSWORD` environment variable before deployment. This password protects the Chroma API.

## Access Points

### External API

```
https://chroma.example.com
```

All requests require authentication via `X-Chroma-Token` header:

```bash
curl -H "X-Chroma-Token: $ADMIN_PASSWORD" \
  https://chroma.example.com/api/v1/collections
```

### Internal Cluster Access

From within cluster:
```
http://chromadb-svc.chroma.svc.cluster.local
```

## Configuration

### Authentication

Chroma uses token-based authentication:

- **Header**: `X-Chroma-Token`
- **Value**: Admin password from `ADMIN_PASSWORD` environment variable
- **Provider**: `TokenConfigServerAuthCredentialsProvider`

All API requests must include the authentication header.

### Storage

- **Location**: `/data` in container
- **PVC**: `chroma-data-pvc` (10Gi)
- **Storage class**: `k8s-hostpath`
- **Data persists** across pod restarts and deletions

To increase storage:
```bash
kubectl edit pvc chroma-data-pvc -n chroma
# Change spec.resources.requests.storage
```

### Resource Limits

Adjust resources for workload:

```bash
kubectl edit statefulset chroma -n chroma
```

Recommended:
- **Light workload**: 512Mi-1Gi memory, 250m-500m CPU
- **Medium workload**: 1Gi-2Gi memory, 500m-1 CPU (default)
- **Heavy workload**: 2Gi-4Gi memory, 1-2 CPU

## Usage

### Python Client

Install client:
```bash
pip install chromadb
```

Basic usage:
```python
import chromadb
from chromadb.config import Settings

# Create client with authentication
client = chromadb.HttpClient(
    host="chroma.example.com",
    port=443,
    ssl=True,
    headers={"X-Chroma-Token": "your-admin-password"},
    settings=Settings(anonymized_telemetry=False)
)

# Check heartbeat
print(client.heartbeat())  # Returns timestamp

# Create or get collection
collection = client.get_or_create_collection(
    name="my_documents",
    metadata={"description": "Document embeddings"}
)

# Add documents with embeddings
collection.add(
    ids=["doc1", "doc2", "doc3"],
    documents=[
        "This is the first document",
        "This is the second document",
        "This is the third document"
    ],
    metadatas=[
        {"source": "file1.txt"},
        {"source": "file2.txt"},
        {"source": "file3.txt"}
    ]
)

# Query by text (Chroma generates embeddings automatically)
results = collection.query(
    query_texts=["document about something"],
    n_results=2
)
print(results)

# Query with custom embeddings
results = collection.query(
    query_embeddings=[[0.1, 0.2, 0.3, ...]],
    n_results=5,
    where={"source": "file1.txt"}  # Metadata filter
)

# Get all items in collection
all_items = collection.get()

# Delete items
collection.delete(ids=["doc1"])

# Delete collection
client.delete_collection(name="my_documents")
```

### REST API

#### Heartbeat
```bash
curl https://chroma.example.com/api/v2/heartbeat
```

#### List Collections
```bash
curl -H "X-Chroma-Token: $ADMIN_PASSWORD" \
  https://chroma.example.com/api/v1/collections
```

#### Create Collection
```bash
curl -X POST https://chroma.example.com/api/v1/collections \
  -H "X-Chroma-Token: $ADMIN_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my_collection",
    "metadata": {"description": "Test collection"}
  }'
```

#### Add Embeddings
```bash
curl -X POST https://chroma.example.com/api/v1/collections/my_collection/add \
  -H "X-Chroma-Token: $ADMIN_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "ids": ["id1", "id2"],
    "embeddings": [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]],
    "metadatas": [{"type": "doc"}, {"type": "doc"}],
    "documents": ["Document 1 text", "Document 2 text"]
  }'
```

#### Query Collection
```bash
curl -X POST https://chroma.example.com/api/v1/collections/my_collection/query \
  -H "X-Chroma-Token: $ADMIN_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "query_embeddings": [[0.1, 0.2, 0.3]],
    "n_results": 5,
    "where": {"type": "doc"}
  }'
```

#### Delete Collection
```bash
curl -X DELETE https://chroma.example.com/api/v1/collections/my_collection \
  -H "X-Chroma-Token: $ADMIN_PASSWORD"
```

## Integration

### LangChain RAG Application

```python
from langchain.vectorstores import Chroma
from langchain.embeddings import OpenAIEmbeddings
from langchain.text_splitter import CharacterTextSplitter
from langchain.document_loaders import TextLoader
import chromadb

# Initialize Chroma client
chroma_client = chromadb.HttpClient(
    host="chroma.example.com",
    port=443,
    ssl=True,
    headers={"X-Chroma-Token": "password"}
)

# Create LangChain vector store
embeddings = OpenAIEmbeddings()
vectorstore = Chroma(
    client=chroma_client,
    collection_name="langchain_docs",
    embedding_function=embeddings
)

# Load and split documents
loader = TextLoader("document.txt")
documents = loader.load()
text_splitter = CharacterTextSplitter(chunk_size=1000, chunk_overlap=0)
docs = text_splitter.split_documents(documents)

# Add to vector store
vectorstore.add_documents(docs)

# Similarity search
results = vectorstore.similarity_search("query text", k=3)
print(results)

# Use as retriever in RAG chain
retriever = vectorstore.as_retriever(search_kwargs={"k": 3})
```

### LlamaIndex Integration

```python
from llama_index import VectorStoreIndex, SimpleDirectoryReader
from llama_index.vector_stores import ChromaVectorStore
from llama_index.storage.storage_context import StorageContext
import chromadb

# Initialize Chroma client
chroma_client = chromadb.HttpClient(
    host="chroma.example.com",
    port=443,
    ssl=True,
    headers={"X-Chroma-Token": "password"}
)

# Get or create collection
collection = chroma_client.get_or_create_collection("llamaindex")

# Create vector store
vector_store = ChromaVectorStore(chroma_collection=collection)
storage_context = StorageContext.from_defaults(vector_store=vector_store)

# Load documents and create index
documents = SimpleDirectoryReader("./data").load_data()
index = VectorStoreIndex.from_documents(
    documents,
    storage_context=storage_context
)

# Query index
query_engine = index.as_query_engine()
response = query_engine.query("What is the main topic?")
print(response)
```

### JupyterHub Integration

From notebooks:
```python
# Install client
!pip install chromadb

import chromadb

# Use internal service endpoint
client = chromadb.HttpClient(
    host="chromadb-svc.chroma.svc.cluster.local",
    port=80,
    ssl=False,
    headers={"X-Chroma-Token": "password"}
)

# Now use as normal
collection = client.get_or_create_collection("experiments")
```

## Monitoring

### Health Check

```bash
curl https://chroma.example.com/api/v2/heartbeat
```

Returns: `{"nanosecond heartbeat": <timestamp>}`

### Pod Status

```bash
kubectl get pods -n chroma
kubectl describe pod -n chroma chroma-0
kubectl logs -n chroma chroma-0 -f
```

### StatefulSet Status

```bash
kubectl get statefulset -n chroma
kubectl describe statefulset chroma -n chroma
```

### Collection Stats

```python
import chromadb

client = chromadb.HttpClient(
    host="chroma.example.com",
    port=443,
    ssl=True,
    headers={"X-Chroma-Token": "password"}
)

# List all collections
collections = client.list_collections()
print(f"Total collections: {len(collections)}")

# Get collection details
for col in collections:
    print(f"Collection: {col.name}")
    print(f"  Count: {col.count()}")
    print(f"  Metadata: {col.metadata}")
```

## Troubleshooting

### Verify Deployment

Check all resources:
```bash
kubectl get all -n chroma
kubectl get pvc -n chroma
kubectl get ingress -n chroma
```

### Authentication Issues

**Issue**: 401 Unauthorized
- **Solution**: Verify `X-Chroma-Token` header matches `ADMIN_PASSWORD`
- **Solution**: Check secret: `kubectl get secret chroma-auth -n chroma -o yaml`

Test authentication:
```bash
# Should fail (no token)
curl https://chroma.example.com/api/v1/collections

# Should succeed
curl -H "X-Chroma-Token: $ADMIN_PASSWORD" \
  https://chroma.example.com/api/v1/collections
```

### Connection Issues

**Issue**: Cannot connect to Chroma
- **Solution**: Check pod is running
- **Solution**: Verify ingress: `kubectl get ingress -n chroma`
- **Solution**: Test internal access: `kubectl run test --rm -it --image=curlimages/curl -- curl http://chromadb-svc.chroma.svc.cluster.local/api/v2/heartbeat`

### Storage Issues

**Issue**: Pod stuck in Pending
- **Solution**: Check PVC status
```bash
kubectl get pvc chroma-data-pvc -n chroma
kubectl describe pvc chroma-data-pvc -n chroma
```

**Issue**: Out of storage
- **Solution**: Increase PVC size
- **Solution**: Delete old collections
- **Solution**: Check storage usage:
```bash
kubectl exec -n chroma chroma-0 -- df -h /data
```

### Performance Issues

**Issue**: Slow queries
- **Solution**: Increase CPU/memory resources
- **Solution**: Reduce n_results in queries
- **Solution**: Optimize collection size (split large collections)

### View Logs

```bash
# Recent logs
kubectl logs -n chroma chroma-0 --tail=100

# Follow logs
kubectl logs -n chroma chroma-0 -f

# Logs from previous instance
kubectl logs -n chroma chroma-0 --previous
```

### Common Issues

**Issue**: Cannot add documents
- **Solution**: Check proxy body size annotation (default: 100m)
- **Solution**: Increase if needed: `kubectl edit ingress chroma-ingress -n chroma`

**Issue**: Collection not found
- **Solution**: List collections to verify name
- **Solution**: Create collection first with `create_collection()` or `get_or_create_collection()`

**Issue**: Embeddings dimension mismatch
- **Solution**: Ensure all embeddings in a collection have same dimension
- **Solution**: Check embedding function consistency

## Testing

The test playbook [18_test.yaml](18_test.yaml) verifies:
- Namespace exists
- StatefulSet is ready
- Pod is running
- Services are configured
- PVC is bound
- Ingress is configured
- API responds to heartbeat
- Can authenticate with token
- Can create collection
- Can add and query embeddings

## Rollback

To uninstall Chroma while preserving data:

```bash
cd ~/thinkube
./scripts/tk_ansible ansible/40_thinkube/optional/chroma/19_rollback.yaml
```

To completely remove including data:

```bash
./scripts/tk_ansible ansible/40_thinkube/optional/chroma/19_rollback.yaml -e remove_data=true
```

**Warning**: Removing data deletes the PVC and all embeddings permanently.

### Backup Data

Before rollback:

```bash
# Create backup pod
kubectl run -n chroma backup --image=busybox --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"backup","image":"busybox","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"chroma-data-pvc"}}]}}'

# Copy data
kubectl cp chroma/backup:/data ./chroma-backup

# Cleanup
kubectl delete pod -n chroma backup
```

## Performance Considerations

- **Memory**: Embeddings stored in memory during queries; size appropriately
- **Disk I/O**: Sequential writes to SQLite; SSDs recommended
- **Query Performance**: Depends on collection size and dimensionality
- **Batch Operations**: Use batch add/query for better performance
- **Collection Size**: Consider splitting large collections (>1M vectors)

## Security Considerations

**Current Configuration**:
- Token-based authentication required
- HTTPS only (SSL redirect enabled)
- No anonymous access
- Telemetry disabled

**For Production**:
1. Rotate auth tokens regularly
2. Use Kubernetes secrets for token management
3. Implement NetworkPolicies for namespace isolation
4. Enable audit logging
5. Monitor API access patterns
6. Use separate tokens per application

## References

- [Chroma Official Documentation](https://docs.trychroma.com/)
- [Chroma GitHub Repository](https://github.com/chroma-core/chroma)
- [LangChain Integration](https://python.langchain.com/docs/integrations/vectorstores/chroma)
- [LlamaIndex Integration](https://docs.llamaindex.ai/en/stable/examples/vector_stores/ChromaIndexDemo.html)
- [Chroma Discord Community](https://discord.gg/chroma)

🤖 [AI-assisted]
