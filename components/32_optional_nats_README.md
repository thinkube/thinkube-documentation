# NATS

## Overview

NATS is a high-performance messaging system for cloud-native applications and microservices. Deployed with JetStream for persistent messaging and stream processing, NATS enables real-time communication between AI services, agent systems, and event-driven ML pipelines.

**Key Features**:
- **High Performance**: Sub-millisecond latency, millions of messages per second
- **JetStream**: Persistent messaging with stream processing and at-least-once delivery
- **Multiple Protocols**: Core NATS pub/sub, JetStream, Key/Value store, Object Store
- **External Access**: Both HTTP monitoring (HTTPS) and TCP client protocol (port 4222)
- **Persistent Storage**: 10Gi persistent volume for JetStream message storage
- **AI Integration**: Real-time agent coordination, LLM observability, model update notifications

## Dependencies

**Core Components** (always available):
- Kubernetes (#1) - k8s-snap 1.34.0
- Ingress (#7) - NGINX Ingress Controller with TCP passthrough
- Harbor (#14) - Container registry for NATS images

**Optional Components**:
- None (NATS is a foundational infrastructure service)

## Prerequisites

```yaml
requirements:
  kubernetes:
    version: "1.34.0"
    provider: "k8s-snap"

  networking:
    ingress_controller: "nginx"
    tcp_passthrough: true
    ports:
      client: 4222
      cluster: 6222
      monitoring: 8222

  storage:
    jetstream_pvc: "10Gi"
    storage_class: "default"

  resources:
    nats:
      replicas: 1
      cpu: "500m-1"
      memory: "512Mi-2Gi"
```

## Playbooks

### **Main Deployment**
**File**: [10_deploy.yaml](10_deploy.yaml)

Deploys NATS with JetStream and external access:

- **Namespace and TLS Setup**
  - Creates `nats` namespace
  - Copies wildcard TLS certificate from `default` namespace
  - Creates `nats-tls-secret` for HTTPS monitoring

- **NATS Helm Deployment**
  - Adds NATS Helm repository: `https://nats-io.github.io/k8s/helm/charts/`
  - Deploys NATS chart version 2.12.0-alpine from Harbor registry
  - Configures JetStream with 10Gi persistent storage
  - Single replica (homelab configuration)
  - Resource limits: 500m-1 CPU, 512Mi-2Gi memory

- **JetStream Configuration**
  - File store enabled with PVC
  - Persistent volume survives pod restarts
  - Cluster mode disabled for single-node deployment

- **nats-box CLI Tool**
  - Version 0.18.1 from Harbor registry
  - Used for testing and management within cluster

- **Monitoring HTTP Ingress**
  - Host: `nats.example.com`
  - Port: 8222 (HTTP monitoring endpoint)
  - TLS termination with wildcard certificate
  - Backend protocol: HTTP

- **Client TCP Passthrough**
  - Patches NGINX Ingress ConfigMap `primary-ingress-ingress-nginx-tcp`
  - Routes port 4222 to `nats/nats:4222`
  - Enables external NATS client connections via TCP

- **Health Verification**
  - Waits for NATS pod to be Running (30 retries, 10s delay)
  - Checks pod with label `app.kubernetes.io/component=nats`

### **Service Discovery**
**File**: [17_configure_discovery.yaml](17_configure_discovery.yaml)

Registers NATS with Thinkube service discovery system:

- **ConfigMap Creation** (`thinkube-service-config` in `nats` namespace)
  - Service type: `optional`
  - Category: `infrastructure`
  - Icon: `/icons/tk_devops.svg`
  - Component version: `0.1.0` (from VERSION file)

- **Endpoints Registered**:
  - Primary: External monitoring (HTTPS) at `https://nats.example.com` (health: `/healthz`)
  - External client (TCP) at `nats.example.com:4222`
  - Internal client (NATS protocol) at `nats://nats.nats.svc.cluster.local:4222`
  - Internal monitoring (HTTP) at `http://nats.nats.svc.cluster.local:8222` (health: `/healthz`)

- **Scaling Configuration**:
  - Resource type: StatefulSet `nats`
  - Min replicas: 1
  - Can disable: true

- **Environment Variables**:
  - `NATS_URL`: `nats://nats.example.com:4222`

- **Code-Server Integration**
  - Updates code-server environment variables via `code_server_env_update` role
  - Makes NATS_URL available to development environment

## Deployment

This component is automatically deployed via the **thinkube-control Optional Components interface**:

1. Navigate to https://thinkube.example.com/optional-components
2. Locate the **NATS** card in the **Infrastructure** section
3. Click **Install** to deploy the component
4. Monitor real-time deployment progress via WebSocket streaming
5. Verify deployment status in the dashboard

The deployment executes the orchestrator playbook at `/ansible/40_thinkube/optional/nats/00_install.yaml`.

**Deployment Sequence**:
1. Create namespace and copy TLS secret
2. Deploy NATS with Helm (JetStream enabled)
3. Wait for pod to be ready
4. Configure HTTP ingress for monitoring
5. Configure TCP passthrough for client connections
6. Register with service discovery
7. Update code-server environment

## Access Points

### External Access

**Monitoring Dashboard** (HTTPS):
```
https://nats.example.com
```

Health check:
```bash
curl https://nats.example.com/healthz
```

**Client Protocol** (TCP passthrough on port 4222):
```
nats://nats.example.com:4222
```

### Internal Cluster Access

**NATS Client Protocol**:
```
nats://nats.nats.svc.cluster.local:4222
```

**Monitoring Endpoint**:
```
http://nats.nats.svc.cluster.local:8222
```

## Configuration

### JetStream Persistent Storage

JetStream uses a 10Gi persistent volume for message storage:

```bash
# Check JetStream storage usage
kubectl exec -n nats nats-0 -- df -h /data

# View JetStream account info
kubectl exec -n nats nats-0 -- nats account info
```

### Resource Limits

Default resource configuration (homelab-appropriate):

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "1"
    memory: "2Gi"
```

To adjust resources, modify [10_deploy.yaml](10_deploy.yaml:141-147) and redeploy.

### Cluster Mode

Currently deployed in single-replica mode for homelab use. To enable clustering:

1. Edit [10_deploy.yaml](10_deploy.yaml:136-138)
2. Set `cluster.enabled: true` and `cluster.replicas: 3`
3. Redeploy

**Note**: Clustering requires 3 replicas minimum for RAFT consensus.

## Usage

### Basic Pub/Sub Example

From within the cluster using nats-box:

```bash
# Subscribe to a subject
kubectl exec -n nats nats-box-0 -- nats sub test.subject

# Publish a message (from another terminal)
kubectl exec -n nats nats-box-0 -- nats pub test.subject "Hello World"
```

### JetStream Example

Create a stream:
```bash
kubectl exec -n nats nats-box-0 -- nats stream add MY_STREAM \
  --subjects="events.>" \
  --storage=file \
  --replicas=1
```

Publish to stream:
```bash
kubectl exec -n nats nats-box-0 -- nats pub events.user.login '{"user":"alice"}'
```

Create consumer:
```bash
kubectl exec -n nats nats-box-0 -- nats consumer add MY_STREAM MY_CONSUMER \
  --filter="events.user.>" \
  --deliver=all
```

### Python Client Example (from JupyterHub)

```python
# Install NATS client in notebook
!pip install nats-py

import asyncio
from nats.aio.client import Client as NATS

async def main():
    # Connect to NATS (internal cluster endpoint)
    nc = await NATS().connect("nats://nats.nats.svc.cluster.local:4222")

    # Simple pub/sub
    async def message_handler(msg):
        print(f"Received: {msg.data.decode()}")

    await nc.subscribe("ai.inference.response", cb=message_handler)
    await nc.publish("ai.inference.request", b'{"model":"gpt-4"}')

    # JetStream
    js = nc.jetstream()
    await js.publish("events.user.login", b'{"user":"alice"}')

    # Keep connection alive
    await asyncio.sleep(5)
    await nc.close()

# Run in notebook
await main()
```

### External Client Connection

From outside the cluster (using external TCP endpoint):

```python
import asyncio
from nats.aio.client import Client as NATS

async def main():
    # Connect via external TCP passthrough
    nc = await NATS().connect("nats://nats.example.com:4222")

    await nc.publish("test", b"Hello from outside!")
    await nc.close()

asyncio.run(main())
```

## Integration

### Agent Coordination

Enable real-time communication between AI agents:

```python
# Agent 1 publishes task
await nc.publish("agents.tasks", b'{"task":"analyze","data":"..."}')

# Agent 2 subscribes to tasks
async def process_task(msg):
    task = json.loads(msg.data)
    # Process task...
    await msg.respond(b'{"status":"completed"}')

await nc.subscribe("agents.tasks", cb=process_task)
```

### LLM Observability (Langfuse Integration)

Stream LLM traces to Langfuse via NATS:

```python
# Publish LLM events to NATS
await nc.publish("llm.traces", langfuse_trace_json.encode())

# Langfuse subscriber processes traces
async def handle_trace(msg):
    trace = json.loads(msg.data)
    langfuse.ingest(trace)

await nc.subscribe("llm.traces", cb=handle_trace)
```

### Real-time Model Updates (MLflow Integration)

Notify services when MLflow registers new models:

```python
# Publish from MLflow webhook handler
await nc.publish("mlflow.model.registered", json.dumps({
    "model_name": "my-model",
    "version": "1.2.0",
    "stage": "production"
}).encode())

# Subscribers react to new models
async def handle_model_update(msg):
    model_info = json.loads(msg.data)
    # Reload model, update configs, etc.

await nc.subscribe("mlflow.model.registered", cb=handle_model_update)
```

### Multi-Agent Systems

Agents communicate via NATS topics:

```python
# Agent publishes to shared chat
await nc.publish("agents.chat", json.dumps({
    "agent_id": "planner",
    "message": "What data sources should we query?",
    "timestamp": time.time()
}).encode())

# Other agents listen and respond
async def handle_agent_message(msg):
    message = json.loads(msg.data)
    if needs_response(message):
        await nc.publish("agents.chat", response.encode())

await nc.subscribe("agents.chat", cb=handle_agent_message)
```

## Monitoring

### Health Checks

External (HTTPS):
```bash
curl https://nats.example.com/healthz
```

Internal (HTTP):
```bash
kubectl exec -n nats nats-box-0 -- curl http://nats:8222/healthz
```

### Monitoring Endpoints

Server variables and stats:
```bash
curl https://nats.example.com/varz
```

Connection info:
```bash
curl https://nats.example.com/connz
```

JetStream info:
```bash
kubectl exec -n nats nats-0 -- nats account info
```

Cluster status (if clustering enabled):
```bash
kubectl exec -n nats nats-0 -- nats server info
```

## Troubleshooting

### Verify Deployment Status

Check pod status:
```bash
kubectl get pods -n nats
kubectl describe pod nats-0 -n nats
```

Check StatefulSet:
```bash
kubectl get statefulset nats -n nats
```

### View Logs

NATS server logs:
```bash
kubectl logs -n nats nats-0 -f
```

nats-box logs (if debugging):
```bash
kubectl logs -n nats nats-box-0 -f
```

### Test Connectivity

Test internal connectivity:
```bash
kubectl run -i --rm --restart=Never nats-test \
  --image=nats:2.12.0-alpine \
  --namespace=nats \
  -- nats pub test "hello" --server=nats://nats:4222
```

Test external TCP passthrough:
```bash
# From local machine with nats CLI installed
nats pub test "hello" --server=nats://nats.example.com:4222
```

### Check JetStream Storage

View JetStream storage usage:
```bash
kubectl exec -n nats nats-0 -- df -h /data
```

List streams:
```bash
kubectl exec -n nats nats-0 -- nats stream ls
```

Stream info:
```bash
kubectl exec -n nats nats-0 -- nats stream info MY_STREAM
```

### Verify TCP Passthrough Configuration

Check Ingress ConfigMap:
```bash
kubectl get configmap primary-ingress-ingress-nginx-tcp -n ingress -o yaml
```

Should include:
```yaml
data:
  "4222": "nats/nats:4222"
```

### Common Issues

**Issue**: Cannot connect to external TCP endpoint
- **Solution**: Verify TCP passthrough is configured in Ingress ConfigMap
- **Solution**: Check firewall allows port 4222 traffic

**Issue**: JetStream storage full
- **Solution**: Increase PVC size or implement stream retention policies
```bash
kubectl exec -n nats nats-0 -- nats stream edit MY_STREAM --max-bytes 1GB
```

**Issue**: Pod stuck in Pending
- **Solution**: Check PVC status. JetStream requires persistent storage.
```bash
kubectl get pvc -n nats
```

**Issue**: High memory usage
- **Solution**: JetStream caches messages in memory. Adjust resource limits or configure stream memory limits.

**Issue**: Connection refused from external clients
- **Solution**: Verify Ingress Service has port 4222 exposed
```bash
kubectl get service -n ingress primary-ingress-ingress-nginx-controller -o yaml | grep 4222
```

## Testing

The test playbook [18_test.yaml](18_test.yaml) verifies:
- NATS pod is running
- JetStream is enabled and healthy
- Monitoring endpoint is accessible
- Can publish and subscribe to messages
- Stream creation and message persistence

## Rollback

To uninstall NATS:

```bash
cd ~/thinkube
./scripts/tk_ansible ansible/40_thinkube/optional/nats/19_rollback.yaml
```

**Warning**: This will delete all JetStream streams, consumers, and messages. Backup important data before uninstalling.

## Performance

- **Throughput**: Millions of messages per second (hardware-dependent)
- **Latency**: Sub-millisecond delivery for pub/sub
- **JetStream**: At-least-once delivery guarantees
- **Scalability**: Horizontal scaling via clustering (3+ replicas)
- **Persistence**: File-based storage with AOF-like durability

## Security Considerations

**Current Configuration**: No authentication (internal cluster use only)

**For Production**:
1. Enable TLS encryption for client connections
2. Configure user authentication with nkeys or JWT
3. Implement authorization with accounts and permissions
4. Restrict external TCP access to authorized clients only
5. Use NetworkPolicies to limit namespace access

## Use Cases

### Real-time AI Pipelines
- Stream data preprocessing between services
- Model inference queues with JetStream
- Result aggregation and distribution

### Agent Systems
- Multi-agent coordination and communication
- Message passing between autonomous agents
- Task distribution and load balancing

### Event-Driven ML
- Model retraining triggers on data drift
- Performance monitoring alerts
- Automated deployment notifications

### Microservices Communication
- Service-to-service messaging
- Event sourcing for ML pipelines
- CQRS patterns for data workflows

## References

- [NATS Official Documentation](https://docs.nats.io/)
- [JetStream Guide](https://docs.nats.io/nats-concepts/jetstream)
- [NATS Kubernetes Operator](https://github.com/nats-io/k8s)
- [Python Client (nats-py)](https://github.com/nats-io/nats.py)
- [NATS CLI](https://github.com/nats-io/natscli)

🤖 [AI-assisted]
