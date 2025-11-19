# Valkey

## Overview

Valkey is an open-source, high-performance in-memory data store that is fully compatible with Redis. Deployed as a persistent service with AOF (Append-Only File) and snapshot backups, Valkey provides reliable key-value storage for infrastructure services, session management, caching, and message queuing.

**Key Features**:
- **Redis Compatibility**: Drop-in replacement for Redis with full protocol compatibility
- **Persistence**: AOF and RDB snapshots for data durability
- **High Performance**: Sub-millisecond latency for most operations
- **External Access**: TCP passthrough on port 6379 for external clients
- **Internal Service**: ClusterIP and headless services for in-cluster access
- **Custom Image**: Built from Alpine edge repository (version 8.1.0)

## Dependencies

**Core Components** (always available):
- Kubernetes (#1) - k8s-snap 1.34.0
- Harbor (#14) - Container registry for custom Valkey image
- Ingress (#7) - NGINX Ingress Controller with TCP passthrough

**Optional Components** (dependent on Valkey):
- Argilla (#46) - NLP annotation platform uses Valkey for caching

## Prerequisites

```yaml
requirements:
  kubernetes:
    version: "1.34.0"
    provider: "k8s-snap"

  harbor:
    custom_image: "library/valkey:7.2-alpine"
    robot_account: "kaniko"
    token_source: "HARBOR_ROBOT_TOKEN in ~/.env"

  storage:
    persistence: true
    size: "5Gi"
    storage_class: "k8s-hostpath"
    access_mode: "ReadWriteOnce"

  networking:
    external_port: 6379
    tcp_passthrough: true
    internal_services:
      - "valkey.valkey.svc.cluster.local:6379"
      - "valkey-headless.valkey.svc.cluster.local:6379"

  valkey_configuration:
    save_snapshot: "900 1"  # Every 900s if 1+ keys changed
    appendonly: "yes"       # AOF enabled
    protected_mode: "no"    # Disabled (cluster-internal only)

  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"
```

## Playbooks

### **Main Deployment**
**File**: [10_deploy.yaml](10_deploy.yaml)

Deploys Valkey with persistence and external access:

- **Harbor Robot Token Loading**
  - Loads `HARBOR_ROBOT_TOKEN` from `~/.env` file
  - Sets facts: `harbor_robot_user` (robot$kaniko), `harbor_robot_token`
  - Verifies token is available
  - Fails deployment if token missing

- **Namespace Creation**
  - Creates `valkey` namespace

- **Harbor Registry Secret**
  - Creates `harbor-registry-secret` in `valkey` namespace
  - Type: `kubernetes.io/dockerconfigjson`
  - Auth: robot$kaniko with token from environment
  - Enables pulling custom Valkey image from Harbor

- **Persistent Volume Claim**
  - Name: `valkey-data`
  - Access mode: ReadWriteOnce
  - Storage class: `k8s-hostpath`
  - Size: 5Gi
  - Mount point: `/data` in container

- **Valkey Deployment**
  - Replicas: 1 (single instance)
  - Image: `{harbor_registry}/library/valkey:7.2-alpine`
  - Image pull policy: Always
  - Image pull secret: `harbor-registry-secret`
  - **Command**: `valkey-server` with arguments:
    - `--save 900 1`: Save snapshot every 900 seconds if 1+ keys changed
    - `--appendonly yes`: Enable AOF for durability
    - `--protected-mode no`: Disable protected mode (cluster-internal only)
  - **Port**: 6379 (container port)
  - **Resources**:
    - Requests: 128Mi memory, 100m CPU
    - Limits: 256Mi memory, 200m CPU
  - **Volume Mount**: PVC `valkey-data` at `/data`

- **ClusterIP Service**
  - Name: `valkey`
  - Type: ClusterIP
  - Port: 6379
  - Target port: 6379
  - Selector: `app=valkey`
  - **Purpose**: Standard cluster-internal access

- **Headless Service**
  - Name: `valkey-headless`
  - ClusterIP: None
  - Port: 6379
  - Target port: 6379
  - Selector: `app=valkey`
  - **Purpose**: Direct pod access for stateful applications

- **TLS Certificate Setup**
  - Retrieves wildcard certificate from `default` namespace
  - Copies to `valkey` namespace as `valkey-tls-secret`
  - **Note**: TLS not used by Valkey protocol, but available for future use

- **TCP Passthrough Configuration**
  - Patches NGINX Ingress ConfigMap `primary-ingress-ingress-nginx-tcp`
  - Maps port 6379 to `valkey/valkey:6379`
  - Enables external access: `valkey.example.com:6379`

- **Deployment Information Display**
  - Namespace: `valkey`
  - External URL: `valkey.example.com:6379`
  - Internal services: ClusterIP and headless
  - Persistence: 5Gi with AOF and snapshots

### **Service Discovery**
**File**: [17_configure_discovery.yaml](17_configure_discovery.yaml)

Registers Valkey with Thinkube service discovery system:

- **ConfigMap Creation** (`thinkube-service-config` in `valkey` namespace)
  - Service type: `optional`
  - Category: `infrastructure`
  - Icon: `/icons/tk_data.svg`
  - Component version: `0.1.0` (from VERSION file)

- **Endpoints Registered**:
  - Primary: External TCP at `valkey.example.com:6379` (TCP passthrough)
  - Secondary: Internal service at `valkey.valkey.svc.cluster.local:6379`

- **Scaling Configuration**:
  - Resource type: Deployment `valkey`
  - Namespace: `valkey`
  - Min replicas: 1
  - Can disable: false (infrastructure service)

- **Environment Variables**:
  - `VALKEY_HOST`: `valkey.example.com`
  - `VALKEY_PORT`: `6379`

- **Code-Server Integration**:
  - Updates code-server environment variables via `code_server_env_update` role
  - Makes Valkey connection details available to development environment

## Deployment

This component is automatically deployed via the **thinkube-control Optional Components interface**:

1. Navigate to https://thinkube.example.com/optional-components
2. Locate the **Valkey** card in the **Infrastructure** section
3. Click **Install** to deploy the component
4. Monitor real-time deployment progress via WebSocket streaming
5. Verify deployment status in the dashboard

The deployment executes the orchestrator playbook at `/ansible/40_thinkube/optional/valkey/00_install.yaml`.

**Deployment Sequence**:
1. Load Harbor robot token from ~/.env
2. Create namespace
3. Create Harbor registry pull secret
4. Create persistent volume claim (5Gi)
5. Deploy Valkey with AOF and snapshot configuration
6. Create ClusterIP service
7. Create headless service
8. Copy TLS certificate (for future use)
9. Configure TCP passthrough for external access
10. Register with service discovery

**Important**: Ensure `HARBOR_ROBOT_TOKEN` is set in `~/.env` before deployment. This token is created during Harbor installation.

## Access Points

### External Access (TCP Passthrough)

```
valkey.example.com:6379
```

Connect with Redis client:
```bash
redis-cli -h valkey.example.com -p 6379 PING
```

### Internal Cluster Access

**ClusterIP Service**:
```
valkey.valkey.svc.cluster.local:6379
```

**Headless Service** (direct pod access):
```
valkey-headless.valkey.svc.cluster.local:6379
```

Example from another pod:
```bash
redis-cli -h valkey.valkey.svc.cluster.local -p 6379 PING
```

## Configuration

### Persistence Settings

Valkey is configured with dual persistence:

1. **RDB Snapshots**:
   - Trigger: Every 900 seconds (15 minutes) if 1+ keys changed
   - File: `/data/dump.rdb`
   - Purpose: Point-in-time backups

2. **AOF (Append-Only File)**:
   - Enabled: yes
   - File: `/data/appendonly.aof`
   - Purpose: Write log for durability
   - Fsync policy: Default (every second)

### Security Settings

- **Protected Mode**: Disabled (`--protected-mode no`)
- **Reason**: Valkey is only accessible within Kubernetes cluster network
- **Authentication**: None configured (cluster-internal service)
- **For Production**: Consider enabling AUTH if exposing externally

### Resource Limits

Adjust resources by editing deployment:

```bash
kubectl edit deployment valkey -n valkey
```

Recommended limits:
- **Light workload**: 128Mi-256Mi memory, 100m-200m CPU (default)
- **Medium workload**: 512Mi-1Gi memory, 500m-1 CPU
- **Heavy workload**: 2Gi-4Gi memory, 1-2 CPU

### Storage Expansion

Increase PVC size:

```bash
# Edit PVC
kubectl edit pvc valkey-data -n valkey

# Change spec.resources.requests.storage to desired size
```

**Note**: Requires storage class to support volume expansion.

## Usage

### Redis CLI

From external client:
```bash
# Install redis-cli
apt-get install redis-tools  # Ubuntu/Debian
brew install redis           # macOS

# Connect
redis-cli -h valkey.example.com -p 6379

# Basic commands
> PING
PONG
> SET mykey "hello"
OK
> GET mykey
"hello"
> DEL mykey
(integer) 1
```

### Python Client

```python
import redis

# Connect to external endpoint
r = redis.Redis(host='valkey.example.com', port=6379, decode_responses=True)

# Or connect from within cluster
# r = redis.Redis(host='valkey.valkey.svc.cluster.local', port=6379, decode_responses=True)

# Basic operations
r.set('key', 'value')
value = r.get('key')
print(value)  # 'value'

# Lists
r.lpush('mylist', 'item1', 'item2', 'item3')
items = r.lrange('mylist', 0, -1)
print(items)  # ['item3', 'item2', 'item1']

# Sets
r.sadd('myset', 'member1', 'member2')
members = r.smembers('myset')
print(members)  # {'member1', 'member2'}

# Hashes
r.hset('user:1000', mapping={'name': 'Alice', 'age': '30'})
user = r.hgetall('user:1000')
print(user)  # {'name': 'Alice', 'age': '30'}

# Pub/Sub
pubsub = r.pubsub()
pubsub.subscribe('mychannel')
r.publish('mychannel', 'hello')

# Expiration
r.setex('tempkey', 60, 'expires in 60 seconds')
ttl = r.ttl('tempkey')
print(ttl)  # ~60
```

### Node.js Client

```javascript
const redis = require('redis');

// Connect to Valkey
const client = redis.createClient({
  url: 'redis://valkey.example.com:6379'
});

client.on('error', (err) => console.log('Redis Client Error', err));

await client.connect();

// Basic operations
await client.set('key', 'value');
const value = await client.get('key');
console.log(value); // 'value'

await client.disconnect();
```

### Go Client

```go
package main

import (
    "context"
    "fmt"
    "github.com/redis/go-redis/v9"
)

func main() {
    ctx := context.Background()

    rdb := redis.NewClient(&redis.Options{
        Addr: "valkey.example.com:6379",
    })

    // Basic operations
    err := rdb.Set(ctx, "key", "value", 0).Err()
    if err != nil {
        panic(err)
    }

    val, err := rdb.Get(ctx, "key").Result()
    if err != nil {
        panic(err)
    }
    fmt.Println("key", val)
}
```

## Integration

### Argilla NLP Annotation

Argilla uses Valkey for caching and session management:

- **Connection**: Internal service `valkey.valkey.svc.cluster.local:6379`
- **Purpose**: Cache annotation suggestions, store user sessions
- **Configuration**: Environment variable `REDIS_HOST`

### Session Storage

Use Valkey for web application sessions:

```python
from flask import Flask, session
from flask_session import Session
import redis

app = Flask(__name__)
app.config['SESSION_TYPE'] = 'redis'
app.config['SESSION_REDIS'] = redis.Redis(
    host='valkey.valkey.svc.cluster.local',
    port=6379
)
Session(app)

@app.route('/')
def index():
    session['user_id'] = 1000
    return 'Session stored in Valkey'
```

### Caching Layer

Use Valkey as a cache for expensive operations:

```python
import redis
import json
import time

cache = redis.Redis(host='valkey.valkey.svc.cluster.local', port=6379, decode_responses=True)

def get_expensive_data(key):
    # Check cache first
    cached = cache.get(f'cache:{key}')
    if cached:
        return json.loads(cached)

    # Compute expensive operation
    data = expensive_computation(key)

    # Store in cache for 1 hour
    cache.setex(f'cache:{key}', 3600, json.dumps(data))
    return data
```

### Message Queue

Use Valkey lists as a simple message queue:

```python
import redis
import json

r = redis.Redis(host='valkey.valkey.svc.cluster.local', port=6379)

# Producer
def send_task(task_data):
    r.rpush('task_queue', json.dumps(task_data))

# Consumer
def process_tasks():
    while True:
        # Blocking pop with 5 second timeout
        task = r.blpop('task_queue', timeout=5)
        if task:
            _, task_data = task
            data = json.loads(task_data)
            process_task(data)
```

## Monitoring

### Check Pod Status

```bash
kubectl get pods -n valkey
kubectl describe pod -n valkey <pod-name>
```

### View Logs

```bash
kubectl logs -n valkey <pod-name> -f
```

### Monitor Valkey Metrics

Connect with redis-cli:
```bash
redis-cli -h valkey.example.com -p 6379 INFO
```

Key metrics:
- `used_memory`: Current memory usage
- `used_memory_peak`: Peak memory usage
- `total_commands_processed`: Total commands executed
- `instantaneous_ops_per_sec`: Current ops/sec
- `keyspace`: Number of keys per database

Monitor specific sections:
```bash
redis-cli -h valkey.example.com -p 6379 INFO memory
redis-cli -h valkey.example.com -p 6379 INFO stats
redis-cli -h valkey.example.com -p 6379 INFO replication
```

### Check Persistence

View persistence status:
```bash
redis-cli -h valkey.example.com -p 6379 INFO persistence
```

Check last save time:
```bash
redis-cli -h valkey.example.com -p 6379 LASTSAVE
```

Force save:
```bash
redis-cli -h valkey.example.com -p 6379 SAVE
# Or background save
redis-cli -h valkey.example.com -p 6379 BGSAVE
```

### Slow Log

Monitor slow queries:
```bash
# Get slow log entries
redis-cli -h valkey.example.com -p 6379 SLOWLOG GET 10

# Get slow log length
redis-cli -h valkey.example.com -p 6379 SLOWLOG LEN

# Reset slow log
redis-cli -h valkey.example.com -p 6379 SLOWLOG RESET
```

## Troubleshooting

### Verify Deployment

Check deployment:
```bash
kubectl get deployment valkey -n valkey
kubectl describe deployment valkey -n valkey
```

Check services:
```bash
kubectl get svc -n valkey
```

Should show:
- `valkey` (ClusterIP)
- `valkey-headless` (ClusterIP: None)

### Test Connectivity

From within cluster:
```bash
kubectl run redis-test --rm -it --restart=Never \
  --image=redis:alpine \
  -- redis-cli -h valkey.valkey.svc.cluster.local PING
```

From external:
```bash
redis-cli -h valkey.example.com -p 6379 PING
```

### Check TCP Passthrough

Verify Ingress ConfigMap:
```bash
kubectl get configmap primary-ingress-ingress-nginx-tcp -n ingress -o yaml | grep 6379
```

Should show:
```yaml
data:
  "6379": "valkey/valkey:6379"
```

### Check Persistence

Verify PVC:
```bash
kubectl get pvc valkey-data -n valkey
```

Should show `Bound` status.

Check data directory:
```bash
kubectl exec -n valkey <pod-name> -- ls -lh /data
```

Should show:
- `dump.rdb` (if snapshots occurred)
- `appendonly.aof` (AOF file)

### Memory Issues

Check memory usage:
```bash
redis-cli -h valkey.example.com -p 6379 INFO memory | grep used_memory_human
```

If memory is high:
1. Check for large keys:
```bash
redis-cli -h valkey.example.com -p 6379 --bigkeys
```

2. Set maxmemory policy:
```bash
redis-cli -h valkey.example.com -p 6379 CONFIG SET maxmemory 200mb
redis-cli -h valkey.example.com -p 6379 CONFIG SET maxmemory-policy allkeys-lru
```

### Connection Refused

**Issue**: Cannot connect to Valkey
- **Solution**: Check pod is running
- **Solution**: Verify service exists
- **Solution**: Check TCP passthrough configuration
- **Solution**: Verify firewall allows port 6379

### Data Loss

**Issue**: Data not persisting across pod restarts
- **Solution**: Verify PVC is bound and mounted
- **Solution**: Check AOF file exists: `kubectl exec -n valkey <pod> -- ls /data`
- **Solution**: Check Valkey logs for write errors

### High Latency

**Issue**: Slow response times
- **Solution**: Check SLOWLOG for slow commands
- **Solution**: Reduce memory usage (evict old keys)
- **Solution**: Increase CPU/memory resources
- **Solution**: Check for blocking commands (KEYS, SCAN with large cursor)

## Common Issues

**Issue**: Pod stuck in Pending
- **Solution**: Check PVC is bound
```bash
kubectl get pvc valkey-data -n valkey
```

**Issue**: Image pull errors
- **Solution**: Verify HARBOR_ROBOT_TOKEN in ~/.env
- **Solution**: Check Harbor registry is accessible
- **Solution**: Verify image exists: `{harbor_registry}/library/valkey:7.2-alpine`

**Issue**: Cannot connect from external clients
- **Solution**: Verify TCP passthrough is configured
- **Solution**: Check firewall rules for port 6379
- **Solution**: Verify DNS resolves `valkey.example.com`

**Issue**: Out of memory
- **Solution**: Increase deployment memory limits
- **Solution**: Configure maxmemory and eviction policy
- **Solution**: Reduce data stored in Valkey

## Testing

The test playbook [18_test.yaml](18_test.yaml) verifies:
- Namespace exists
- Pod is running
- Services are configured
- PVC is bound
- Valkey responds to PING command
- Can SET and GET keys
- Persistence is working

## Rollback

To uninstall Valkey:

```bash
cd ~/thinkube
./scripts/tk_ansible ansible/40_thinkube/optional/valkey/19_rollback.yaml
```

**Warning**: This will delete all Valkey data including the PVC. Backup important data before uninstalling.

### Backup Data

Before rollback, save important keys:

```bash
# Dump all keys
redis-cli -h valkey.example.com -p 6379 --rdb /tmp/valkey-backup.rdb

# Or use SAVE to create snapshot
redis-cli -h valkey.example.com -p 6379 SAVE

# Copy RDB file from pod
kubectl cp valkey/<pod-name>:/data/dump.rdb /tmp/valkey-backup.rdb
```

## Performance Considerations

- **Memory**: Valkey stores all data in memory; size appropriately
- **Persistence**: AOF provides durability but adds write overhead
- **Network**: TCP passthrough adds minimal latency
- **CPU**: Most operations are CPU-light; increase for heavy workloads
- **Pipelining**: Use pipelining for bulk operations to reduce RTT

## Security Considerations

**Current Configuration**:
- No authentication (protected-mode disabled)
- Cluster-internal access only
- TCP passthrough exposes to external network

**For Production**:
1. Enable authentication:
```bash
redis-cli -h valkey.example.com -p 6379 CONFIG SET requirepass "strong_password"
```

2. Restrict external access with NetworkPolicies
3. Use TLS for encrypted connections
4. Enable ACLs for fine-grained permissions
5. Regular security updates via Harbor image rebuilds

## References

- [Valkey Official Documentation](https://valkey.io/)
- [Redis Protocol Specification](https://redis.io/docs/reference/protocol-spec/)
- [Redis Commands Reference](https://redis.io/commands/)
- [Python Redis Client](https://github.com/redis/redis-py)
- [Node.js Redis Client](https://github.com/redis/node-redis)

🤖 [AI-assisted]
