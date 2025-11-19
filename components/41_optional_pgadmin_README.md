# pgAdmin - PostgreSQL Administration Tool

## Overview

pgAdmin is a feature-rich, open-source administration and development platform for PostgreSQL databases. It provides a comprehensive web-based interface for database management, query development, data visualization, and server monitoring. This deployment integrates pgAdmin with Keycloak for single sign-on authentication and automatically configures connections to Thinkube PostgreSQL instances.

This component deploys pgAdmin with Keycloak OIDC authentication, automatic server discovery, and preconfigured database connections for seamless PostgreSQL administration within the Thinkube platform.

## Dependencies

This component depends on the following Thinkube components:

- **#1 - Kubernetes (k8s-snap)**: Provides the container orchestration platform
- **#2 - Ingress Controller**: Routes external traffic to pgAdmin web interface
- **#4 - SSL/TLS Certificates**: Secures HTTPS connections
- **#6 - Keycloak**: Provides SSO authentication for pgAdmin
- **#14 - Harbor**: Provides the container registry for pgAdmin images
- **#22 - PostgreSQL**: Target database for management (optional but recommended)

## Prerequisites

To deploy this component, ensure the following variables are configured in your Ansible inventory:

```yaml
# Domain configuration
domain_name: "example.com"
pgadmin_hostname: "pgadmin.example.com"

# Kubernetes configuration
kubeconfig: "/path/to/kubeconfig"
kubectl_bin: "/snap/bin/kubectl"

# Namespaces
pgadmin_namespace: "pgadmin"
postgres_namespace: "postgres"

# Keycloak configuration
keycloak_url: "https://keycloak.example.com"
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

Coordinates the complete pgAdmin deployment by executing all component playbooks in the correct sequence.

**Tasks:**
1. Imports `10_configure_keycloak.yaml` to create OIDC client
2. Imports `11_deploy_with_oidc.yaml` to deploy pgAdmin with Keycloak integration
3. Imports `17_configure_discovery.yaml` to register service endpoints

### **10_configure_keycloak.yaml** - Keycloak OIDC Client Configuration

Configures Keycloak authentication for pgAdmin with custom protocol mappers.

**Configuration Steps:**

**Step 1: Retrieve Admin Credentials**
- Gets ADMIN_PASSWORD from environment variable
- Sets Keycloak connection parameters
- Disables certificate validation for self-signed certificates

**Step 2: Create pgAdmin Keycloak Client**
- Creates OIDC client with client ID `pgadmin`
- Enables standard OpenID Connect authorization code flow
- Disables direct access grants (no resource owner password credentials)
- Configures as confidential client (requires client secret)
- Sets redirect URI: `https://pgadmin.example.com/oauth2/authorize`
- Configures web origins: `https://pgadmin.example.com`
- Uses `keycloak/keycloak_client` role for client creation

**Step 3: Configure Email-as-Username Mapper**
- Creates custom protocol mapper: `email-as-preferred-username`
- Maps user's email attribute to `preferred_username` claim
- Includes claim in ID token, access token, and userinfo endpoint
- Ensures pgAdmin receives email as the username (required by pgAdmin OIDC)
- Uses `keycloak/keycloak_mapper` role for mapper creation

**Step 4: Display Configuration Summary**
- Shows Keycloak realm name
- Displays client ID and UUID
- Lists redirect URIs
- Shows client secret (for verification)

### **11_deploy_with_oidc.yaml** - pgAdmin OIDC Deployment

Deploys pgAdmin with full Keycloak OIDC integration and automatic PostgreSQL server configuration.

**Configuration Steps:**

**Step 1: Namespace Creation**
- Creates `pgadmin` namespace if it doesn't exist
- Uses kubectl command for idempotent namespace creation

**Step 2: TLS Certificate Setup**
- Retrieves wildcard TLS certificate from `default` namespace
- Copies certificate to `pgadmin` namespace as `pgadmin-tls-secret`
- Enables HTTPS access via Ingress

**Step 3: PostgreSQL Server Auto-Discovery**
- Checks if PostgreSQL StatefulSet `postgresql-official` exists in `postgres` namespace
- Extracts PostgreSQL password from StatefulSet environment variables
- Creates servers configuration with connection details:
  - Name: "Thinkube PostgreSQL"
  - Host: `postgresql-official.postgres.svc.cluster.local`
  - Port: 5432
  - Database: mydatabase
  - Username: admin (from inventory)
  - SSL Mode: prefer
  - Save Password: enabled
  - Shared: enabled (visible to all users)
- Creates `pgadmin-servers` ConfigMap with `servers.json` configuration
- ConfigMap is optional (deployment succeeds even if PostgreSQL not present)

**Step 4: Retrieve Keycloak Client Secret**
- Obtains Keycloak admin token from master realm
- Queries Keycloak API for `pgadmin` client by clientId
- Retrieves client UUID
- Gets client secret via Keycloak admin API
- Stores secret as Ansible fact for configuration

**Step 5: Create OAuth2 Configuration**
- Applies `oauth2-config.yaml.j2` template to create `pgadmin-oauth-config` ConfigMap
- Configures pgAdmin OIDC settings:
  - Authentication source: OAUTH2
  - OIDC provider: Keycloak
  - Server metadata URL: `https://keycloak.example.com/realms/thinkube/.well-known/openid-configuration`
  - Client ID: pgadmin
  - Client secret: (from Keycloak)
  - Auto-create users: enabled
  - Button text: "Keycloak Login"

**Step 6: Create Init Script**
- Applies `init-script.yaml.j2` template to create `pgadmin-init-script` ConfigMap
- Python script processes OAuth2 configuration
- Converts YAML config to pgAdmin's `config_local.py` Python format
- Executed by init container before pgAdmin starts

**Step 7: Create Proxy Headers ConfigMap**
- Creates `pgadmin-proxy-headers` ConfigMap
- Sets `X-Forwarded-Proto: http` to prevent redirect loops
- NGINX Ingress terminates TLS, backend sees HTTP traffic

**Step 8: Deploy pgAdmin Application**
- Creates Deployment with 1 replica
- **Init Container** (init-config):
  - Image: `python:3.12-slim`
  - Executes init script to generate `config_local.py`
  - Mounts oauth-config, init-script, and pgadmin-config volumes
- **Main Container** (pgadmin):
  - Image from Harbor: `{harbor_registry}/library/pgadmin4:latest`
  - Environment variables:
    - `PGADMIN_DEFAULT_EMAIL`: `admin@example.com` (fallback, OIDC preferred)
    - `PGADMIN_DEFAULT_PASSWORD`: From ADMIN_PASSWORD (fallback)
    - `GUNICORN_TIMEOUT`: 120 seconds
    - `PGADMIN_CONFIG_SERVER_MODE`: True
    - `PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED`: False
    - `PGADMIN_CONFIG_ENHANCED_COOKIE_PROTECTION`: False
    - `PGADMIN_CONFIG_COOKIE_SAMESITE`: 'Lax'
    - `PGADMIN_CONFIG_PREFERRED_URL_SCHEME`: 'http' (Ingress handles HTTPS)
    - `PGADMIN_CONFIG_SECURITY_HTTPS_ONLY`: False
    - `PGADMIN_CONFIG_SECURITY_REDIRECT_HTTPS`: False
    - `PGADMIN_SERVER_JSON_FILE`: /pgadmin4/servers.json
    - `PGADMIN_REPLACE_SERVERS_ON_STARTUP`: True
  - Volume mounts:
    - servers.json (from pgadmin-servers ConfigMap, optional)
    - config_local.py (from pgadmin-config emptyDir, generated by init container)
    - /var/lib/pgadmin (emptyDir for runtime data)
  - Exposes port 80 (HTTP)

**Step 9: Create Service**
- Creates ClusterIP Service `pgadmin`
- Routes traffic to pgAdmin pods on port 80

**Step 10: Create Ingress**
- Creates Ingress for HTTPS access
- Annotations:
  - `ssl-redirect: false` and `force-ssl-redirect: false` (prevent loops)
  - `proxy-body-size: 128m` (support large query results)
  - `backend-protocol: HTTP`
  - `proxy-set-headers: pgadmin-proxy-headers` (sets X-Forwarded-Proto)
- TLS termination with pgadmin-tls-secret
- Routes all traffic from `https://pgadmin.example.com` to pgadmin Service

**Step 11: Wait for Pod Readiness**
- Polls for pgAdmin pod to reach Running state
- Maximum 30 attempts with 2-second delay
- Displays pod status

**Step 12: Deployment Summary**
- Shows access URL
- Explains OIDC authentication flow
- Notes that native authentication is disabled in favor of Keycloak

### **17_configure_discovery.yaml** - Service Discovery Configuration

Registers pgAdmin endpoints and metadata with the Thinkube service discovery system for integration with the control plane.

**Tasks:**
1. Reads component version from `VERSION` file (0.1.0)
2. Creates `thinkube-service-config` ConfigMap with:
   - Service metadata: name, display name, description, type (optional), category (development)
   - Component version: 0.1.0
   - Icon: `/icons/tk_dashboard.svg`
   - Endpoint: Web interface at `https://pgadmin.example.com` with health check at `/misc/ping`
   - Dependency: postgresql
   - Scaling configuration: Deployment `pgadmin` in `pgadmin` namespace, min 1 replica, can be disabled
3. Updates code-server environment variables via `code_server_env_update` role
4. Displays service registration summary

## Deployment

pgAdmin is automatically deployed via the **thinkube-control Optional Components** interface at `https://thinkube.example.com/optional-components`.

To deploy manually:

```bash
cd ~/thinkube
export ADMIN_PASSWORD='your-admin-password'
./scripts/run_ansible.sh ansible/40_thinkube/optional/pgadmin/00_install.yaml
```

The deployment process typically takes 2-3 minutes and includes:
1. Keycloak OIDC client configuration with email-as-username mapper
2. PostgreSQL server auto-discovery (if deployed)
3. OAuth2 configuration generation
4. pgAdmin deployment with init container for config processing
5. Service and Ingress creation with proxy headers
6. Service discovery registration with the Thinkube control plane

## Access Points

After deployment, pgAdmin is accessible via:

- **Web Interface**: `https://pgadmin.example.com`
- **Health Check**: `https://pgadmin.example.com/misc/ping`

### Authentication

pgAdmin uses Keycloak SSO for authentication:

**OIDC Login (Primary):**
1. Navigate to `https://pgadmin.example.com`
2. Click "Keycloak Login" button
3. Authenticate with Keycloak credentials
4. User account is automatically created in pgAdmin on first login
5. Email from Keycloak becomes the pgAdmin username

**Fallback Authentication:**
- Email: `admin@example.com`
- Password: Value of ADMIN_PASSWORD environment variable
- Only used when OIDC is unavailable

## Configuration

### OIDC Configuration

pgAdmin OIDC settings are configured via ConfigMap and processed by init container:

```python
# Generated config_local.py
AUTHENTICATION_SOURCES = ['oauth2']
OAUTH2_AUTO_CREATE_USER = True
OAUTH2_CONFIG = [{
    'OAUTH2_NAME': 'keycloak',
    'OAUTH2_DISPLAY_NAME': 'Keycloak Login',
    'OAUTH2_CLIENT_ID': 'pgadmin',
    'OAUTH2_CLIENT_SECRET': '<client-secret>',
    'OAUTH2_SERVER_METADATA_URL': 'https://keycloak.example.com/realms/thinkube/.well-known/openid-configuration',
    'OAUTH2_USERINFO_ENDPOINT': 'https://keycloak.example.com/realms/thinkube/protocol/openid-connect/userinfo',
    'OAUTH2_API_BASE_URL': 'https://keycloak.example.com/realms/thinkube',
    'OAUTH2_TOKEN_URL': 'https://keycloak.example.com/realms/thinkube/protocol/openid-connect/token',
    'OAUTH2_AUTHORIZATION_URL': 'https://keycloak.example.com/realms/thinkube/protocol/openid-connect/auth',
    'OAUTH2_SCOPE': 'email profile',
    'OAUTH2_USERNAME_CLAIM': 'preferred_username'
}]
```

### PostgreSQL Server Configuration

When PostgreSQL (#22) is deployed, pgAdmin automatically configures the server connection:

```json
{
  "Servers": {
    "1": {
      "Name": "Thinkube PostgreSQL",
      "Group": "Servers",
      "Host": "postgresql-official.postgres.svc.cluster.local",
      "Port": 5432,
      "MaintenanceDB": "mydatabase",
      "Username": "admin",
      "Password": "<postgres-password>",
      "SSLMode": "prefer",
      "SavePassword": true,
      "Shared": true,
      "Comment": "Default Thinkube PostgreSQL instance"
    }
  }
}
```

### Container Configuration

pgAdmin deployment uses init container pattern:

```yaml
initContainers:
  - name: init-config
    image: python:3.12-slim
    command: ["python", "/scripts/init.py"]
    # Generates config_local.py from oauth2-config

containers:
  - name: pgadmin
    image: harbor.example.com/library/pgadmin4:latest
    env:
      - name: PGADMIN_CONFIG_SERVER_MODE
        value: "True"
      # ... additional config overrides
```

## Usage

### Accessing Databases

**If PostgreSQL is Configured:**

1. **Login**: Use Keycloak SSO
2. **Browse Servers**: Expand "Servers" → "Thinkube PostgreSQL" in left sidebar
3. **Connect**: Connection is automatic (credentials pre-configured)
4. **Query**: Right-click database → "Query Tool"

**Adding Custom Servers:**

1. Right-click "Servers" → "Register" → "Server..."
2. **General Tab**:
   - Name: My Database
   - Server Group: Servers
3. **Connection Tab**:
   - Host: database.example.com
   - Port: 5432
   - Maintenance Database: postgres
   - Username: dbuser
   - Password: dbpassword
4. **SSL Tab** (if needed):
   - SSL Mode: Require or Verify-Full
5. **Save**

### Query Editor

**Execute Queries:**

```sql
-- Simple query
SELECT * FROM users LIMIT 10;

-- Complex query with JOIN
SELECT u.username, o.order_id, o.total
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE o.created_at > NOW() - INTERVAL '7 days'
ORDER BY o.created_at DESC;
```

**Export Results:**
1. Execute query
2. Click "Download as CSV" or "Download as JSON" in query results
3. Choose delimiter and options
4. Save file

### Visual Query Builder

1. Right-click table → "View/Edit Data" → "All Rows"
2. Click "Query Tool" → "Query Builder"
3. Drag tables from left panel to canvas
4. Define joins by dragging between columns
5. Select columns to display
6. Add WHERE conditions
7. Click "Generate SQL"

### Database Administration

**Create Database:**

```sql
CREATE DATABASE myapp
    WITH OWNER = admin
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0;
```

**Create User:**

```sql
CREATE USER appuser WITH ENCRYPTED PASSWORD 'securepassword';
GRANT ALL PRIVILEGES ON DATABASE myapp TO appuser;
```

**Backup Database:**

1. Right-click database → "Backup..."
2. Choose format: Custom, Tar, Plain (SQL)
3. Select filename
4. Configure options (compression, verbose, etc.)
5. Click "Backup"

**Restore Database:**

1. Right-click database → "Restore..."
2. Select backup file
3. Configure restore options
4. Click "Restore"

### Monitoring

**View Server Activity:**

1. Select server in tree
2. Click "Dashboard" tab
3. View:
   - Server Activity (connections, transactions)
   - Database Statistics
   - Session Activity
   - Locks
   - Prepared Transactions

**Monitor Queries:**

```sql
-- Active queries
SELECT pid, usename, application_name, client_addr, query, state
FROM pg_stat_activity
WHERE state = 'active';

-- Long-running queries
SELECT pid, now() - query_start AS duration, query
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY duration DESC;

-- Kill query
SELECT pg_terminate_backend(12345);  -- Replace with actual PID
```

## Integration

### Integration with PostgreSQL (#22)

pgAdmin automatically discovers and configures Thinkube PostgreSQL:

**Auto-Configuration:**
- Server connection details extracted from StatefulSet
- Password retrieved from environment variables
- Shared server configuration (visible to all users)
- No manual setup required

**Cluster-Internal Access:**
- Uses Kubernetes DNS: `postgresql-official.postgres.svc.cluster.local`
- No external exposure required
- Secure cluster-internal communication

### Integration with Keycloak (#6)

pgAdmin integrates with Keycloak for SSO:

**User Mapping:**
- Keycloak users automatically created in pgAdmin
- Email becomes pgAdmin username
- No separate pgAdmin account needed

**Session Management:**
- OAuth2 tokens managed by Keycloak
- Single logout across all applications
- Token refresh handled automatically

### Script Execution

pgAdmin can be used to execute administrative scripts:

**Example: Database Initialization**

```sql
-- Create schema
CREATE SCHEMA IF NOT EXISTS myapp;

-- Create tables
CREATE TABLE myapp.users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insert sample data
INSERT INTO myapp.users (email) VALUES
    ('user1@example.com'),
    ('user2@example.com');

-- Grant permissions
GRANT USAGE ON SCHEMA myapp TO appuser;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA myapp TO appuser;
```

**Execute Script File:**

1. Click "Query Tool"
2. Click "Open File" (folder icon)
3. Select SQL script
4. Click "Execute" (F5)

## Monitoring

### Health Checks

pgAdmin provides a ping endpoint:

```bash
# Check pgAdmin health
curl https://pgadmin.example.com/misc/ping

# Expected response
{"success":1}
```

### Kubernetes Resources

Monitor pgAdmin pod status:

```bash
# Check pod status
kubectl get pods -n pgadmin

# View pod logs
kubectl logs -n pgadmin -l app=pgadmin --tail=100 -f

# Check init container logs
kubectl logs -n pgadmin -l app=pgadmin -c init-config

# Check resource usage
kubectl top pod -n pgadmin

# Check service
kubectl get svc -n pgadmin

# Check ingress
kubectl get ingress -n pgadmin
```

### Application Logs

pgAdmin logs are available via kubectl:

```bash
# View gunicorn access logs
kubectl logs -n pgadmin -l app=pgadmin | grep "GET\|POST"

# View authentication logs
kubectl logs -n pgadmin -l app=pgadmin | grep "oauth2\|login"

# View error logs
kubectl logs -n pgadmin -l app=pgadmin | grep "ERROR\|CRITICAL"
```

## Troubleshooting

### Connection Issues

**Problem**: Cannot access pgAdmin web interface

```bash
# Check pod status
kubectl get pods -n pgadmin

# Check pod logs
kubectl logs -n pgadmin -l app=pgadmin

# Verify service
kubectl get svc -n pgadmin

# Check ingress
kubectl get ingress -n pgadmin
kubectl describe ingress pgadmin-ingress -n pgadmin

# Test service connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://pgadmin.pgadmin.svc.cluster.local/misc/ping
```

### OIDC Authentication Issues

**Problem**: "Keycloak Login" button not appearing

```bash
# Check init container completed successfully
kubectl logs -n pgadmin -l app=pgadmin -c init-config

# Verify config_local.py was generated
kubectl exec -n pgadmin -l app=pgadmin -- cat /pgadmin4/config_local.py

# Check oauth2-config ConfigMap
kubectl get configmap -n pgadmin pgadmin-oauth-config -o yaml

# Verify Keycloak client exists
# (requires Keycloak admin access)
```

**Problem**: OAuth2 redirect loop or 401 errors

```bash
# Verify Keycloak client redirect URI
# Must match: https://pgadmin.example.com/oauth2/authorize

# Check proxy headers ConfigMap
kubectl get configmap -n pgadmin pgadmin-proxy-headers -o yaml

# Verify X-Forwarded-Proto is set correctly in Ingress
kubectl describe ingress -n pgadmin pgadmin-ingress | grep proxy-set-headers

# Test OIDC metadata endpoint
curl https://keycloak.example.com/realms/thinkube/.well-known/openid-configuration
```

### Database Connection Issues

**Problem**: Cannot connect to PostgreSQL server

```bash
# Verify PostgreSQL is running
kubectl get pods -n postgres

# Test PostgreSQL connectivity from pgAdmin pod
kubectl exec -n pgadmin -l app=pgadmin -- \
  nc -zv postgresql-official.postgres.svc.cluster.local 5432

# Check servers.json configuration
kubectl get configmap -n pgadmin pgadmin-servers -o yaml

# Verify PostgreSQL password
kubectl get statefulset -n postgres postgresql-official -o jsonpath='{.spec.template.spec.containers[0].env}' | jq
```

**Problem**: "FATAL: password authentication failed"

```bash
# Ensure servers.json has correct credentials
# Password should match PostgreSQL POSTGRES_PASSWORD

# Check if server configuration is being loaded
kubectl logs -n pgadmin -l app=pgadmin | grep "servers.json"

# Verify PGADMIN_SERVER_JSON_FILE environment variable
kubectl get deployment -n pgadmin pgadmin -o jsonpath='{.spec.template.spec.containers[0].env}' | grep SERVER_JSON
```

### Performance Issues

**Problem**: Slow query execution or timeouts

```bash
# Increase gunicorn timeout
kubectl set env deployment/pgadmin -n pgadmin GUNICORN_TIMEOUT=300

# Check resource usage
kubectl top pod -n pgadmin

# View active connections in PostgreSQL
kubectl exec -n postgres postgresql-official-0 -- psql -U admin -d mydatabase -c \
  "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"
```

### Init Container Failures

**Problem**: pgAdmin pod stuck in Init state

```bash
# Check init container status
kubectl describe pod -n pgadmin -l app=pgadmin

# View init container logs
kubectl logs -n pgadmin -l app=pgadmin -c init-config

# Verify init script ConfigMap
kubectl get configmap -n pgadmin pgadmin-init-script -o yaml

# Check if Python can execute script
kubectl logs -n pgadmin -l app=pgadmin -c init-config | grep "Error\|Exception"
```

## Testing

### UI Access Test

```bash
# Test HTTPS access
curl -I https://pgadmin.example.com

# Expected: HTTP 200 or 302 (redirect to login)
```

### Health Endpoint Test

```bash
# Test health endpoint
curl https://pgadmin.example.com/misc/ping

# Expected response
{"success":1}
```

### OIDC Configuration Test

```bash
# Verify config_local.py contains OIDC settings
kubectl exec -n pgadmin -l app=pgadmin -- \
  grep -A 10 "AUTHENTICATION_SOURCES" /pgadmin4/config_local.py

# Expected output should show:
# AUTHENTICATION_SOURCES = ['oauth2']
```

### PostgreSQL Connection Test

**From pgAdmin UI:**
1. Login via Keycloak
2. Expand "Servers" → "Thinkube PostgreSQL"
3. Should connect automatically without prompting for password

**From CLI:**

```bash
# Execute test query via pgAdmin API (requires authentication)
# This is complex; UI testing is recommended

# Alternative: Test from pgAdmin pod directly
kubectl exec -n pgadmin -l app=pgadmin -- \
  psql postgresql://admin:PASSWORD@postgresql-official.postgres.svc.cluster.local:5432/mydatabase \
  -c "SELECT version();"
```

### Database Query Test

Execute test query in pgAdmin:

```sql
-- Test connection
SELECT version();

-- Test permissions
CREATE TABLE test_table (id SERIAL, data TEXT);
INSERT INTO test_table (data) VALUES ('test');
SELECT * FROM test_table;
DROP TABLE test_table;
```

## Rollback

To rollback or remove the pgAdmin deployment:

```bash
# Delete pgAdmin deployment and resources
kubectl delete deployment -n pgadmin pgadmin
kubectl delete svc -n pgadmin pgadmin
kubectl delete ingress -n pgadmin pgadmin-ingress

# Delete ConfigMaps
kubectl delete configmap -n pgadmin pgadmin-oauth-config
kubectl delete configmap -n pgadmin pgadmin-init-script
kubectl delete configmap -n pgadmin pgadmin-proxy-headers
kubectl delete configmap -n pgadmin pgadmin-servers
kubectl delete configmap -n pgadmin thinkube-service-config

# Delete secrets
kubectl delete secret -n pgadmin pgadmin-tls-secret

# Optional: Delete namespace
kubectl delete namespace pgadmin

# Optional: Delete Keycloak client
# (requires manual deletion via Keycloak admin UI or API)
```

**Note**: Deleting the pgadmin namespace will remove all pgAdmin data including user preferences, saved queries, and custom server configurations.

## References

- [pgAdmin Documentation](https://www.pgadmin.org/docs/)
- [pgAdmin OAuth2 Authentication](https://www.pgadmin.org/docs/pgadmin4/latest/oauth2.html)
- [pgAdmin Server Configuration](https://www.pgadmin.org/docs/pgadmin4/latest/import_export_servers.html)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [pgAdmin Container Deployment](https://www.pgadmin.org/docs/pgadmin4/latest/container_deployment.html)
- [pgAdmin Configuration](https://www.pgadmin.org/docs/pgadmin4/latest/config_py.html)

---

🤖 [AI-assisted]
