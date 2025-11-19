# LiteLLM - Unified LLM API Proxy

## Overview

LiteLLM is a unified LLM API proxy that provides a single OpenAI-compatible interface for 100+ LLM providers including OpenAI, Anthropic, Azure OpenAI, Google (Gemini/PaLM), Cohere, Hugging Face, Bedrock, and more. It features intelligent load balancing across multiple models and providers, comprehensive cost tracking and budget management, rate limiting, API key management with team-based access control, and response caching for improved performance and cost savings.

This component deploys LiteLLM with Keycloak SSO authentication for the admin dashboard, JWT-based API authentication, PostgreSQL backend for usage tracking and team management, and SeaweedFS S3-compatible caching for optimized response delivery.

## Dependencies

This component depends on the following Thinkube components:

- **#1 - Kubernetes (k8s-snap)**: Provides the container orchestration platform
- **#2 - Ingress Controller**: Routes external traffic to LiteLLM API and dashboard
- **#4 - SSL/TLS Certificates**: Secures HTTPS connections
- **#6 - Keycloak**: Provides SSO authentication and JWT token verification
- **#14 - Harbor**: Provides the container registry for LiteLLM images
- **#22 - PostgreSQL**: Stores usage data, teams, budgets, and virtual API keys
- **#25 - SeaweedFS**: Provides S3-compatible storage for response caching

## Prerequisites

To deploy this component, ensure the following variables are configured in your Ansible inventory:

```yaml
# Domain configuration
domain_name: "example.com"
litellm_hostname: "litellm.example.com"

# Kubernetes configuration
kubeconfig: "/path/to/kubeconfig"

# Namespaces
litellm_namespace: "litellm"
postgres_namespace: "postgres"
seaweedfs_namespace: "seaweedfs"

# Keycloak configuration
keycloak_url: "https://auth.example.com"
keycloak_realm: "thinkube"
admin_username: "admin"
auth_realm_username: "admin"

# Harbor registry
harbor_registry: "harbor.example.com"
library_project: "library"

# Ingress
primary_ingress_class: "nginx"

# Environment variables
ADMIN_PASSWORD: "your-admin-password"  # Required for deployment
```

## Playbooks

### **00_install.yaml** - Main Orchestrator

Coordinates the complete LiteLLM deployment by executing all component playbooks in sequence.

**Tasks:**
1. Imports `10_configure_keycloak.yaml` to configure OIDC
2. Imports `11_deploy.yaml` to deploy LiteLLM
3. Imports `17_configure_discovery.yaml` to register service

### **10_configure_keycloak.yaml** - Keycloak OIDC Configuration

Configures Keycloak for LiteLLM dashboard SSO and API JWT authentication.

**Configuration Steps:**

**Step 1: Create LiteLLM OIDC Client**
- Client ID: `litellm`
- Protocol: openid-connect
- Standard flow enabled for dashboard login
- Direct access grants enabled for programmatic access
- Redirect URIs: `https://litellm.example.com/sso/callback`, `https://litellm.example.com/*`
- Web origins: `https://litellm.example.com`

**Step 2: Create Custom Client Scope**
- Scope name: `litellm_proxy_admin`
- Adds admin permissions for proxy management
- Added as optional scope to client

**Step 3: Create Realm Roles**
- `AI_ADMIN`: Administrator role for full LiteLLM access
- `AI_USER`: Standard user role for API usage

**Step 4: Assign Admin Role**
- Assigns `AI_ADMIN` role to admin user
- Enables full dashboard and API access for admin

**Step 5: Retrieve Client Secret**
- Gets OAuth2 client secret from Keycloak
- Stores for use in LiteLLM deployment configuration

### **11_deploy.yaml** - LiteLLM Deployment

Deploys LiteLLM with PostgreSQL database, SeaweedFS caching, and Keycloak integration.

**Configuration Steps:**

**Step 1: Namespace and Prerequisites**
- Creates `litellm` namespace
- Verifies PostgreSQL service exists in `postgres` namespace
- Verifies SeaweedFS S3 service exists in `seaweedfs` namespace

**Step 2: Generate Master Key**
- Generates random 32-character master key with prefix `sk-`
- Master key used for API authentication and encryption

**Step 3: Retrieve Keycloak Client Secret**
- Obtains Keycloak admin token
- Retrieves `litellm` client details
- Gets OAuth2 client secret for OIDC configuration

**Step 4: Create Secrets**
- Creates `litellm-secrets` Secret with:
  - `LITELLM_MASTER_KEY`: API master key
  - `LITELLM_SALT_KEY`: Encryption salt (32 chars)
  - `ADMIN_USERNAME` and `ADMIN_PASSWORD`: Dashboard credentials
  - `DATABASE_URL`: PostgreSQL connection string for `litellm` database
  - `CLIENT_SECRET`: Keycloak OAuth2 client secret
  - SeaweedFS S3 credentials: bucket name, region, endpoint, access/secret keys

**Step 5: Create Configuration**
- Creates `litellm-config` ConfigMap with:
  - Database URL from environment
  - Master key and salt key configuration
  - Proxy batch write interval: 60 seconds
  - UI access mode: "all" (allows all authenticated users)
  - Database connection pool: 10 connections
  - Allow requests on DB unavailable: true
  - S3 caching configuration:
    - Cache type: s3
    - Bucket: litellm-cache
    - Endpoint: SeaweedFS S3 service
    - Supported call types: completion, acompletion, embedding, aembedding
    - TTL: 3600 seconds (1 hour)
  - Model list placeholder (configured via UI)

**Step 6: Create Persistent Volume**
- Creates 5Gi PVC for local data storage
- Used for SQLite fallback and temporary files

**Step 7: Deploy LiteLLM**
- **Init Containers**:
  - wait-for-postgres: Waits for PostgreSQL readiness
  - wait-for-seaweedfs: Waits for SeaweedFS S3 readiness
  - init-db: Creates `litellm` database, grants privileges, transfers ownership
- **Main Container**:
  - Image from Harbor: `{harbor_registry}/library/litellm:latest`
  - Command: `litellm --port 4000 --config /app/config.yaml`
  - Exposes port 4000
  - Environment variables:
    - Master key, salt key, UI credentials from Secret
    - `STORE_MODEL_IN_DB`: True
    - `PROXY_BASE_URL`: https://litellm.example.com
    - `LITELLM_MODE`: PRODUCTION
    - Database URL from Secret
    - Keycloak OIDC configuration:
      - `GENERIC_CLIENT_ID`: litellm
      - Client secret from Secret
      - Authorization, token, userinfo endpoints
      - Scope: "openid profile email roles"
    - Admin configuration:
      - `PROXY_ADMIN_ID`: admin username
      - `LITELLM_PROXY_ADMIN_ROLE`: AI_ADMIN
      - User role attribute: realm_access.roles
      - User ID/email attributes: preferred_username, email
    - S3 caching credentials from Secret
  - Volume mounts: config.yaml, data PVC
  - Probes: liveness on `/health/liveliness`, readiness on `/health/readiness`
  - Resources: 256Mi/100m requests, 1Gi/500m limits

**Step 8: Create Service**
- ClusterIP Service `litellm` on port 80 → 4000

**Step 9: Create Ingress**
- TLS with wildcard certificate
- Annotations: 10m body size, 600s timeouts
- Routes `https://litellm.example.com` to service

**Step 10: Wait for Readiness**
- Waits for deployment ready replicas to match desired replicas
- Maximum 30 retries with 10-second delay

### **17_configure_discovery.yaml** - Service Discovery Configuration

Registers LiteLLM with Thinkube service discovery.

**Tasks:**
1. Reads component version (0.1.0)
2. Retrieves master key from Secret
3. Creates `thinkube-service-config` ConfigMap with:
   - Service metadata: name, display name, description, type (optional), category (ai)
   - Icon: `/icons/tk_ai.svg`
   - Endpoints:
     - **dashboard** (primary): `https://litellm.example.com/ui`
     - **api**: `https://litellm.example.com/v1`
   - Scaling: Deployment, min 1 replica, can disable
   - Environment variables: LITELLM_ENDPOINT, LITELLM_MASTER_KEY
4. Updates code-server environment variables

## Deployment

LiteLLM is automatically deployed via the **thinkube-control Optional Components** interface at `https://thinkube.example.com/optional-components`.

The deployment process takes 3-5 minutes and includes PostgreSQL database creation, SeaweedFS bucket configuration, Keycloak client setup, and LiteLLM proxy deployment with caching enabled.

## Access Points

After deployment, LiteLLM is accessible via:

- **Admin Dashboard**: `https://litellm.example.com/ui`
- **API Endpoint**: `https://litellm.example.com/v1`
- **Health Check**: `https://litellm.example.com/health/readiness`
- **API Documentation**: `https://litellm.example.com/docs`

### Authentication

**Dashboard Access:**
- Navigate to `https://litellm.example.com/ui`
- Click "Login with SSO" (Keycloak)
- Authenticate with Keycloak credentials
- Users with `AI_ADMIN` role have full access

**API Access:**

Using master key:
```bash
curl -X POST https://litellm.example.com/v1/chat/completions \
  -H "Authorization: Bearer YOUR_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

Using JWT token from Keycloak:
```bash
curl -X POST https://litellm.example.com/v1/chat/completions \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Configuration

### Adding LLM Providers

1. Access dashboard: `https://litellm.example.com/ui`
2. Login with Keycloak SSO
3. Navigate to "Models"
4. Click "Add Model"
5. Configure provider:
   - Model name: `gpt-3.5-turbo`
   - Provider: OpenAI
   - API key: Your OpenAI key
6. Save configuration

Supported providers include OpenAI, Anthropic, Azure OpenAI, Google (Gemini/Vertex AI), Cohere, AWS Bedrock, Hugging Face, Ollama, and 100+ more.

### Team Management

Create teams with budget limits:

1. Navigate to "Teams" in dashboard
2. Click "Create Team"
3. Set team name, budget (USD), rate limits
4. Generate team API key
5. Assign users to team

### Virtual Keys

Create virtual API keys with specific permissions:

1. Navigate to "Keys"
2. Click "Create Key"
3. Configure:
   - Key alias
   - Allowed models
   - Budget (max spend)
   - Rate limits (RPM/TPM)
   - Expiration date
4. Generate key

## Usage

### OpenAI SDK Compatibility

LiteLLM is fully compatible with OpenAI's SDK:

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://litellm.example.com/v1",
    api_key="YOUR_MASTER_KEY"
)

response = client.chat.completions.create(
    model="gpt-3.5-turbo",
    messages=[{"role": "user", "content": "Hello!"}]
)

print(response.choices[0].message.content)
```

### Load Balancing

Configure multiple deployments of the same model:

```python
# In dashboard, add multiple model deployments
# Model 1: gpt-3.5-turbo (OpenAI)
# Model 2: gpt-3.5-turbo (Azure OpenAI)
# Model 3: gpt-3.5-turbo (OpenAI backup)

# LiteLLM automatically load balances requests
response = client.chat.completions.create(
    model="gpt-3.5-turbo",
    messages=[{"role": "user", "content": "Hello!"}]
)
```

### Fallback Configuration

Set up automatic fallbacks:

```yaml
# In config.yaml (via dashboard)
model_list:
  - model_name: production-gpt4
    litellm_params:
      model: gpt-4
      api_key: os.environ/OPENAI_API_KEY
    model_info:
      mode: fallback

  - model_name: production-gpt4-fallback
    litellm_params:
      model: claude-3-sonnet
      api_key: os.environ/ANTHROPIC_API_KEY
```

### Cost Tracking

View usage and costs:

```python
# Via dashboard: Navigate to "Usage" tab
# View spending by:
# - Team
# - Model
# - User
# - Time period

# Via API
import requests

response = requests.get(
    "https://litellm.example.com/spend/tags",
    headers={"Authorization": f"Bearer {master_key}"}
)

print(response.json())
```

## Integration

### Integration with Langfuse (#43)

LiteLLM can send observability data to Langfuse:

```python
# Configure in dashboard under "Settings" → "Callbacks"
# Add Langfuse callback:
# - Public key: Your Langfuse public key
# - Secret key: Your Langfuse secret key
# - Host: https://langfuse.example.com

# All API calls will now be logged to Langfuse
```

### Integration with PostgreSQL (#22)

LiteLLM stores all data in PostgreSQL:

```bash
# Connect to litellm database
kubectl exec -n postgres postgresql-official-0 -- psql -U admin -d litellm

# View tables
\dt

# Query spend logs
SELECT * FROM "LiteLLM_SpendLogs" ORDER BY startTime DESC LIMIT 10;

# View teams
SELECT * FROM "LiteLLM_TeamTable";
```

### Integration with SeaweedFS (#25)

Response caching uses SeaweedFS S3:

```bash
# Cached responses stored in litellm-cache bucket
# Cache key format: {model}:{prompt_hash}
# TTL: 1 hour (configurable)

# Benefits:
# - Reduced API costs for repeated queries
# - Faster response times
# - Lower provider rate limit usage
```

## Monitoring

### Health Checks

```bash
# Liveness check
curl https://litellm.example.com/health/liveliness

# Readiness check
curl https://litellm.example.com/health/readiness

# Database connection check
curl https://litellm.example.com/health
```

### Kubernetes Resources

```bash
# Check pod status
kubectl get pods -n litellm

# View logs
kubectl logs -n litellm -l app=litellm --tail=100 -f

# Check resource usage
kubectl top pod -n litellm

# View PVC status
kubectl get pvc -n litellm
```

### Metrics

LiteLLM exposes Prometheus metrics:

```bash
# Access metrics endpoint (requires auth)
curl -H "Authorization: Bearer YOUR_MASTER_KEY" \
  https://litellm.example.com/metrics
```

## Troubleshooting

### Connection Issues

**Problem**: Cannot access dashboard

```bash
# Check pod status
kubectl get pods -n litellm

# Check logs
kubectl logs -n litellm deployment/litellm

# Check ingress
kubectl get ingress -n litellm
```

### Database Connection Failures

**Problem**: "Database connection failed"

```bash
# Verify PostgreSQL is running
kubectl get pods -n postgres

# Test connection from LiteLLM pod
kubectl exec -n litellm -l app=litellm -- \
  nc -zv postgresql-official.postgres.svc.cluster.local 5432

# Check database exists
kubectl exec -n postgres postgresql-official-0 -- \
  psql -U admin -d postgres -c "\l" | grep litellm
```

### Caching Issues

**Problem**: S3 caching not working

```bash
# Verify SeaweedFS is running
kubectl get pods -n seaweedfs

# Test S3 endpoint
kubectl exec -n litellm -l app=litellm -- \
  nc -zv seaweedfs-s3.seaweedfs.svc.cluster.local 8333

# Check S3 credentials in secret
kubectl get secret -n litellm litellm-secrets -o yaml
```

### Keycloak SSO Issues

**Problem**: "Failed to login with SSO"

```bash
# Verify Keycloak client exists
# (requires Keycloak admin access)

# Check client secret matches
kubectl get secret -n litellm litellm-secrets \
  -o jsonpath='{.data.CLIENT_SECRET}' | base64 -d

# View LiteLLM OIDC configuration
kubectl get deployment -n litellm litellm \
  -o jsonpath='{.spec.template.spec.containers[0].env}' | grep GENERIC
```

### Model Configuration Issues

**Problem**: "Model not found"

```bash
# Check model configuration in database
kubectl exec -n postgres postgresql-official-0 -- \
  psql -U admin -d litellm -c \
  "SELECT * FROM \"LiteLLM_ModelTable\";"

# Verify API keys are set
# Access dashboard → Models → Edit model → Check API key
```

## Testing

### Dashboard Access Test

```bash
# Test HTTPS access
curl -I https://litellm.example.com/ui

# Expected: HTTP 200 or 302
```

### API Test

```bash
# Retrieve master key
MASTER_KEY=$(kubectl get secret -n litellm litellm-secrets \
  -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d)

# Test API endpoint
curl -X POST https://litellm.example.com/v1/chat/completions \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "test-model",
    "messages": [{"role": "user", "content": "test"}]
  }'
```

### Database Test

```bash
# Verify database connection
kubectl exec -n litellm -l app=litellm -- \
  python -c "import psycopg2; conn = psycopg2.connect('$DATABASE_URL'); print('Connected')"
```

## Rollback

To remove LiteLLM:

```bash
# Delete deployment and resources
kubectl delete deployment -n litellm litellm
kubectl delete svc -n litellm litellm
kubectl delete ingress -n litellm litellm

# Delete ConfigMaps and Secrets
kubectl delete configmap -n litellm litellm-config thinkube-service-config
kubectl delete secret -n litellm litellm-secrets litellm-tls-secret

# Delete PVC (WARNING: Deletes all local data)
kubectl delete pvc -n litellm litellm-data-pvc

# Delete litellm database from PostgreSQL
kubectl exec -n postgres postgresql-official-0 -- \
  psql -U admin -d postgres -c "DROP DATABASE litellm;"

# Optional: Delete namespace
kubectl delete namespace litellm
```

## References

- [LiteLLM Documentation](https://docs.litellm.ai/)
- [LiteLLM GitHub](https://github.com/BerriAI/litellm)
- [Supported Providers](https://docs.litellm.ai/docs/providers)
- [Cost Tracking](https://docs.litellm.ai/docs/proxy/cost_tracking)
- [Load Balancing](https://docs.litellm.ai/docs/proxy/load_balancing)

---

🤖 [AI-assisted]