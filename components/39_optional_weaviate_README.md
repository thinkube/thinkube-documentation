# Weaviate Vector Database

## Overview

Weaviate is an open-source vector database designed for AI applications that enables semantic search, similarity matching, and retrieval-augmented generation (RAG). It provides a GraphQL API, REST endpoints, and high-performance gRPC access for storing and querying vector embeddings alongside traditional data. Weaviate supports automatic vectorization, hybrid search combining keyword and vector search, and horizontal scaling for production workloads.

This component deploys Weaviate with API key authentication, persistent storage, and dual-protocol access (HTTP REST + gRPC) for optimal performance across different use cases.

## Dependencies

This component depends on the following Thinkube components:

- **#1 - Kubernetes (k8s-snap)**: Provides the container orchestration platform
- **#2 - Ingress Controller**: Routes external traffic to Weaviate services
- **#4 - SSL/TLS Certificates**: Secures HTTPS and gRPC-over-TLS connections
- **#14 - Harbor**: Provides the container registry for Weaviate images

## Prerequisites

To deploy this component, ensure the following variables are configured in your Ansible inventory:

```yaml
# Domain configuration
domain_name: "example.com"
weaviate_hostname: "weaviate.example.com"
weaviate_grpc_hostname: "weaviate-grpc.example.com"

# Kubernetes configuration
kubeconfig: "/path/to/kubeconfig"
kubectl_bin: "/snap/bin/kubectl"
helm_bin: "/snap/bin/helm"

# Namespace
weaviate_namespace: "weaviate"

# Harbor registry
harbor_registry: "harbor.example.com"
library_project: "library"

# Ingress
primary_ingress_class: "nginx"
primary_ingress_ip: "192.168.1.100"
```

## Playbooks

### **00_install.yaml** - Main Orchestrator

Coordinates the complete Weaviate deployment by executing all component playbooks in the correct sequence.

**Tasks:**
1. Imports `10_deploy.yaml` to deploy Weaviate with authentication
2. Imports `17_configure_discovery.yaml` to register service endpoints

### **10_deploy.yaml** - Weaviate Deployment with API Key Authentication

Deploys Weaviate vector database with API key authentication, persistent storage, and dual-protocol access (HTTP REST + gRPC).

**Configuration Steps:**

**Step 1: Namespace and Secret Setup**
- Creates `weaviate` namespace for component isolation
- Generates secure 32-character API key using random password generation
- Creates `weaviate-auth` Secret containing the API key for client authentication
- Copies wildcard TLS certificate from `default` namespace to `weaviate` namespace as `weaviate-tls-secret`

**Step 2: Authentication ConfigMap**
- Creates `weaviate-auth-config` ConfigMap with authentication configuration
- Enables API key authentication: `AUTHENTICATION_APIKEY_ENABLED: "true"`
- Enables anonymous access for health checks: `AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "true"`
- Allows read-only operations for anonymous users
- Disables default vectorizer to allow custom embedding models

**Step 3: Weaviate StatefulSet Deployment**
- Deploys Weaviate using StatefulSet for stable storage
- Pulls image from Harbor registry: `{harbor_registry}/library/weaviate:latest`
- Mounts authentication ConfigMap at `/weaviate-config/conf.yaml`
- Configures environment variables:
  - `AUTHENTICATION_APIKEY_ENABLED: "true"`
  - `AUTHENTICATION_APIKEY_ALLOWED_KEYS: [API_KEY]`
  - `AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: "true"`
  - `DEFAULT_VECTORIZER_MODULE: none`
  - `ENABLE_MODULES: ""`
  - `PERSISTENCE_DATA_PATH: /var/lib/weaviate`
  - `QUERY_DEFAULTS_LIMIT: "25"`
  - `CLUSTER_HOSTNAME: weaviate-0`
- Exposes ports: 8080 (HTTP), 50051 (gRPC)
- Configures resource requests: 1 CPU, 2Gi memory
- Configures resource limits: 2 CPU, 4Gi memory
- Implements liveness probe on `/v1/.well-known/live`
- Implements readiness probe on `/v1/.well-known/ready`
- Creates 10Gi PersistentVolumeClaim for vector and object storage

**Step 4: Weaviate ClusterIP Services**
- Creates `weaviate` service for HTTP REST API on port 8080
- Creates `weaviate-grpc` service for gRPC access on port 50051
- Both services target the Weaviate StatefulSet pods

**Step 5: HTTP Ingress Configuration**
- Creates Ingress for REST API at `weaviate.example.com`
- Configures TLS with wildcard certificate
- Routes all traffic to `weaviate` service port 8080
- Enables large payload support with `proxy-body-size: "0"`

**Step 6: gRPC Ingress Configuration**
- Creates separate Ingress for gRPC at `weaviate-grpc.example.com`
- Configures TLS with wildcard certificate
- Routes traffic to `weaviate-grpc` service port 50051
- Enables gRPC protocol with `backend-protocol: "GRPC"`
- Enables gRPC-over-TLS for secure high-performance queries

**Step 7: Code-Server CLI Configuration**
- Retrieves Weaviate API key from `weaviate-auth` Secret
- Gets code-server pod name from `code-server` namespace
- Creates Weaviate CLI config from template with:
  - REST endpoint: `https://weaviate.example.com`
  - gRPC endpoint: `weaviate-grpc.example.com:50051`
  - API key for authentication
- Copies config to `/home/thinkube/.weaviate/config.json` in code-server pod
- Sets secure permissions (600) on config file
- Removes temporary config file from control plane

**Step 8: Deployment Verification**
- Waits for Weaviate StatefulSet to become ready
- Verifies Ingress creation for both HTTP and gRPC endpoints
- Displays deployment summary with access URLs

### **17_configure_discovery.yaml** - Service Discovery Configuration

Registers Weaviate endpoints and metadata with the Thinkube service discovery system for integration with the control plane.

**Tasks:**
1. Reads component version from `VERSION` file (0.1.0)
2. Retrieves Weaviate API key from `weaviate-auth` Secret
3. Gets code-server pod name for environment variable updates
4. Creates Weaviate config from template and copies to code-server
5. Creates `thinkube-service-config` ConfigMap with:
   - Service metadata: name, display name, description, type (optional), category (ai)
   - Component version: 0.1.0
   - Icon: `/icons/tk_vector.svg`
   - Endpoints:
     - **api** (primary): `https://weaviate.example.com` with health check at `/v1/.well-known/ready`
     - **grpc**: `weaviate-grpc.example.com:50051` for high-performance queries
     - **graphql**: `https://weaviate.example.com/v1/graphql` for GraphQL queries
   - Scaling configuration: StatefulSet `weaviate` in `weaviate` namespace, min 1 replica, can be disabled
   - Metadata: API key authentication, persistent storage, BSD-3-Clause license
   - Environment variables: `WEAVIATE_URL`, `WEAVIATE_GRPC_URL`, `WEAVIATE_API_KEY`
6. Updates code-server environment variables via `code_server_env_update` role
7. Displays service registration summary

## Deployment

Weaviate is automatically deployed via the **thinkube-control Optional Components** interface at `https://thinkube.example.com/optional-components`.

To deploy manually:

```bash
cd ~/thinkube
./scripts/run_ansible.sh ansible/40_thinkube/optional/weaviate/00_install.yaml
```

The deployment process typically takes 3-5 minutes and includes:
1. Namespace and authentication setup with API key generation
2. Weaviate StatefulSet deployment with persistent storage
3. Dual ingress configuration for HTTP REST and gRPC access
4. CLI configuration in code-server for developer access
5. Service discovery registration with the Thinkube control plane

## Access Points

After deployment, Weaviate is accessible via:

- **REST API**: `https://weaviate.example.com`
- **gRPC Endpoint**: `weaviate-grpc.example.com:50051`
- **GraphQL API**: `https://weaviate.example.com/v1/graphql`
- **Health Check**: `https://weaviate.example.com/v1/.well-known/ready`

### Authentication

All API requests require authentication using the API key stored in the `weaviate-auth` Secret:

```bash
# Retrieve API key
kubectl get secret -n weaviate weaviate-auth -o jsonpath='{.data.api-key}' | base64 -d

# Use API key in requests
curl -H "Authorization: Bearer YOUR_API_KEY" https://weaviate.example.com/v1/meta
```

Anonymous access is enabled for health check endpoints only.

## Configuration

### Authentication Configuration

Weaviate uses API key authentication configured via the `weaviate-auth-config` ConfigMap:

```yaml
authentication:
  apikey:
    enabled: true
    allowed_keys:
      - YOUR_API_KEY
  anonymous_access:
    enabled: true
```

### Storage Configuration

Weaviate uses a 10Gi PersistentVolumeClaim for vector and object storage:

```yaml
persistence:
  enabled: true
  size: 10Gi
  storageClass: ""  # Uses default storage class
  accessModes:
    - ReadWriteOnce
```

### Resource Configuration

Default resource allocation:

```yaml
resources:
  requests:
    cpu: "1"
    memory: "2Gi"
  limits:
    cpu: "2"
    memory: "4Gi"
```

### Vectorizer Configuration

By default, Weaviate is configured with no default vectorizer (`DEFAULT_VECTORIZER_MODULE: none`), allowing you to:
- Use custom embedding models via the API
- Bring your own vectors from external embedding services
- Configure module-specific vectorizers per schema class

## Usage

### Python Client

Install the Weaviate Python client:

```bash
pip install weaviate-client
```

Connect to Weaviate using the API key:

```python
import weaviate
from weaviate.auth import AuthApiKey

# Retrieve API key from environment
import os
api_key = os.getenv("WEAVIATE_API_KEY")

# Connect to Weaviate
client = weaviate.Client(
    url="https://weaviate.example.com",
    auth_client_secret=AuthApiKey(api_key=api_key)
)

# Check connection
print(client.is_ready())
```

### Create a Schema

Define a schema for your data:

```python
schema = {
    "classes": [
        {
            "class": "Document",
            "description": "A document with text content",
            "vectorizer": "none",  # Bring your own vectors
            "properties": [
                {
                    "name": "content",
                    "dataType": ["text"],
                    "description": "The document content"
                },
                {
                    "name": "title",
                    "dataType": ["string"],
                    "description": "The document title"
                },
                {
                    "name": "category",
                    "dataType": ["string"],
                    "description": "Document category"
                }
            ]
        }
    ]
}

client.schema.create(schema)
```

### Insert Data with Vectors

Add objects with custom vectors:

```python
import numpy as np

# Example: Insert document with custom embedding
doc_vector = np.random.rand(768).tolist()  # 768-dim vector

client.data_object.create(
    data_object={
        "content": "Weaviate is a vector database for AI applications.",
        "title": "Introduction to Weaviate",
        "category": "documentation"
    },
    class_name="Document",
    vector=doc_vector
)
```

### Vector Search

Perform semantic search using vector similarity:

```python
# Search with a query vector
query_vector = np.random.rand(768).tolist()

result = (
    client.query
    .get("Document", ["title", "content", "category"])
    .with_near_vector({"vector": query_vector})
    .with_limit(5)
    .do()
)

print(result)
```

### GraphQL Queries

Use GraphQL for advanced queries:

```python
query = """
{
  Get {
    Document(limit: 10) {
      title
      content
      category
      _additional {
        id
        certainty
      }
    }
  }
}
"""

result = client.query.raw(query)
print(result)
```

### gRPC Client (High Performance)

For production workloads requiring low latency:

```python
import weaviate
from weaviate.auth import AuthApiKey

client = weaviate.Client(
    url="https://weaviate.example.com",
    auth_client_secret=AuthApiKey(api_key=api_key),
    additional_config=weaviate.AdditionalConfig(
        grpc_port_experimental=50051,
        grpc_secure_experimental=True
    )
)

# gRPC is automatically used for batch operations
# and queries when available
```

### Batch Import

Efficiently import large datasets:

```python
client.batch.configure(batch_size=100)

with client.batch as batch:
    for i in range(1000):
        vector = np.random.rand(768).tolist()
        batch.add_data_object(
            data_object={
                "title": f"Document {i}",
                "content": f"Content for document {i}",
                "category": "batch-import"
            },
            class_name="Document",
            vector=vector
        )
```

### CLI Access from Code-Server

Access Weaviate from the code-server terminal using the pre-configured CLI:

```bash
# Configuration is automatically loaded from ~/.weaviate/config.json
export WEAVIATE_URL=https://weaviate.example.com
export WEAVIATE_GRPC_URL=weaviate-grpc.example.com:50051
export WEAVIATE_API_KEY=$(cat ~/.weaviate/config.json | jq -r '.api_key')

# Use with Python client
python3 -c "import weaviate; print(weaviate.Client(url='${WEAVIATE_URL}', auth_client_secret=weaviate.AuthApiKey('${WEAVIATE_API_KEY}')).is_ready())"
```

## Integration

### LangChain Integration

Use Weaviate as a vector store in LangChain:

```python
from langchain.vectorstores import Weaviate
from langchain.embeddings import OpenAIEmbeddings
import weaviate
from weaviate.auth import AuthApiKey

# Connect to Weaviate
client = weaviate.Client(
    url="https://weaviate.example.com",
    auth_client_secret=AuthApiKey(api_key=os.getenv("WEAVIATE_API_KEY"))
)

# Create LangChain vector store
embeddings = OpenAIEmbeddings()
vectorstore = Weaviate(
    client=client,
    index_name="Document",
    text_key="content",
    embedding=embeddings
)

# Add documents
from langchain.schema import Document

docs = [
    Document(page_content="First document", metadata={"title": "Doc 1"}),
    Document(page_content="Second document", metadata={"title": "Doc 2"})
]

vectorstore.add_documents(docs)

# Similarity search
results = vectorstore.similarity_search("query text", k=5)
```

### LlamaIndex Integration

Use Weaviate with LlamaIndex:

```python
from llama_index import VectorStoreIndex, ServiceContext
from llama_index.vector_stores import WeaviateVectorStore
from llama_index.storage.storage_context import StorageContext
import weaviate
from weaviate.auth import AuthApiKey

# Connect to Weaviate
client = weaviate.Client(
    url="https://weaviate.example.com",
    auth_client_secret=AuthApiKey(api_key=os.getenv("WEAVIATE_API_KEY"))
)

# Create vector store
vector_store = WeaviateVectorStore(
    weaviate_client=client,
    index_name="Document"
)

storage_context = StorageContext.from_defaults(vector_store=vector_store)

# Build index
index = VectorStoreIndex.from_documents(
    documents,
    storage_context=storage_context
)

# Query
query_engine = index.as_query_engine()
response = query_engine.query("What is Weaviate?")
```

### RAG Pipeline Integration

Integrate Weaviate into retrieval-augmented generation pipelines:

```python
from openai import OpenAI
import weaviate
from weaviate.auth import AuthApiKey

# Initialize clients
weaviate_client = weaviate.Client(
    url="https://weaviate.example.com",
    auth_client_secret=AuthApiKey(api_key=os.getenv("WEAVIATE_API_KEY"))
)

openai_client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

def rag_query(query: str, k: int = 3):
    # 1. Generate query embedding
    response = openai_client.embeddings.create(
        model="text-embedding-3-small",
        input=query
    )
    query_vector = response.data[0].embedding

    # 2. Retrieve relevant documents from Weaviate
    results = (
        weaviate_client.query
        .get("Document", ["title", "content"])
        .with_near_vector({"vector": query_vector})
        .with_limit(k)
        .do()
    )

    # 3. Build context from retrieved documents
    context = "\n\n".join([
        f"{doc['title']}: {doc['content']}"
        for doc in results['data']['Get']['Document']
    ])

    # 4. Generate answer with LLM
    completion = openai_client.chat.completions.create(
        model="gpt-4",
        messages=[
            {"role": "system", "content": "Answer based on the provided context."},
            {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {query}"}
        ]
    )

    return completion.choices[0].message.content

# Use RAG pipeline
answer = rag_query("What are vector databases?")
print(answer)
```

### OpenSearch Integration

Use Weaviate alongside OpenSearch (#35) for hybrid search (keyword + semantic):

```python
from opensearchpy import OpenSearch
import weaviate
from weaviate.auth import AuthApiKey

# Connect to both systems
weaviate_client = weaviate.Client(
    url="https://weaviate.example.com",
    auth_client_secret=AuthApiKey(api_key=os.getenv("WEAVIATE_API_KEY"))
)

opensearch_client = OpenSearch(
    hosts=["https://opensearch.example.com"],
    http_auth=(os.getenv("OPENSEARCH_USER"), os.getenv("OPENSEARCH_PASSWORD"))
)

def hybrid_search(query: str, query_vector: list, k: int = 10):
    # Keyword search in OpenSearch
    keyword_results = opensearch_client.search(
        index="documents",
        body={
            "query": {"match": {"content": query}},
            "size": k
        }
    )

    # Semantic search in Weaviate
    vector_results = (
        weaviate_client.query
        .get("Document", ["title", "content"])
        .with_near_vector({"vector": query_vector})
        .with_limit(k)
        .do()
    )

    # Combine and re-rank results
    # (implementation depends on your ranking strategy)
    return merge_results(keyword_results, vector_results)
```

## Monitoring

### Health Checks

Weaviate provides built-in health endpoints:

```bash
# Liveness check
curl https://weaviate.example.com/v1/.well-known/live

# Readiness check
curl https://weaviate.example.com/v1/.well-known/ready
```

### Metrics Endpoint

Weaviate exposes Prometheus metrics at `/metrics`:

```bash
curl -H "Authorization: Bearer YOUR_API_KEY" https://weaviate.example.com/metrics
```

### Key Metrics to Monitor

- **weaviate_object_count_total**: Total number of objects stored
- **weaviate_query_duration_seconds**: Query latency
- **weaviate_batch_duration_seconds**: Batch import performance
- **weaviate_vector_index_size**: Size of vector indexes
- **weaviate_lsm_bloom_filter_size**: Storage efficiency metrics

### Kubernetes Resources

Monitor Weaviate pod status:

```bash
# Check pod status
kubectl get pods -n weaviate

# View pod logs
kubectl logs -n weaviate -l app=weaviate --tail=100 -f

# Check resource usage
kubectl top pod -n weaviate

# Check PVC status
kubectl get pvc -n weaviate
```

### Integration with Prometheus (#31)

If Prometheus is deployed, create a ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: weaviate
  namespace: weaviate
spec:
  selector:
    matchLabels:
      app: weaviate
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

## Troubleshooting

### Connection Issues

**Problem**: Cannot connect to Weaviate API

```bash
# Check pod status
kubectl get pods -n weaviate

# Check pod logs for errors
kubectl logs -n weaviate -l app=weaviate

# Verify service endpoints
kubectl get svc -n weaviate

# Check ingress configuration
kubectl get ingress -n weaviate
```

### Authentication Failures

**Problem**: "401 Unauthorized" errors

```bash
# Verify API key exists
kubectl get secret -n weaviate weaviate-auth

# Retrieve current API key
kubectl get secret -n weaviate weaviate-auth -o jsonpath='{.data.api-key}' | base64 -d

# Test authentication
curl -H "Authorization: Bearer $(kubectl get secret -n weaviate weaviate-auth -o jsonpath='{.data.api-key}' | base64 -d)" \
  https://weaviate.example.com/v1/meta
```

### Storage Issues

**Problem**: Pod stuck in Pending state due to PVC issues

```bash
# Check PVC status
kubectl get pvc -n weaviate

# Describe PVC for events
kubectl describe pvc -n weaviate weaviate-data-weaviate-0

# Check available storage classes
kubectl get storageclass

# Verify node storage capacity
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### Performance Issues

**Problem**: Slow query performance

1. **Check resource usage**:
   ```bash
   kubectl top pod -n weaviate
   ```

2. **Increase resources** if needed:
   ```bash
   # Edit StatefulSet
   kubectl edit statefulset -n weaviate weaviate

   # Update resource limits
   resources:
     requests:
       cpu: "2"
       memory: "4Gi"
     limits:
       cpu: "4"
       memory: "8Gi"
   ```

3. **Enable gRPC** for better performance:
   ```python
   client = weaviate.Client(
       url="https://weaviate.example.com",
       auth_client_secret=AuthApiKey(api_key=api_key),
       additional_config=weaviate.AdditionalConfig(
           grpc_port_experimental=50051,
           grpc_secure_experimental=True
       )
   )
   ```

### Schema Issues

**Problem**: Schema errors or conflicts

```bash
# Get current schema
curl -H "Authorization: Bearer YOUR_API_KEY" https://weaviate.example.com/v1/schema | jq

# Delete a class
curl -X DELETE -H "Authorization: Bearer YOUR_API_KEY" \
  https://weaviate.example.com/v1/schema/Document

# Recreate schema
curl -X POST -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d @schema.json \
  https://weaviate.example.com/v1/schema
```

### gRPC Connection Issues

**Problem**: Cannot connect via gRPC

```bash
# Test gRPC endpoint with grpcurl
grpcurl -d '{"meta": {}}' \
  -H "Authorization: Bearer YOUR_API_KEY" \
  weaviate-grpc.example.com:50051 \
  weaviate.v1.Weaviate/Meta

# Check gRPC ingress
kubectl describe ingress -n weaviate weaviate-grpc-ingress
```

### Data Inconsistencies

**Problem**: Missing or corrupted data

```bash
# Check Weaviate logs for errors
kubectl logs -n weaviate -l app=weaviate | grep -i error

# Verify object count
curl -H "Authorization: Bearer YOUR_API_KEY" \
  https://weaviate.example.com/v1/schema | jq '.classes[].invertedIndexConfig'

# Check storage volume
kubectl exec -n weaviate weaviate-0 -- df -h /var/lib/weaviate
```

## Testing

### API Connectivity Test

```bash
# Test REST API
curl -H "Authorization: Bearer YOUR_API_KEY" \
  https://weaviate.example.com/v1/meta | jq

# Expected response
{
  "hostname": "weaviate-0",
  "version": "...",
  "modules": {}
}
```

### Schema Creation Test

```bash
# Create test schema
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "class": "TestDocument",
    "vectorizer": "none",
    "properties": [
      {
        "name": "content",
        "dataType": ["text"]
      }
    ]
  }' \
  https://weaviate.example.com/v1/schema

# Verify schema
curl -H "Authorization: Bearer YOUR_API_KEY" \
  https://weaviate.example.com/v1/schema/TestDocument | jq
```

### Object Creation Test

```bash
# Create test object with vector
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "class": "TestDocument",
    "properties": {
      "content": "This is a test document"
    },
    "vector": [0.1, 0.2, 0.3, 0.4]
  }' \
  https://weaviate.example.com/v1/objects

# Query objects
curl -H "Authorization: Bearer YOUR_API_KEY" \
  "https://weaviate.example.com/v1/objects?class=TestDocument" | jq
```

### Vector Search Test

```bash
# Search with vector
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{
      Get {
        TestDocument(nearVector: {vector: [0.1, 0.2, 0.3, 0.4]}) {
          content
          _additional {
            id
            certainty
          }
        }
      }
    }"
  }' \
  https://weaviate.example.com/v1/graphql | jq
```

### GraphQL Test

```bash
# Test GraphQL endpoint
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{
      Get {
        TestDocument {
          content
          _additional {
            id
          }
        }
      }
    }"
  }' \
  https://weaviate.example.com/v1/graphql | jq
```

### Python Client Test

```python
import weaviate
from weaviate.auth import AuthApiKey
import os

# Connect
client = weaviate.Client(
    url="https://weaviate.example.com",
    auth_client_secret=AuthApiKey(api_key=os.getenv("WEAVIATE_API_KEY"))
)

# Test connection
assert client.is_ready(), "Weaviate is not ready"

# Test schema
schema = client.schema.get()
print(f"Schema classes: {[c['class'] for c in schema['classes']]}")

# Test object creation
uuid = client.data_object.create(
    data_object={"content": "Test from Python client"},
    class_name="TestDocument",
    vector=[0.5, 0.6, 0.7, 0.8]
)
print(f"Created object: {uuid}")

# Test query
result = client.query.get("TestDocument", ["content"]).with_limit(1).do()
print(f"Query result: {result}")

print("All tests passed!")
```

### Performance Benchmark

```python
import weaviate
from weaviate.auth import AuthApiKey
import time
import numpy as np

client = weaviate.Client(
    url="https://weaviate.example.com",
    auth_client_secret=AuthApiKey(api_key=os.getenv("WEAVIATE_API_KEY"))
)

# Batch import benchmark
print("Testing batch import performance...")
client.batch.configure(batch_size=100)

start_time = time.time()
with client.batch as batch:
    for i in range(1000):
        vector = np.random.rand(768).tolist()
        batch.add_data_object(
            data_object={"content": f"Document {i}"},
            class_name="TestDocument",
            vector=vector
        )

import_time = time.time() - start_time
print(f"Imported 1000 objects in {import_time:.2f}s ({1000/import_time:.0f} objects/sec)")

# Query benchmark
print("\nTesting query performance...")
query_times = []
for _ in range(10):
    query_vector = np.random.rand(768).tolist()
    start_time = time.time()
    client.query.get("TestDocument", ["content"]).with_near_vector({"vector": query_vector}).with_limit(10).do()
    query_times.append(time.time() - start_time)

print(f"Average query time: {np.mean(query_times)*1000:.2f}ms")
print(f"Query throughput: {1/np.mean(query_times):.0f} queries/sec")
```

## Rollback

To rollback or remove the Weaviate deployment:

```bash
# Delete Weaviate StatefulSet and services
kubectl delete statefulset -n weaviate weaviate
kubectl delete svc -n weaviate weaviate weaviate-grpc

# Delete ingresses
kubectl delete ingress -n weaviate weaviate-http-ingress weaviate-grpc-ingress

# Delete ConfigMaps and Secrets
kubectl delete configmap -n weaviate weaviate-auth-config thinkube-service-config
kubectl delete secret -n weaviate weaviate-auth weaviate-tls-secret

# Optional: Delete persistent data (WARNING: This deletes all vectors and objects)
kubectl delete pvc -n weaviate weaviate-data-weaviate-0

# Optional: Delete namespace
kubectl delete namespace weaviate
```

**Note**: Deleting the PVC will permanently remove all stored vectors and objects. Ensure you have backups before proceeding.

## References

- [Weaviate Documentation](https://weaviate.io/developers/weaviate)
- [Weaviate Python Client](https://weaviate.io/developers/weaviate/client-libraries/python)
- [Weaviate GraphQL API](https://weaviate.io/developers/weaviate/api/graphql)
- [Weaviate gRPC API](https://weaviate.io/developers/weaviate/api/grpc)
- [Vector Search Concepts](https://weaviate.io/developers/weaviate/concepts/vector-search)
- [Weaviate Schema](https://weaviate.io/developers/weaviate/config-refs/schema)
- [LangChain Weaviate Integration](https://python.langchain.com/docs/integrations/vectorstores/weaviate)
- [LlamaIndex Weaviate Integration](https://docs.llamaindex.ai/en/stable/examples/vector_stores/WeaviateIndexDemo.html)

---

🤖 [AI-assisted]
