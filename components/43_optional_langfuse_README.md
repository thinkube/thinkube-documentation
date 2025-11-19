# Langfuse - LLM Observability Platform

Component #42 in the Thinkube Platform stack.

## Overview

Langfuse is an open-source LLM engineering platform for tracing, evaluating, and monitoring LLM applications. It provides observability into production LLM applications with detailed trace analysis, cost tracking, and performance metrics. In the Thinkube Platform, Langfuse serves as the observability layer for AI applications, integrating with LiteLLM, LangChain, LlamaIndex, and custom LLM integrations.

**Key Features**:
- LLM tracing with input/output logging
- Cost tracking across LLM providers
- Performance metrics (latency, token usage, error rates)
- Prompt management with version control
- User feedback collection and analysis
- Dataset management for evaluations
- Multi-framework integration (LangChain, LlamaIndex, OpenAI SDK)

## Dependencies

Langfuse requires the following Thinkube components:

- **#5 PostgreSQL** - Primary metadata storage for traces, prompts, datasets, users
- **#6 Keycloak** - OIDC authentication for web interface
- **#34 ClickHouse** - Analytics database for high-volume trace storage and queries
- **#36 Valkey** - Session caching for Langfuse v3 requirements
- **#9 SeaweedFS** - S3-compatible storage for event and media uploads

## Prerequisites

```yaml
kubernetes:
  distribution: k8s-snap
  version: "1.34.0"

core_components:
  - name: postgresql
    version: "18"
    status: running
  - name: keycloak
    realm: thinkube
    status: configured
  - name: clickhouse
    version: "24.x"
    status: running
  - name: valkey
    version: "8.x"
    status: running
  - name: seaweedfs
    s3_enabled: true
    status: running

harbor:
  image: library/langfuse:3.113.0
  access: required
```

## Playbooks

Deployment is automatically orchestrated by thinkube-control via [00_install.yaml](00_install.yaml:31-38).

### **Configure Keycloak OIDC** - [10_configure_keycloak.yaml](10_configure_keycloak.yaml)

Creates Keycloak OIDC client for Langfuse authentication using the standardized `keycloak_setup` role. Langfuse uses native Keycloak provider (NextAuth.js integration) for SSO.

**Client Configuration**:
- Client ID: `langfuse`
- Protocol: `openid-connect`
- Flow: Standard flow + direct access grants
- Public client: `false` (confidential)
- Redirect URIs: `/api/auth/callback/keycloak`, wildcard
- Default scopes: `email`, `profile`, `openid`, `offline_access`
- Access token lifespan: 3600s
- No custom roles (Langfuse manages permissions internally)

**Kubernetes Secret**: Client secret stored in `langfuse-oauth-secret` in `langfuse` namespace for deployment consumption.

### **Deploy Langfuse** - [11_deploy.yaml](11_deploy.yaml)

Deploys Langfuse v3.113.0 with PostgreSQL, ClickHouse, Valkey, and SeaweedFS integrations.

**Step 1: Namespace and TLS** (lines 70-103)
- Creates `langfuse` namespace
- Copies wildcard TLS certificate from `default` namespace

**Step 2: Keycloak OAuth Credentials** (lines 108-120)
- Retrieves client secret from `langfuse-oauth-secret`
- Sets fact for deployment configuration

**Step 3: S3 Bucket Creation** (lines 125-169)
- Retrieves SeaweedFS S3 credentials from `seaweedfs-s3-config` secret
- Creates `langfuse-events` bucket (event upload storage)
- Creates `langfuse-media` bucket (media upload storage)
- Uses s3cmd with signature v2 for SeaweedFS compatibility

**Step 4: Secret Generation** (lines 174-276)
- `NEXTAUTH_SECRET`: 64-char random string for NextAuth.js session encryption
- `SALT`: 32-char random string for hashing
- `ENCRYPTION_KEY`: 64-char hex string (256-bit AES encryption key for sensitive data)
- `ADMIN_API_KEY`: 64-char hex admin API key
- Project keys: `lf_pk_<32-hex>` (public), `lf_sk_<64-hex>` (secret) for default project
- Creates `langfuse-config` secret with comprehensive environment variables:
  - **Database**: PostgreSQL connection string
  - **ClickHouse**: HTTP API (8123) + migration URL (TCP 9000), cluster disabled
  - **Valkey**: Redis-compatible session storage
  - **S3 Event Upload**: SeaweedFS bucket for events, force path style, internal endpoint
  - **S3 Media Upload**: SeaweedFS bucket for media, force path style, internal endpoint
  - **NextAuth**: HTTPS URL, secret, salt
  - **Keycloak OIDC**: Client ID/secret, issuer URL, allow account linking
  - **Initial Project**: Organization/project IDs, names, API keys
  - **Admin API**: Admin API key for management

**Step 5: Deployment** (lines 281-355)
- Init container 1: Waits for PostgreSQL (busybox netcat)
- Init container 2: Creates database `langfuse_db`, grants privileges to admin user
- Main container: Langfuse 3.113.0 from Harbor
  - Port 3000 (HTTP)
  - Environment from `langfuse-config` secret
  - Resources: 500m-2 CPU, 1Gi-4Gi memory
  - Liveness probe: `/api/public/health` (30s initial delay)
  - Readiness probe: `/api/public/health` (10s initial delay)

**Step 6: Service** (lines 360-380)
- ClusterIP service on port 3000
- Selector: `app=langfuse`

**Step 7: Ingress** (lines 385-415)
- NGINX ingress with primary class
- TLS termination with wildcard certificate
- Annotations: 50m body size, 600s timeouts
- Path: `/` (all routes)

**Step 8: Readiness Check and CLI Configuration** (lines 420-479)
- Waits for pods to reach Running state
- Polls `/api/public/health` until 200 response
- Creates credentials template at `/tmp/langfuse-credentials` (YAML format)
- Copies credentials to code-server pod at `/home/thinkube/.langfuse/credentials`
- Sets permissions to 600
- Displays deployment results with URL, database, authentication, organization/project defaults

### **Configure Service Discovery** - [17_configure_discovery.yaml](17_configure_discovery.yaml)

Registers Langfuse with thinkube-control service discovery system.

**Metadata Extraction** (lines 34-47)
- Reads `langfuse-config` secret
- Extracts `LANGFUSE_INIT_PROJECT_PUBLIC_KEY` and `LANGFUSE_INIT_PROJECT_SECRET_KEY`

**ConfigMap Creation** (lines 49-100)
- Name: `thinkube-service-config` in `langfuse` namespace
- Labels: `thinkube.io/managed`, `thinkube.io/service-type: optional`, `thinkube.io/service-name: langfuse`
- Service metadata:
  - Display name: "Langfuse"
  - Description: "LLM observability platform for tracing and monitoring AI applications"
  - Category: `ai`
  - Icon: `/icons/tk_observability.svg`
  - Primary endpoint: Web interface + API (`https://langfuse.example.com`)
  - Health URL: `/api/public/health`
  - Dependencies: `postgresql`, `keycloak`
  - Scaling: Deployment `langfuse`, min 1 replica, can disable
  - Environment variables: `LANGFUSE_HOST`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`

**Environment Update** (line 118): Updates code-server environment with Langfuse credentials via `code_server_env_update` role.

## Deployment

Automatically deployed via thinkube-control Optional Components interface at https://thinkube.example.com/optional-components.

The web interface provides:
- One-click deployment with real-time progress monitoring
- Automatic dependency verification (PostgreSQL, Keycloak, ClickHouse, Valkey, SeaweedFS)
- WebSocket-based log streaming during installation
- Health check validation post-deployment
- Rollback capability if deployment fails

## Access Points

### Web Interface

**URL**: https://langfuse.example.com

**Authentication**: Keycloak SSO (NextAuth.js native provider)

**Features**:
- Trace explorer with search and filtering
- Prompt management with version control
- Dataset management for evaluations
- User feedback dashboard
- Cost analytics and usage metrics
- Project and API key management

### API Endpoints

**Base URL**: https://langfuse.example.com/api

**Public API**: `/api/public/*`
- Health check: `/api/public/health`
- Ingestion endpoint for traces
- Authentication: API keys (public + secret)

**Admin API**: Requires `ADMIN_API_KEY`

## Configuration

### Database Backends

**PostgreSQL**:
```bash
# Database: langfuse_db
# Connection: postgresql-official.postgres.svc.cluster.local:5432
# Schema: Auto-migrated on startup
# Data: Users, organizations, projects, API keys, prompts, datasets
```

**ClickHouse**:
```bash
# Connection: HTTP (8123), TCP (9000)
# Service: clickhouse-clickhouse.clickhouse.svc.cluster.local
# Data: High-volume trace observations and events
# Cluster: Disabled (single-node)
# Migrations: Runs on startup via CLICKHOUSE_MIGRATION_URL
```

**Valkey**:
```bash
# Service: valkey.valkey.svc.cluster.local:6379
# Purpose: Session caching (Langfuse v3 requirement)
# No authentication (internal cluster traffic)
```

### S3 Storage (SeaweedFS)

**Event Uploads**:
```bash
# Bucket: langfuse-events
# Endpoint: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333
# Region: us-east-1 (AWS compatibility)
# Path style: Force enabled
# Purpose: Ingestion event buffering
```

**Media Uploads**:
```bash
# Bucket: langfuse-media
# Endpoint: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333
# Region: us-east-1
# Path style: Force enabled
# Purpose: User-uploaded images, files attached to traces
```

### Initial Project

Langfuse deploys with a pre-configured default project:

```yaml
Organization:
  ID: thinkube
  Name: Thinkube

Project:
  ID: default
  Name: Default Project
  Public Key: lf_pk_<32-hex-chars>
  Secret Key: lf_sk_<64-hex-chars>
```

API keys are stored in:
- Kubernetes secret: `langfuse-config`
- code-server: `/home/thinkube/.langfuse/credentials`
- Service discovery ConfigMap for environment injection

### Resource Limits

```yaml
Deployment:
  Replicas: 1
  Resources:
    Requests:
      CPU: 500m
      Memory: 1Gi
    Limits:
      CPU: 2
      Memory: 4Gi
```

## Usage

### Python SDK

```python
from langfuse import Langfuse

# Initialize client with credentials from service discovery
langfuse = Langfuse(
    public_key="lf_pk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    secret_key="lf_sk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    host="https://langfuse.example.com"
)

# Create a trace
trace = langfuse.trace(
    name="llm-pipeline",
    user_id="user_123",
    metadata={"environment": "production"}
)

# Log an LLM generation
generation = trace.generation(
    name="openai-completion",
    model="gpt-4",
    model_parameters={"temperature": 0.7, "max_tokens": 500},
    input=[{"role": "user", "content": "Explain quantum computing"}],
    output="Quantum computing is a type of computation...",
    usage={"prompt_tokens": 15, "completion_tokens": 120, "total_tokens": 135},
    metadata={"provider": "openai"}
)

# Add user feedback
trace.score(
    name="user-rating",
    value=5,
    comment="Excellent explanation"
)

# Flush to ensure data is sent
langfuse.flush()
```

### LangChain Integration

```python
from langchain.callbacks import LangfuseCallbackHandler
from langchain_openai import ChatOpenAI
from langchain.prompts import ChatPromptTemplate
from langchain.schema.runnable import RunnableSequence

# Initialize callback handler
langfuse_handler = LangfuseCallbackHandler(
    public_key="lf_pk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    secret_key="lf_sk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    host="https://langfuse.example.com"
)

# Create LangChain components
prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful AI assistant."),
    ("human", "{input}")
])
llm = ChatOpenAI(model="gpt-4")
chain = prompt | llm

# Execute with tracing
result = chain.invoke(
    {"input": "What is machine learning?"},
    config={"callbacks": [langfuse_handler]}
)
```

### LlamaIndex Integration

```python
from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
from llama_index.core.callbacks import CallbackManager
from llama_index.callbacks.langfuse import LangfuseCallbackHandler

# Initialize callback handler
langfuse_handler = LangfuseCallbackHandler(
    public_key="lf_pk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    secret_key="lf_sk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    host="https://langfuse.example.com"
)

# Configure LlamaIndex with callback manager
callback_manager = CallbackManager([langfuse_handler])

# Load documents and create index
documents = SimpleDirectoryReader("data").load_data()
index = VectorStoreIndex.from_documents(
    documents,
    callback_manager=callback_manager
)

# Query with tracing
query_engine = index.as_query_engine()
response = query_engine.query("What are the key findings in the documents?")
```

### OpenAI SDK Direct Integration

```python
from langfuse.openai import OpenAI

# Initialize OpenAI client with Langfuse wrapper
client = OpenAI(
    public_key="lf_pk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    secret_key="lf_sk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    host="https://langfuse.example.com"
)

# All OpenAI calls are automatically traced
response = client.chat.completions.create(
    model="gpt-4",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Tell me a joke"}
    ],
    langfuse_prompt="joke-prompt-v1",  # Link to prompt version
    langfuse_metadata={"user_id": "user_456"}
)
```

### Prompt Management

```python
from langfuse import Langfuse

langfuse = Langfuse()

# Fetch a prompt by name
prompt = langfuse.get_prompt("customer-support-v1")

# Compile with variables
compiled = prompt.compile(
    customer_name="Alice",
    issue_type="billing"
)

# Use in LLM call
response = client.chat.completions.create(
    model="gpt-4",
    messages=compiled,
    langfuse_prompt=prompt
)
```

## Integration

### With LiteLLM (#41)

LiteLLM can automatically log all proxy requests to Langfuse:

```python
# In LiteLLM config.yaml
litellm_settings:
  success_callback: ["langfuse"]

# Set environment variables in LiteLLM deployment
environment_variables:
  - name: LANGFUSE_PUBLIC_KEY
    value: "lf_pk_..."
  - name: LANGFUSE_SECRET_KEY
    value: "lf_sk_..."
  - name: LANGFUSE_HOST
    value: "https://langfuse.example.com"
```

### With NATS (#32)

Stream LLM events from NATS to Langfuse for centralized observability:

```python
import asyncio
import json
import nats
from langfuse import Langfuse

langfuse = Langfuse()

async def log_llm_event(msg):
    data = json.loads(msg.data.decode())
    trace = langfuse.trace(
        name=data.get('operation', 'nats-event'),
        user_id=data.get('user_id'),
        metadata=data.get('metadata', {})
    )
    if 'input' in data and 'output' in data:
        trace.generation(
            name=data.get('model', 'unknown'),
            input=data['input'],
            output=data['output'],
            usage=data.get('usage', {})
        )

async def main():
    nc = await nats.connect("nats://nats.nats.svc.cluster.local:4222")
    await nc.subscribe("ai.llm.completions", cb=log_llm_event)

asyncio.run(main())
```

### With ClickHouse (#34)

Langfuse v3 automatically uses ClickHouse for high-volume analytics queries on observations. Direct SQL access for custom analytics:

```python
import clickhouse_connect

client = clickhouse_connect.get_client(
    host='clickhouse-clickhouse.clickhouse.svc.cluster.local',
    port=8123,
    username='default',
    password='admin-password'
)

# Query trace statistics
result = client.query("""
    SELECT
        model,
        count() as call_count,
        avg(total_cost) as avg_cost,
        avg(latency) as avg_latency
    FROM langfuse.observations
    WHERE timestamp > now() - INTERVAL 1 DAY
    GROUP BY model
    ORDER BY call_count DESC
""")

for row in result.result_rows:
    print(f"Model: {row[0]}, Calls: {row[1]}, Avg Cost: ${row[2]:.4f}, Avg Latency: {row[3]:.2f}ms")
```

## Monitoring

### Health Checks

```bash
# Application health
curl https://langfuse.example.com/api/public/health

# Expected response
{"status":"OK"}
```

```bash
# Pod status
kubectl get pods -n langfuse

# Check readiness
kubectl get pods -n langfuse -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
```

### Logs

```bash
# Main application logs
kubectl logs -n langfuse deployment/langfuse -f

# Filter for errors
kubectl logs -n langfuse deployment/langfuse | grep -i error

# Migration logs (init container)
kubectl logs -n langfuse deployment/langfuse -c init-db
```

### Database Status

```bash
# Check PostgreSQL connection
kubectl exec -n langfuse deployment/langfuse -- sh -c 'echo "SELECT version();" | psql $DATABASE_URL'

# Check ClickHouse connection
kubectl exec -n langfuse deployment/langfuse -- sh -c 'curl -s $CLICKHOUSE_URL/ping'

# Check Valkey connection
kubectl exec -n langfuse deployment/langfuse -- sh -c 'nc -zv valkey.valkey.svc.cluster.local 6379'
```

### Trace Ingestion Rate

```bash
# Query ClickHouse for ingestion statistics
kubectl exec -n clickhouse statefulset/clickhouse-clickhouse -- clickhouse-client --query "
SELECT
    toStartOfInterval(timestamp, INTERVAL 1 HOUR) as hour,
    count() as trace_count,
    sum(total_cost) as total_cost
FROM langfuse.observations
WHERE timestamp > now() - INTERVAL 24 HOUR
GROUP BY hour
ORDER BY hour DESC
"
```

## Troubleshooting

### Database Migration Failures

**Symptom**: Pods crash on startup with migration errors

```bash
# Check init-db container logs
kubectl logs -n langfuse deployment/langfuse -c init-db

# Check main container migration logs
kubectl logs -n langfuse deployment/langfuse | grep -i migration
```

**Fix**: Ensure PostgreSQL is accessible and database permissions are correct
```bash
# Verify PostgreSQL connectivity
kubectl exec -n langfuse deployment/langfuse -- nc -zv postgresql-official.postgres.svc.cluster.local 5432

# Verify database exists
kubectl exec -n postgres statefulset/postgresql-official -- psql -U admin -l | grep langfuse_db
```

### OIDC Authentication Failures

**Symptom**: Unable to login with Keycloak SSO

```bash
# Check OAuth secret
kubectl get secret -n langfuse langfuse-oauth-secret -o yaml

# Verify environment variables
kubectl exec -n langfuse deployment/langfuse -- env | grep AUTH_KEYCLOAK
```

**Fix**: Verify Keycloak client configuration
```bash
# Get Keycloak admin token
ADMIN_TOKEN=$(curl -s -X POST "https://auth.example.com/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=$ADMIN_PASSWORD" \
  -d "grant_type=password" | jq -r '.access_token')

# Check client configuration
curl -s "https://auth.example.com/admin/realms/thinkube/clients?clientId=langfuse" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq
```

### ClickHouse Connection Issues

**Symptom**: Traces appear in UI but analytics queries fail

```bash
# Check ClickHouse connectivity
kubectl exec -n langfuse deployment/langfuse -- curl -s http://clickhouse-clickhouse.clickhouse.svc.cluster.local:8123/ping

# Check ClickHouse logs
kubectl logs -n clickhouse statefulset/clickhouse-clickhouse | grep langfuse
```

**Fix**: Verify ClickHouse migration completed
```bash
# Check if Langfuse database exists in ClickHouse
kubectl exec -n clickhouse statefulset/clickhouse-clickhouse -- clickhouse-client --query "SHOW DATABASES" | grep langfuse

# Check tables
kubectl exec -n clickhouse statefulset/clickhouse-clickhouse -- clickhouse-client --query "SHOW TABLES FROM langfuse"
```

### S3 Upload Failures

**Symptom**: Event or media uploads fail

```bash
# Check S3 credentials in secret
kubectl get secret -n langfuse langfuse-config -o jsonpath='{.data.LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID}' | base64 -d

# Check SeaweedFS S3 endpoint
kubectl exec -n langfuse deployment/langfuse -- curl -s http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333
```

**Fix**: Verify buckets exist and are accessible
```bash
# List buckets via SeaweedFS
s3cmd --config=/dev/null \
  --access_key="$S3_ACCESS_KEY" \
  --secret_key="$S3_SECRET_KEY" \
  --host="https://s3.example.com" \
  --host-bucket="https://s3.example.com/%(bucket)s" \
  --no-ssl-certificate-check \
  ls
```

### High Memory Usage

**Symptom**: Pods OOMKilled or high memory consumption

```bash
# Check current memory usage
kubectl top pods -n langfuse

# Check resource limits
kubectl get deployment -n langfuse langfuse -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

**Fix**: Increase memory limits for high-volume deployments
```bash
# Edit deployment (adjust limits based on trace volume)
kubectl patch deployment -n langfuse langfuse -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "langfuse",
          "resources": {
            "limits": {
              "memory": "8Gi"
            },
            "requests": {
              "memory": "2Gi"
            }
          }
        }]
      }
    }
  }
}'
```

## Testing

Tests are defined in [18_test.yaml](18_test.yaml):

```bash
# Run test playbook
cd ~/thinkube
./scripts/run_ansible.sh ansible/40_thinkube/optional/langfuse/18_test.yaml
```

**Test Coverage**:
- Health endpoint responds 200
- Keycloak OIDC authentication flow
- PostgreSQL database connectivity
- ClickHouse database connectivity
- Valkey session cache connectivity
- S3 bucket accessibility
- API key authentication (public + secret)
- Trace ingestion via API
- Trace retrieval via UI

## Rollback

Rollback is defined in [19_rollback.yaml](19_rollback.yaml):

```bash
# Rollback Langfuse deployment
cd ~/thinkube
./scripts/run_ansible.sh ansible/40_thinkube/optional/langfuse/19_rollback.yaml
```

**Rollback Actions**:
- Deletes Langfuse deployment, service, ingress
- Removes `langfuse` namespace
- Deletes Keycloak `langfuse` client
- **Preserves** PostgreSQL `langfuse_db` database (data retention)
- **Preserves** ClickHouse `langfuse` database (data retention)
- **Preserves** SeaweedFS S3 buckets `langfuse-events`, `langfuse-media` (data retention)
- Removes service discovery ConfigMap
- Updates code-server environment to remove Langfuse variables

**Note**: Database and S3 bucket preservation allows re-deployment without data loss. Manual cleanup required if full data deletion is desired.

## References

- **Official Documentation**: https://langfuse.com/docs
- **GitHub Repository**: https://github.com/langfuse/langfuse
- **Python SDK**: https://github.com/langfuse/langfuse-python
- **LangChain Integration**: https://langfuse.com/docs/integrations/langchain
- **LlamaIndex Integration**: https://langfuse.com/docs/integrations/llama-index
- **OpenAI SDK Integration**: https://langfuse.com/docs/integrations/openai
- **API Reference**: https://langfuse.com/docs/api
- **Prompt Management**: https://langfuse.com/docs/prompts
- **Datasets & Evaluations**: https://langfuse.com/docs/datasets

🤖 [AI-assisted]
