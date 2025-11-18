# thinkube.yaml Specification v1.0

## Purpose
A static descriptor file that tells thinkube-control what containers an application has and how to deploy them.

## Core Principles
1. **Static Descriptor** - NOT a template with conditionals
2. **Cloud Agnostic** - Works on-premise and cloud (via future bridge)
3. **Simple** - No Kubernetes knowledge required
4. **Flexible** - Supports 1 to N containers

## Schema

```yaml
apiVersion: thinkube.io/v1
kind: ThinkubeDeployment
metadata:
  name: string              # Application name

spec:
  containers:               # List of containers
    - name: string          # Container identifier
      build: string         # Build context path
      port: number          # Container port (optional)
      size: string          # Resource size: small/medium/large/xlarge (optional)
      schedule: string      # Cron expression for scheduled tasks (optional)
      mounts:               # Storage mounts (optional)
        - string            # Format: "storage-name:/mount/path"
      gpu:                  # GPU requirements (optional)
        count: number       # Number of GPUs (required when gpu is specified)
        memory: string      # Minimum memory per GPU (required when gpu is specified)
      test:                 # Test configuration (optional)
        enabled: boolean    # Enable testing for this container (default: false)
        command: string     # Test command (required when enabled is true)
        image: string       # Test image override (optional)
      migrations:           # Database migration configuration (optional)
        tool: string        # Migration tool: alembic, django, flyway, liquibase, etc.
        auto: boolean       # Auto-run migrations on startup (default: true)
  
  routes:                   # HTTP routing rules (optional)
    - path: string          # URL path
      to: string            # Container name
  
  services:                 # Platform services needed (optional)
    - string                # Service type or "type:name" format
```

## Field Descriptions

### metadata.name
- The application name
- Supports substitution: `"{{ project_name }}"`

### spec.containers
- List of containers that make up the application
- At least one container required

### spec.containers[].name
- Unique identifier for the container
- Used in routing and references
- Examples: `backend`, `frontend`, `worker`, `api`

### spec.containers[].build
- Path to build context relative to project root
- Examples: `"."`, `"./backend"`, `"./services/api"`

### spec.containers[].port
- TCP port the container listens on
- Optional for workers/jobs that don't expose ports
- Must be a number between 1-65535

### spec.containers[].size
- Resource allocation hint
- Values: `"small"`, `"medium"`, `"large"`, `"xlarge"`
- Optional, defaults to `"small"`
- Size recommendations:
  - `small`: Basic web apps, microservices (256MB RAM)
  - `medium`: Standard applications (512MB RAM)
  - `large`: Resource-intensive apps (1GB RAM)
  - `xlarge`: ML/AI workloads, LLMs (24GB RAM)

### spec.containers[].schedule
- Cron expression for scheduled containers
- Example: `"0 * * * *"` (hourly)
- Optional, only for cron jobs
- Container will not have persistent pods

### spec.containers[].mounts
- Storage volume mounts
- Format: `"storage-name:/mount/path"`
- Example: `"uploads:/app/uploads"`
- Storage must be declared in services

### spec.containers[].gpu
- GPU resource requirements for the container
- Optional field for ML/AI workloads
- When specified, MUST include both count and memory:
  ```yaml
  gpu:
    count: 1         # Number of GPUs (required)
    memory: "10Gi"   # Minimum GPU memory per GPU (required)
  ```
- Both fields are mandatory to ensure proper resource allocation
- Platform behavior:
  - Allocates the specified number of GPUs
  - Ensures each GPU has at least the specified memory
  - Uses GPU operator labels (`nvidia.com/gpu.memory`) for scheduling
  - Prefers lower-capability GPUs that meet requirements to conserve resources
- Examples:
  - `gpu: {count: 1, memory: "10Gi"}` - Request 1 GPU with at least 10GB memory
  - `gpu: {count: 1, memory: "20Gi"}` - Request 1 GPU with at least 20GB memory  
  - `gpu: {count: 2, memory: "20Gi"}` - Request 2 GPUs, each with at least 20GB memory

### spec.containers[].capabilities
- Special container capabilities
- Optional array of capability strings
- Available capabilities:
  - `"large-uploads"` - Configures nginx for large file uploads (up to 1GB)

### spec.containers[].test
- Test configuration for CI/CD pipelines
- Optional object that controls testing behavior
- Tests run before container builds in CI/CD workflows

### spec.containers[].test.enabled
- Whether to run tests for this container
- Optional boolean, defaults to `false`
- When set to `true`, test.command must be provided
- Set to `false` to skip tests during CI/CD builds

### spec.containers[].test.command
- Test command to run
- Required when test.enabled is true
- Must be explicitly specified - no auto-detection
- Examples:
  - Python: `"./run_tests.sh"` or `"pytest -v"`
  - Node.js: `"npm test"` or `"npm run test:ci"`
  - Go: `"go test ./..."` or `"make test"`

### spec.containers[].test.image
- Override test runner image
- Optional string, defaults to appropriate base image based on container
- Default images provided by the platform:
  - Python containers: `registry.{{ domain_name }}/library/python-base:3.11-slim`
  - Node.js containers: `registry.{{ domain_name }}/library/node-base:18-alpine`
  - General purpose: `registry.{{ domain_name }}/library/test-runner:latest`
- The default images include common testing frameworks pre-installed
- Useful for custom test environments or specific tool versions
- Example: `"myregistry/custom-test-runner:latest"`

### spec.containers[].migrations
- Database migration configuration
- Optional object that controls migration behavior
- Only relevant for containers that use databases

### spec.containers[].migrations.tool
- The migration tool used by the container
- Required when migrations object is specified
- Supported values:
  - `"alembic"` - Python Alembic migrations
  - `"django"` - Django migrations
  - `"flyway"` - Flyway migrations (Java/SQL)
  - `"liquibase"` - Liquibase migrations
  - `"prisma"` - Prisma migrations
  - `"sequelize"` - Sequelize migrations (Node.js)
  - `"gorm"` - GORM AutoMigrate (Go)
  - `"custom"` - Custom migration tool
- The platform will configure appropriate startup hooks based on the tool

### spec.containers[].migrations.auto
- Whether to run migrations automatically on container startup
- Optional boolean, defaults to `true`
- When `true`, migrations run before the application starts
- When `false`, migrations must be run manually
- For production-like environments, consider setting to `false`

### spec.routes
- HTTP ingress routing rules
- Maps URL paths to containers
- Paths are matched in order (most specific first)

### spec.routes[].path
- URL path pattern
- Examples: `/`, `/api`, `/api/v1`
- Supports prefix matching

### spec.routes[].to
- Container name to route to
- Must match a container name in the containers list

### spec.services
- Platform services the application requires
- Available types: `"database"`, `"cache"`, `"storage"`, `"queue"`
- Format: `"type"` or `"type:name"` for named instances
- Example: `"storage:uploads"` creates storage named "uploads"

## Substitutions Allowed
- `{{ project_name }}` - The project name
- `{{ domain_name }}` - The platform domain

## Examples

### Minimal Application
```yaml
apiVersion: thinkube.io/v1
kind: ThinkubeDeployment
metadata:
  name: "{{ project_name }}"

spec:
  containers:
    - name: app
      build: .
      port: 3000
```

### Web Application with Database
```yaml
apiVersion: thinkube.io/v1
kind: ThinkubeDeployment
metadata:
  name: "{{ project_name }}"

spec:
  containers:
    - name: backend
      build: ./backend
      port: 8000
      test:
        enabled: true
        command: "pytest --cov=app"
      migrations:
        tool: alembic
        auto: true
      
    - name: frontend
      build: ./frontend
      port: 80
      test:
        enabled: true
  
  routes:
    - path: /api
      to: backend
    - path: /
      to: frontend
  
  services:
    - database
```

### Complex Application
```yaml
apiVersion: thinkube.io/v1
kind: ThinkubeDeployment
metadata:
  name: "{{ project_name }}"

spec:
  containers:
    - name: api
      build: ./api
      port: 8000
      size: medium
      
    - name: webapp
      build: ./webapp
      port: 3000
      
    - name: upload-service
      build: ./upload
      port: 8080
      capabilities: ["large-uploads"]
      mounts:
        - uploads:/data/uploads
      
    - name: worker
      build: ./worker
      size: large
      test:
        enabled: false  # Skip tests for worker
      
    - name: scheduler
      build: ./scheduler
      schedule: "*/15 * * * *"
      test:
        enabled: true
        command: "go test -v ./..."
      
    - name: backup
      build: ./jobs
      schedule: "0 2 * * *"
      mounts:
        - backups:/data/backups
  
  routes:
    - path: /api
      to: api
    - path: /upload
      to: upload-service
    - path: /ws
      to: api
    - path: /
      to: webapp
  
  services:
    - database
    - cache
    - storage:uploads
    - storage:backups
    - queue
```

### ML/AI Application with GPU
```yaml
apiVersion: thinkube.io/v1
kind: ThinkubeDeployment
metadata:
  name: "{{ project_name }}"

spec:
  containers:
    - name: inference
      build: .
      port: 7860
      size: xlarge
      gpu:
        count: 1
        memory: "20Gi"
      health: /health
      test:
        enabled: false  # GPU testing may not be available in CI/CD
  
  routes:
    - path: /
      to: inference
```

## Platform Behavior

### Resource Allocation
Based on the `size` field:
- `small`: 256Mi memory, 100m CPU
- `medium`: 512Mi memory, 500m CPU  
- `large`: 1Gi memory, 1000m CPU

### Service Connections
When a service is declared, environment variables are automatically injected:
- `database` → `DATABASE_URL`
- `cache` → `CACHE_URL`
- `storage:name` → `STORAGE_NAME_URL`
- `queue` → `QUEUE_URL`

### Health Checks
All containers with ports must expose `/health` endpoint for health checks.

### TLS Certificates
HTTPS is automatically enabled using platform wildcard certificates.

### CI/CD Testing
When tests are configured:
- Tests run automatically before container builds
- Failed tests prevent deployment
- Test results are reported to thinkube-control
- Coverage reports are collected when available
- Tests run in isolated environments with service connections

## What is NOT Included

This specification intentionally excludes:
- ❌ Conditional logic (`{% if %}` statements)
- ❌ Complex Kubernetes configurations
- ❌ Cloud-specific settings
- ❌ Deployment strategies
- ❌ Service mesh configurations
- ❌ Raw environment variables (use Dockerfile ENV)
- ❌ Command overrides (use Dockerfile CMD)
- ❌ Multi-region deployments

These complexities are handled by:
- **Dockerfiles** - For container-specific configuration
- **thinkube-control** - For deployment orchestration
- **Cloud Bridge** (future) - For cloud-specific optimizations

## Version History

- **v1.0** (2024-01-29) - Initial specification
  - Simple, static descriptor
  - Support for multiple containers
  - Basic routing and services
  - Focus on developer simplicity
  - Optional test configuration for CI/CD
  - Migration configuration for database containers