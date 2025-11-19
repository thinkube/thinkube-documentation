# OpenSearch

## Overview

OpenSearch is an open-source search and analytics engine used for log aggregation, full-text search, security analytics, and real-time application monitoring. Deployed with OpenSearch Dashboards for visualization, Keycloak OIDC integration for SSO, and Fluent Bit for continuous log collection from all cluster containers.

**Key Features**:
- **Search and Analytics**: Full-text search with relevance scoring and aggregations
- **OpenSearch Dashboards**: Kibana-compatible visualization and exploration interface
- **Keycloak SSO**: OIDC integration with multiple authentication methods
- **Fluent Bit Integration**: Real-time log collection from all Kubernetes pods
- **TLS Security**: HTTPS for API, inter-node encryption, certificate-based authentication
- **Index Lifecycle Management**: Automated data retention and rollover
- **Persistent Storage**: 30Gi for data retention

## Dependencies

**Core Components** (always available):
- Kubernetes (#1) - k8s-snap 1.34.0
- Keycloak (#5) - OAuth2/OIDC authentication
- Ingress (#7) - NGINX Ingress Controller
- Cert-manager (#8) - Wildcard TLS certificates

**Optional Components** (dependent on OpenSearch):
- Argilla (#46) - NLP annotation platform uses OpenSearch for data storage

## Prerequisites

```yaml
requirements:
  kubernetes:
    version: "1.34.0"
    provider: "k8s-snap"

  helm:
    repository: "https://opensearch-project.github.io/helm-charts/"
    charts:
      - "opensearch/opensearch"
      - "opensearch/opensearch-dashboards"

  authentication:
    keycloak_integration: true
    basic_auth: true
    admin_password: "ADMIN_PASSWORD environment variable"

  storage:
    opensearch_data: "30Gi"
    storage_class: "default"

  networking:
    opensearch_api: "opensearch.example.com"
    dashboards: "osd.example.com"

  fluent_bit:
    image: "fluent/fluent-bit:2.2.0"
    daemonset: true
```

## Playbooks

### **Main Deployment**
**File**: [10_deploy.yaml](10_deploy.yaml)

Comprehensive deployment with Keycloak integration and security configuration:

#### **Pre-Tasks: Password and Security**

- **Install apache2-utils Package**
  - Provides `htpasswd` command for bcrypt password hashing
  - Required for OpenSearch internal user passwords

- **Password Validation**
  - Verifies `ADMIN_PASSWORD` environment variable is set
  - Fails deployment if missing

- **Bcrypt Hash Generation**
  - Generates bcrypt hash with cost factor 12 (secure)
  - Command: `htpasswd -bnBC 12 "" '$ADMIN_PASSWORD'`
  - Hash used for OpenSearch internal `admin` user

#### **Phase 1: Keycloak Client Configuration**

- **Keycloak Client Setup** (via `keycloak/keycloak_setup` role)
  - Client ID: `opensearch`
  - Protocol: `openid-connect`
  - Standard flow enabled (authorization code)
  - Direct access grants enabled
  - Public client: false (confidential client with secret)
  - **PKCE explicitly disabled**: `oauth.pkce.required: false` (Keycloak compatibility)
  - Redirect URIs:
    - `https://osd.example.com/*`
    - `https://osd.example.com/auth/openid/login`
  - Web origins: `https://osd.example.com`

- **Client Scope Creation**
  - Scope name: `opensearch-authorization`
  - Protocol: `openid-connect`
  - Description: "Client scope for OpenSearch token claims"
  - Include in token scope: true

- **Client Mappers**
  - `preferred_username` mapper:
    - Type: `oidc-usermodel-property-mapper`
    - Maps user attribute `username` to claim `preferred_username`
    - Included in ID token and access token
  - `roles` mapper:
    - Type: `oidc-usermodel-realm-role-mapper`
    - Maps realm roles to claim `roles`
    - Multivalued: true
    - Included in ID token and access token

- **Scope Mappers**
  - Adds mappers to `opensearch-authorization` scope
  - Ensures claims appear in userinfo endpoint

- **Scope Assignment**
  - Assigns `opensearch-authorization` scope to client

- **User Role Assignment**
  - Creates realm role: `opensearch_admin`
  - Assigns role to `auth_realm_username` user
  - Enables admin access via Keycloak SSO

#### **Phase 2: Namespace Creation**

- **Creates `opensearch` namespace**

#### **Phase 3: TLS Certificate Preparation**

- **Wildcard Certificate Retrieval**
  - Gets certificate from `default` namespace
  - Secret name: `{domain_name}-tls` (dots replaced with hyphens)

- **Certificate Conversion Process**
  - Creates temporary directory: `/tmp/ssl-convert` (mode 0700)
  - Writes certificate and key to temporary files
  - **Certificate conversion**: `openssl x509 -outform PEM`
  - **Key conversion to PKCS8** (required by OpenSearch):
    - Command: `openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt`
    - **Critical**: OpenSearch requires PKCS8 format private keys
    - Verifies key header: `BEGIN PRIVATE KEY` (not `BEGIN RSA PRIVATE KEY`)
  - Reads converted files with base64 encoding

- **TLS Secret Creation**
  - Creates `opensearch-tls-secret` in `opensearch` namespace
  - Type: `kubernetes.io/tls`
  - Contains converted certificate and PKCS8 key

#### **Phase 4: Secrets Creation**

- **Admin Password Secret**
  - Name: `opensearch-admin-password`
  - Contains plain password for dashboards connection

- **Keycloak Token Retrieval**
  - Gets admin token from Keycloak master realm
  - Client: `admin-cli`
  - Grant type: `password`

- **OIDC Client Secret Retrieval**
  - Queries Keycloak API for `opensearch` client
  - Extracts client secret for OIDC configuration

#### **Phase 5: Security Configuration Secret**

**Creates `opensearch-security-config` secret with multiple security files**:

- **config.yml** - Authentication configuration:
  - Anonymous auth: disabled
  - **OIDC Auth Domain** (order 1, higher priority):
    - Type: `openid`
    - Challenge: false (no HTTP challenge)
    - OpenID Connect URL: `{keycloak_url}/realms/{realm}/.well-known/openid-configuration`
    - Client ID and secret from Keycloak
    - Subject key: `preferred_username`
    - Roles key: `roles`
    - Authentication backend: `noop` (no backend, trust OIDC)
  - **Basic Internal Auth Domain** (order 2, fallback):
    - Type: `basic`
    - Challenge: true (HTTP Basic challenge)
    - Authentication backend: `internal` (internal users file)

- **internal_users.yml** - Internal users:
  - `admin` user with bcrypt hash from pre-task
  - Reserved: true
  - Backend roles: `["admin"]`

- **roles.yml** - Role definitions:
  - `admin` role with full cluster and index permissions
  - Cluster permissions: `["*"]`
  - Index permissions: all actions on all indices
  - Tenant permissions: `kibana_all_write` on all tenants

- **roles_mapping.yml** - Backend role mapping:
  - Maps `opensearch_admin` backend role to `admin` role
  - Maps internal `admin` user to `admin` role

- **action_groups.yml** - Action group definitions:
  - `admin_all` with all actions

- **tenants.yml** - Tenant configuration:
  - `admin_tenant` reserved tenant

- **nodes_dn.yml** - Node distinguished names (empty)

- **whitelist.yml** - API whitelist (empty)

#### **Phase 6: OpenSearch Helm Deployment**

- **Helm Values Configuration** (`/tmp/opensearch-values.yaml`):
  - Cluster name: `opensearch-cluster`
  - Node group: `master`
  - Single node: true (homelab configuration)
  - Replicas: 1

  - **Security Configuration**:
    - Enabled: true
    - Config secret: `opensearch-security-config`
    - Data complete: true (skip built-in security)

  - **opensearch.yml Configuration**:
    - Network host: `0.0.0.0`
    - **HTTP SSL Configuration**:
      - Enabled: true
      - Certificate: `/usr/share/opensearch/config/certificates/tls.crt`
      - Private key: `/usr/share/opensearch/config/certificates/tls.key`
      - Trusted CAs: `/usr/share/opensearch/config/certificates/tls.crt`
    - **Transport SSL Configuration**:
      - Enabled: true (inter-node encryption)
      - Same certificates as HTTP
    - **Security Plugin Settings**:
      - Allow default init: true
      - Admin DNs: `CN=*.{domain}`, `CN={domain}`, `CN=admin.cluster.local`
      - Audit type: `internal_opensearch`
      - Snapshot restore privilege: enabled
      - REST API roles: `["all_access", "security_rest_api_access"]`

  - **Persistence**:
    - Enabled: true
    - Access mode: ReadWriteOnce
    - Size: 30Gi

  - **Extra Volumes**:
    - Mounts `opensearch-tls-secret` at `/usr/share/opensearch/config/certificates`
    - Mode: 0600 (read/write for owner only)

  - **Environment Variables**:
    - `DISABLE_INSTALL_DEMO_CONFIG`: "true"
    - `DISABLE_SECURITY_PLUGIN`: "false"
    - `OPENSEARCH_INITIAL_ADMIN_PASSWORD`: from secret
    - `OPENSEARCH_JAVA_OPTS`: "-Xms1g -Xmx1g" (1GB heap)

  - **Resources**:
    - Requests: 1 CPU, 2Gi memory
    - Limits: 2 CPU, 4Gi memory

  - **Service**: ClusterIP

- **Helm Repository Setup**:
  - Adds repository: `https://opensearch-project.github.io/helm-charts/`
  - Updates repositories

- **Helm Installation**:
  - Release name: `gato-opensearch`
  - Chart: `opensearch/opensearch`
  - Timeout: 10 minutes

#### **Phase 7: Security Initialization**

- **Wait for Pod Ready**
  - Waits for `opensearch-cluster-master-0` pod
  - Status: Running
  - Retries: 30 × 10s = 5 minutes

- **Security Admin Tool Execution**
  - Creates `/tmp/opensearch-security` directory
  - Copies `securityadmin.sh` from pod via kubectl exec
  - Copies certificates from pod
  - Makes script executable
  - **Runs securityadmin.sh inside pod**:
    - Config directory: `/usr/share/opensearch/config/opensearch-security`
    - Options: `-icl -nhnv` (ignore cluster name, no hostname verification)
    - Host: localhost, port: 9200
    - CA cert, cert, and key from `/usr/share/opensearch/config/certificates/`
    - Force flag: `-ff`
    - Environment: `JAVA_HOME=/usr/share/opensearch/jdk`
  - Retries: 3 × 10s delay
  - **Critical**: Applies security configuration from ConfigMap to cluster

- **Cleanup**: Removes `/tmp/opensearch-security`

- **Wait 30 seconds** for configuration to propagate

#### **Phase 8: Authentication Test**

- **Test Admin Login**:
  - Uses kubectl exec to curl from inside pod
  - URL: `https://localhost:9200/_plugins/_security/authinfo`
  - Credentials: `admin` with password from environment
  - Retries: 10 × 30s = 5 minutes
  - Fails if "Unauthorized" in response

#### **Phase 9: OpenSearch Ingress**

- **Creates `opensearch-ingress`**:
  - Host: `opensearch.example.com`
  - Backend protocol: HTTPS
  - SSL verify: false (self-signed cert)
  - Force SSL redirect: true
  - Timeouts: 300s (connect, send, read)
  - Proxy body size: 50m
  - Proxy buffer size: 128k
  - Backend: `opensearch-cluster-master:9200`
  - TLS: `opensearch-tls-secret`

#### **Phase 10: OpenSearch Dashboards OIDC Secret**

- **Creates `opensearch-dashboards-oidc` secret**:
  - Contains `OIDC_CLIENT_SECRET` from Keycloak

#### **Phase 11: Dashboards Helm Deployment**

- **Helm Values Configuration** (`/tmp/osd-values.yaml`):
  - **opensearch_dashboards.yml Configuration**:
    - Server name: `opensearch-dashboards`
    - Server host: `0.0.0.0`
    - OpenSearch hosts: `["https://opensearch-cluster-master:9200"]`
    - SSL verification mode: none
    - Request timeout: 120000ms
    - CA certificate: `/usr/share/opensearch-dashboards/config/certificates/tls.crt`
    - **Basic Auth Configuration**:
      - Username: `admin`
      - Password: `${OPENSEARCH_DASHBOARDS_PASSWORD}` (from env)
      - Request headers allowlist: `["authorization", "securitytenant"]`
    - **Multiple Auth Configuration**:
      - Auth types: `["basicauth", "openid"]`
      - Multiple auth enabled: true
    - **OIDC Configuration**:
      - Connect URL: `{keycloak_url}/realms/{realm}/.well-known/openid-configuration`
      - Client ID: `opensearch`
      - Client secret: `${OIDC_CLIENT_SECRET}` (from env)
      - Base redirect URL: `https://osd.example.com`
      - Verify hostnames: false
      - Cookie secure: true
      - Cookie password: same as client secret
      - Scope: `openid profile email roles`
      - Anonymous auth: false
    - **Logging**:
      - Verbose: true
      - Log queries: true

  - **Extra Environment Variables**:
    - `OPENSEARCH_DASHBOARDS_PASSWORD`: from `opensearch-admin-password` secret
    - `OIDC_CLIENT_SECRET`: from `opensearch-dashboards-oidc` secret

  - **Extra Volumes**: Mounts `opensearch-tls-secret` at `/usr/share/opensearch-dashboards/config/certificates`

  - **Service**: ClusterIP

- **Helm Installation**:
  - Release name: `gato-opensearch-dashboards`
  - Chart: `opensearch/opensearch-dashboards`

#### **Phase 12: Dashboards Ingress**

- **Creates `osd-ingress`**:
  - Host: `osd.example.com`
  - Proxy buffer size: 128k
  - Proxy buffers: 4 × 256k
  - Proxy busy buffers: 256k
  - Rewrite target: `/`
  - Proxy body size: 50m
  - SSL redirect: true
  - Backend: `gato-opensearch-dashboards:5601`
  - TLS: `opensearch-tls-secret`

#### **Phase 13: Code-Server CLI Configuration**

- **Generates OpenSearch Config**:
  - Template: [templates/opensearch-config.yaml.j2](templates/opensearch-config.yaml.j2)
  - Writes to `/tmp/opensearch-config.yaml` (mode 0600)

- **Copies Config to Code-Server**:
  - Gets code-server pod name
  - Creates directory: `/home/thinkube/.opensearch/`
  - Copies config: `/home/thinkube/.opensearch/config.yaml`
  - Sets permissions: 600

#### **Phase 14: Cleanup**

- **Removes Temporary Files**:
  - `/tmp/opensearch-values.yaml`
  - `/tmp/osd-values.yaml`
  - `/tmp/opensearch-security`
  - `/tmp/ssl-convert`

### **Fluent Bit Deployment**
**File**: [16_deploy_fluent_bit.yaml](16_deploy_fluent_bit.yaml)

Deploys continuous log collection from all cluster containers:

- **ConfigMap Creation** (`fluent-bit-config`):
  - **SERVICE Configuration**:
    - Daemon: Off (run in foreground)
    - Flush: 5 seconds
    - Log level: info
    - HTTP server: enabled on port 2020 (health checks)
    - Health check: enabled

  - **INPUT Configuration** (tail):
    - Path: `/var/log/containers/*.log`
    - Multiline parser: docker, cri
    - Tag: `kube.*`
    - Memory buffer limit: 5MB
    - Skip long lines: On
    - Refresh interval: 10s

  - **FILTER Configuration** (kubernetes):
    - Match: `kube.*`
    - Kube URL: `https://kubernetes.default.svc:443`
    - CA file: `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`
    - Token file: `/var/run/secrets/kubernetes.io/serviceaccount/token`
    - Tag prefix: `kube.var.log.containers.`
    - Merge log: On (parse JSON logs)
    - K8S-Logging.Parser: On
    - K8S-Logging.Exclude: Off
    - Annotations: Off

  - **FILTER Configuration** (nest):
    - Match: `kube.*`
    - Operation: lift
    - Nested under: `kubernetes`
    - Add prefix: `k8s_`
    - **Purpose**: Flattens kubernetes metadata to top level with prefix

  - **OUTPUT Configuration** (opensearch):
    - Match: `kube.*`
    - Host: `opensearch-cluster-master.opensearch.svc.cluster.local`
    - Port: 9200
    - HTTP user: `admin`
    - HTTP password: from `ADMIN_PASSWORD`
    - TLS: On
    - TLS verify: Off (self-signed cert)
    - Suppress type name: On (OpenSearch 2.x compatibility)
    - Logstash format: On (creates time-based indices)
    - Logstash prefix: `fluent-bit-kube`
    - Logstash date format: `%Y.%m.%d` (daily indices)
    - Time key: `@timestamp`
    - Retry limit: 5
    - Buffer size: 5M

  - **Custom Parsers**:
    - `docker_no_time`: JSON parser without time field
    - `syslog`: Regex parser for syslog format

- **RBAC Configuration**:
  - Creates ServiceAccount: `fluent-bit`
  - Creates ClusterRole: `fluent-bit-read` with permissions:
    - Get, list, watch: namespaces, pods, nodes
  - Creates ClusterRoleBinding

- **DaemonSet Deployment**:
  - Name: `fluent-bit`
  - Image: `fluent/fluent-bit:2.2.0`
  - **Tolerations**: Runs on control-plane and master nodes
  - **Resources**:
    - Limits: 200Mi memory
    - Requests: 100m CPU, 200Mi memory
  - **Volume Mounts**:
    - `/var/log` (host path for container logs)
    - `/var/lib/docker/containers` (read-only, Docker container logs)
    - `/fluent-bit/etc/` (ConfigMap for configuration)
    - `/run/log/journal` (read-only, systemd journal)
  - **Port**: 2020 (HTTP server for health checks)

- **Wait for Pods Ready**:
  - Waits for all Fluent Bit pods to be Running
  - Retries: 30 × 10s

- **Index Template Creation**:
  - Creates `fluent-bit-kube` index template
  - Index pattern: `fluent-bit-kube-*`
  - Settings:
    - Shards: 1
    - Replicas: 0 (single node)
    - Refresh interval: 5s
  - Mappings:
    - `@timestamp`: date
    - `service`, `namespace`, `pod`, `container`, `host`, `stream`: keyword
    - `log`: text
    - `labels`: object

- **Verification**:
  - Waits 30 seconds for initial logs
  - Checks if indices created: `_cat/indices/fluent-bit-kube-*`
  - Gets document count: `_count`

- **Deployment Summary**:
  - Displays number of Fluent Bit pods
  - Shows index information
  - Shows document count
  - Instructions for viewing logs in Dashboards

### **Service Discovery**
**File**: [17_configure_discovery.yaml](17_configure_discovery.yaml)

Registers OpenSearch with Thinkube service discovery system:

- **ConfigMap Creation** (`thinkube-service-config` in `opensearch` namespace)
  - Service type: `optional`
  - Category: `storage`
  - Icon: `/icons/tk_search.svg`
  - Component version: `0.1.0` (from VERSION file)

- **Endpoints Registered**:
  - Primary: Dashboards web UI at `https://osd.example.com/auth/openid/captureUrlFragment` (health: `/api/status`)

- **Scaling Configuration**:
  - Resource type: StatefulSet `opensearch-cluster-master`
  - Min replicas: 1
  - Can disable: true

- **Environment Variables**:
  - `OPENSEARCH_URL`: `https://opensearch.example.com`
  - `OPENSEARCH_HOST`: `opensearch.example.com`
  - `OPENSEARCH_PORT`: `443`
  - `OPENSEARCH_USER`: `admin`
  - `OPENSEARCH_PASSWORD`: from `ADMIN_PASSWORD`
  - `OPENSEARCH_DASHBOARDS_URL`: `https://osd.example.com`

- **Code-Server Integration**:
  - Updates code-server environment variables via `code_server_env_update` role

## Deployment

This component is automatically deployed via the **thinkube-control Optional Components interface**:

1. Navigate to https://thinkube.example.com/optional-components
2. Locate the **OpenSearch** card in the **Data** section
3. Click **Install** to deploy the component
4. Monitor real-time deployment progress via WebSocket streaming
5. Verify deployment status in the dashboard

The deployment executes the orchestrator playbook at `/ansible/40_thinkube/optional/opensearch/00_install.yaml`.

**Deployment Sequence**:
1. Generate bcrypt password hash
2. Configure Keycloak client with OIDC
3. Create namespace
4. Convert TLS certificates to PKCS8 format
5. Create security configuration secret
6. Deploy OpenSearch via Helm
7. Initialize security with securityadmin.sh
8. Test authentication
9. Create ingress for API access
10. Deploy OpenSearch Dashboards with OIDC
11. Create ingress for dashboard access
12. Deploy Fluent Bit DaemonSet for log collection
13. Create index template for logs
14. Register with service discovery

**Important**: Set `ADMIN_PASSWORD` environment variable before deployment.

## Access Points

### OpenSearch Dashboards (Web UI)

Primary access:
```
https://osd.example.com
```

Login options:
1. **Basic Authentication**: Username `admin`, password from `ADMIN_PASSWORD`
2. **Keycloak SSO**: Click "Login via Keycloak" button

### OpenSearch API

```
https://opensearch.example.com
```

Basic auth example:
```bash
curl -u admin:$ADMIN_PASSWORD https://opensearch.example.com/_cluster/health
```

### Internal Cluster Access

From within cluster:
```
https://opensearch-cluster-master.opensearch.svc.cluster.local:9200
```

## Configuration

### Authentication Methods

OpenSearch supports two authentication methods simultaneously:

1. **OIDC via Keycloak** (priority 1):
   - Subject key: `preferred_username`
   - Roles key: `roles`
   - Backend role `opensearch_admin` maps to `admin` role

2. **Basic Authentication** (priority 2, fallback):
   - Internal user: `admin` with bcrypt password
   - Backend role: `admin`

### User Management

Create additional internal users via Security Plugin:

1. Navigate to https://osd.example.com
2. Go to Security → Internal Users
3. Click "Create internal user"
4. Assign backend roles

Or via API:
```bash
curl -u admin:$ADMIN_PASSWORD -X PUT "https://opensearch.example.com/_plugins/_security/api/internalusers/newuser" \
  -H 'Content-Type: application/json' \
  -d '{
    "password": "SecurePassword123!",
    "backend_roles": ["opensearch_admin"]
  }'
```

### Index Management

Create index:
```bash
curl -u admin:$ADMIN_PASSWORD -X PUT "https://opensearch.example.com/my-index"
```

Create index with mapping:
```bash
curl -u admin:$ADMIN_PASSWORD -X PUT "https://opensearch.example.com/my-index" \
  -H 'Content-Type: application/json' \
  -d '{
    "mappings": {
      "properties": {
        "timestamp": { "type": "date" },
        "message": { "type": "text" },
        "level": { "type": "keyword" }
      }
    }
  }'
```

### Index Patterns in Dashboards

Create index pattern for Fluent Bit logs:

1. Navigate to https://osd.example.com
2. Go to Management → Stack Management → Index Patterns
3. Create index pattern: `fluent-bit-kube-*`
4. Select time field: `@timestamp`
5. Click "Create index pattern"
6. Go to Discover to view logs

### Storage Configuration

Default: 30Gi persistent volume

To increase:
```bash
helm upgrade gato-opensearch opensearch/opensearch \
  -n opensearch \
  --reuse-values \
  --set persistence.size=50Gi
```

**Note**: May require PVC expansion or recreation.

## Usage

### Search API

Simple search:
```bash
curl -u admin:$ADMIN_PASSWORD "https://opensearch.example.com/fluent-bit-kube-*/_search?q=error"
```

Query DSL:
```bash
curl -u admin:$ADMIN_PASSWORD -X POST "https://opensearch.example.com/fluent-bit-kube-*/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "match": {
        "log": "error"
      }
    },
    "size": 10,
    "sort": [{ "@timestamp": "desc" }]
  }'
```

### Python Client

```python
from opensearchpy import OpenSearch

client = OpenSearch(
    hosts = [{'host': 'opensearch.example.com', 'port': 443}],
    http_auth = ('admin', 'password'),
    use_ssl = True,
    verify_certs = True,
    ssl_show_warn = False
)

# Search
response = client.search(
    index="fluent-bit-kube-*",
    body={
        "query": {
            "match": {
                "log": "error"
            }
        }
    }
)

# Index document
client.index(
    index="my-index",
    body={
        "timestamp": "2025-01-18T12:00:00Z",
        "message": "Application started",
        "level": "info"
    }
)
```

### Viewing Logs in Dashboards

1. Navigate to https://osd.example.com
2. Login (basic auth or Keycloak SSO)
3. Create index pattern: `fluent-bit-kube-*` with time field `@timestamp`
4. Go to **Discover**
5. View real-time logs from all containers
6. Filter by namespace, pod, container, etc.
7. Create visualizations and dashboards

### Aggregations

Count logs by namespace:
```bash
curl -u admin:$ADMIN_PASSWORD -X POST "https://opensearch.example.com/fluent-bit-kube-*/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_namespace": {
        "terms": {
          "field": "k8s_namespace_name.keyword",
          "size": 20
        }
      }
    }
  }'
```

## Integration

### Argilla NLP Annotation

Argilla uses OpenSearch for annotation data storage:

- **Indices**: `rg.{workspace}.{dataset_name}`
- **Purpose**: Store annotations, records, suggestions
- **Access**: Internal cluster endpoint

### Custom Application Integration

From JupyterHub notebooks:

```python
!pip install opensearch-py

from opensearchpy import OpenSearch

client = OpenSearch(
    hosts = [{'host': 'opensearch-cluster-master.opensearch.svc.cluster.local', 'port': 9200}],
    http_auth = ('admin', 'password'),
    use_ssl = True,
    verify_certs = False
)

# Analyze logs
response = client.search(
    index="fluent-bit-kube-*",
    body={
        "size": 0,
        "aggs": {
            "errors_by_pod": {
                "filter": {
                    "match": {
                        "log": "error"
                    }
                },
                "aggs": {
                    "pods": {
                        "terms": {
                            "field": "k8s_pod_name.keyword"
                        }
                    }
                }
            }
        }
    }
)

print(response['aggregations'])
```

## Monitoring

### Cluster Health

```bash
curl -u admin:$ADMIN_PASSWORD "https://opensearch.example.com/_cluster/health?pretty"
```

### Node Stats

```bash
curl -u admin:$ADMIN_PASSWORD "https://opensearch.example.com/_nodes/stats?pretty"
```

### Index Stats

```bash
curl -u admin:$ADMIN_PASSWORD "https://opensearch.example.com/_cat/indices?v"
```

### Fluent Bit Health

Check DaemonSet:
```bash
kubectl get daemonset fluent-bit -n opensearch
```

Check logs:
```bash
kubectl logs -n opensearch -l k8s-app=fluent-bit -f
```

Check health endpoint:
```bash
kubectl exec -n opensearch <fluent-bit-pod> -- curl http://localhost:2020/api/v1/health
```

## Troubleshooting

### Verify Deployment Status

Check pods:
```bash
kubectl get pods -n opensearch
```

Should show:
- `opensearch-cluster-master-0` (Running)
- `gato-opensearch-dashboards-...` (Running)
- `fluent-bit-...` (Running on each node)

### Check Logs

OpenSearch:
```bash
kubectl logs -n opensearch opensearch-cluster-master-0 -f
```

Dashboards:
```bash
kubectl logs -n opensearch -l app.kubernetes.io/name=opensearch-dashboards -f
```

Fluent Bit:
```bash
kubectl logs -n opensearch -l k8s-app=fluent-bit -f
```

### Authentication Issues

Test admin login:
```bash
kubectl exec -n opensearch opensearch-cluster-master-0 -- \
  curl -ks -u admin:'$ADMIN_PASSWORD' https://localhost:9200/_plugins/_security/authinfo
```

Should return user info, not "Unauthorized".

### Keycloak SSO Issues

Verify client secret:
```bash
kubectl get secret opensearch-dashboards-oidc -n opensearch -o jsonpath='{.data.OIDC_CLIENT_SECRET}' | base64 -d
```

Check redirect URIs in Keycloak match:
- `https://osd.example.com/*`
- `https://osd.example.com/auth/openid/login`

### Security Plugin Issues

Re-run securityadmin:
```bash
kubectl exec -n opensearch opensearch-cluster-master-0 -- bash -c '
cd /usr/share/opensearch/plugins/opensearch-security/tools
export JAVA_HOME=/usr/share/opensearch/jdk
./securityadmin.sh \
  -cd /usr/share/opensearch/config/opensearch-security \
  -icl -nhnv -h localhost -p 9200 \
  -cacert /usr/share/opensearch/config/certificates/tls.crt \
  -cert /usr/share/opensearch/config/certificates/tls.crt \
  -key /usr/share/opensearch/config/certificates/tls.key
'
```

### Fluent Bit Not Shipping Logs

Check indices:
```bash
curl -u admin:$ADMIN_PASSWORD "https://opensearch.example.com/_cat/indices/fluent-bit-kube-*?v"
```

If no indices, check Fluent Bit logs for errors:
```bash
kubectl logs -n opensearch -l k8s-app=fluent-bit --tail=100
```

Common issues:
- Authentication failure: Check `ADMIN_PASSWORD` in ConfigMap
- Connection refused: Check OpenSearch is running
- TLS errors: `TLS.Verify Off` should be set

### Storage Full

Check disk usage:
```bash
curl -u admin:$ADMIN_PASSWORD "https://opensearch.example.com/_cat/allocation?v"
```

Delete old indices:
```bash
curl -u admin:$ADMIN_PASSWORD -X DELETE "https://opensearch.example.com/fluent-bit-kube-2025.01.01"
```

Or implement Index State Management (ISM) policy for automatic deletion.

### Common Issues

**Issue**: Cannot access dashboards
- **Solution**: Check ingress, verify DNS points to ingress IP

**Issue**: "Unauthorized" errors
- **Solution**: Verify `ADMIN_PASSWORD`, check security configuration applied

**Issue**: OIDC login fails
- **Solution**: Check client secret matches Keycloak, verify redirect URIs

**Issue**: Fluent Bit pods CrashLoopBackOff
- **Solution**: Check ConfigMap syntax, verify OpenSearch is accessible

**Issue**: High memory usage
- **Solution**: Reduce JVM heap (`OPENSEARCH_JAVA_OPTS`), limit index replicas to 0

## Testing

The test playbook [18_test.yaml](18_test.yaml) verifies:
- OpenSearch pod is running
- Authentication works (basic auth and OIDC)
- API responds correctly
- Dashboards accessible
- Keycloak integration functional
- Fluent Bit collecting logs
- Indices being created

## Rollback

To uninstall OpenSearch:

```bash
cd ~/thinkube
./scripts/tk_ansible ansible/40_thinkube/optional/opensearch/19_rollback.yaml
```

**Warning**: This will delete all indexed data including logs collected by Fluent Bit. Backup important indices before uninstalling.

### Backup Indices

Export indices:
```bash
# Snapshot to filesystem
curl -u admin:$ADMIN_PASSWORD -X PUT "https://opensearch.example.com/_snapshot/my_backup" \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "fs",
    "settings": {
      "location": "/mnt/snapshots"
    }
  }'

# Create snapshot
curl -u admin:$ADMIN_PASSWORD -X PUT "https://opensearch.example.com/_snapshot/my_backup/snapshot_1?wait_for_completion=true"
```

## Security Considerations

**Current Configuration**:
- TLS enabled for HTTP and transport
- PKCS8 private key format required
- Bcrypt password hashing (cost factor 12)
- OIDC integration with Keycloak
- Basic auth as fallback
- PKCE explicitly disabled for Keycloak compatibility

**For Production**:
1. Enable certificate verification (`TLS.Verify On` in Fluent Bit)
2. Use properly signed certificates (not self-signed)
3. Implement role-based access control (RBAC) with fine-grained permissions
4. Enable audit logging
5. Use field-level and document-level security
6. Implement Index State Management for data retention
7. Rotate passwords regularly
8. Enable PKCE for OIDC if supported by all clients

## Performance Considerations

- **Single Node**: Suitable for homelab, not production
- **JVM Heap**: 1GB (adjust based on available memory)
- **Shards**: Use 1 shard for small indices (<50GB)
- **Refresh Interval**: 5s default (increase for write-heavy workloads)
- **Fluent Bit Buffer**: 5MB (increase if log bursts cause backpressure)
- **Index Lifecycle**: Implement ISM policies for automatic rollover and deletion

## References

- [OpenSearch Official Documentation](https://opensearch.org/docs/)
- [OpenSearch Dashboards Guide](https://opensearch.org/docs/latest/dashboards/)
- [Security Plugin Documentation](https://opensearch.org/docs/latest/security-plugin/)
- [Fluent Bit Documentation](https://docs.fluentbit.io/)
- [OpenSearch Helm Charts](https://github.com/opensearch-project/helm-charts)

🤖 [AI-assisted]
