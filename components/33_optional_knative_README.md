# Knative

## Overview

Knative provides serverless capabilities for Kubernetes, enabling automatic scaling, event-driven architectures, and simplified deployment of containerless workloads. Deployed with Knative Serving for serverless containers, Knative Eventing for event-driven applications, and Kourier as a lightweight ingress controller.

**Key Features**:
- **Knative Serving**: Deploy and manage serverless workloads with automatic scaling
- **Knative Eventing**: Event-driven architecture support with channels, brokers, and triggers
- **Kourier Ingress**: Lightweight ingress controller optimized for Knative
- **Scale-to-Zero**: Automatically scale pods to zero when idle
- **Autoscaling**: Horizontal pod autoscaling based on request metrics
- **HTTPS by Default**: TLS termination with wildcard certificates
- **Harbor Integration**: Private container registry support with authentication

## Dependencies

**Core Components** (always available):
- Kubernetes (#1) - k8s-snap 1.34.0
- Ingress (#7) - NGINX Ingress Controller (secondary ingress for Knative)
- Cert-manager (#8) - Wildcard TLS certificates
- CoreDNS (#1) - DNS resolution for internal services
- Harbor (#14) - Container registry for custom images

**Optional Components**:
- None (Knative is a foundational infrastructure service)

## Prerequisites

```yaml
requirements:
  kubernetes:
    version: "1.34.0"
    provider: "k8s-snap"

  knative_versions:
    serving: "1.17.0"
    eventing: "1.17.1"
    kourier: "1.17.0"

  networking:
    domain_suffix: "kn.example.com"
    ingress_class: "nginx-kn"
    secondary_ingress: true
    https_default: true

  resources:
    controller:
      replicas: 1
    webhook:
      replicas: 1
    autoscaler:
      replicas: 1
    activator:
      replicas: 1

  harbor:
    robot_account: "kaniko"
    authentication: required
```

## Playbooks

### **Main Deployment**
**File**: [10_deploy.yaml](10_deploy.yaml)

Comprehensive 9-phase deployment of Knative with extensive configuration:

#### **Phase 1: Prepare Environment**

- **Namespace Stuck Detection**
  - Checks for namespaces stuck in Terminating state
  - Force deletes stuck namespaces by removing finalizers
  - Uses kubectl proxy to finalize namespace deletion via API

- **Namespace Creation**
  - Creates `knative-serving` namespace (Knative Serving components)
  - Creates `knative-eventing` namespace (Knative Eventing components)
  - Creates `kourier-system` namespace (Kourier ingress controller)
  - Creates `kn` namespace (sample services and user workloads)

- **TLS Certificate Setup**
  - Retrieves wildcard certificate from `default` namespace
  - Copies certificate to secondary ingress namespace
  - Creates TLS secret for Knative services
  - Restarts secondary ingress controller to apply certificate

#### **Phase 2: Install Knative Components**

- **Knative Serving Installation**
  - Downloads and applies Knative Serving CRDs v1.17.0
  - Downloads and applies Knative Serving core components v1.17.0
  - Components: controller, webhook, autoscaler, activator, domain-mapping

- **Kourier Installation**
  - Downloads and applies Kourier v1.17.0 manifests
  - Deploys 3scale-kourier-gateway (ingress gateway)
  - Deploys net-kourier-controller (Knative integration)

- **RBAC Configuration**
  - Creates ClusterRoleBinding `kourier-ingress-binding`
  - Grants Kourier ServiceAccount cluster-admin permissions
  - **Note**: Uses cluster-admin for simplicity; restrict in production

#### **Phase 3: Configure Knative Components**

- **Kourier ConfigMap**
  - Creates `config-kourier` in `knative-serving` namespace
  - Sets ingress class: `kourier.ingress.networking.knative.dev`
  - Configures TLS certificate namespace and secret name

- **Webhook Readiness Handling**
  - Waits up to 120 seconds for webhook deployment to be ready
  - Monitors webhook pod availability
  - Emergency fix: Changes failurePolicy from Fail to Ignore if webhook doesn't become ready
  - Allows playbook to continue even if webhook is slow to start

- **Network Configuration**
  - Updates `config-network` ConfigMap with multiple settings:
    - Ingress class: `kourier.ingress.networking.knative.dev`
    - Default external scheme: `https`
    - Mesh compatibility mode: `disabled` (critical for proper DNS resolution)
    - Mesh pod addressability: `false`
    - Path pattern matching: `enabled`
    - Service IP range: `10.152.183.0/24`
    - Registry hostname entries for Harbor access
  - Falls back to kubectl apply if Kubernetes module fails

- **Cleanup Conflicting Resources**
  - Removes any pre-existing `kourier-ingress` Ingress resources
  - Prevents conflicts with new ingress configuration

#### **Phase 4: Setup TLS and Ingress**

- **Kourier-System TLS Secret**
  - Checks for existing TLS secret in `kourier-system`
  - Deletes old secret if exists (ensures fresh certificate)
  - Copies wildcard certificate to `kourier-system` namespace

- **Wildcard Ingress for Knative Services**
  - Creates `knative-wildcard-ingress` in `kourier-system`
  - Host pattern: `*.kn.example.com`
  - Backend: Kourier service on port 80
  - Annotations:
    - SSL redirect enabled
    - Proxy body size unlimited (for large requests)
    - Proxy timeouts: 3600s (1 hour for long-running requests)
  - TLS termination with wildcard certificate

- **Direct Ingress for Kourier**
  - Creates `knative-direct-ingress` for direct Kourier access
  - Path rewrite: `/$2` (strips prefix)
  - Preserves host headers
  - Upstream hash by request URI (consistent routing)

#### **Phase 5: Configure Domain Mapping and Network**

- **Kourier Service Configuration**
  - Patches Kourier service with `externalTrafficPolicy: Local`
  - Ensures traffic routes correctly from external sources

- **Network ConfigMap Re-application**
  - Re-applies `config-network` to ensure consistency
  - Critical settings enforced again after other components start

- **Domain Mapping Configuration**
  - Creates `config-domain` ConfigMap
  - Maps `kn.example.com` domain to Knative services
  - Empty string value means "default domain"

#### **Phase 6: Restart Controllers**

- **Controller Restarts**
  - Restarts `controller` deployment (processes Service CRDs)
  - Restarts `net-kourier-controller` (manages Kourier configuration)
  - Waits for both deployments to become Available (60s timeout)

- **Deployment Readiness Checks**
  - Waits for all Knative deployments to be ready:
    - `controller` - Main Knative Serving controller
    - `webhook` - Admission webhook for validation
    - `autoscaler` - Horizontal pod autoscaler
    - `activator` - Request proxy for scaled-to-zero pods
    - `net-kourier-controller` - Kourier integration

- **Autoscaler WebSocket Service (Internal)**
  - Creates `autoscaler-websocket-internal` service
  - Exposes port 8080 (WebSocket) and 9090 (metrics)
  - Used by activator for autoscaling metrics

- **Autoscaler Service Fix**
  - Creates/updates `autoscaler` service
  - Annotation: `networking.knative.dev/disableSelection: "true"`
  - Prevents Knative from modifying service selectors

- **Deployment Configuration**
  - Creates `config-deployment` ConfigMap
  - Sets `autoscaler.useServiceHost: "true"`
  - Ensures pods use service DNS names for autoscaler

- **Service IP Discovery**
  - Retrieves ClusterIP for `autoscaler-websocket-internal`
  - Retrieves ClusterIP for `kourier` (external)
  - Retrieves ClusterIP for `kourier-internal`

- **Activator Host Aliases**
  - Patches `activator` deployment with hostAliases
  - Maps autoscaler internal IP to DNS names:
    - `autoscaler.knative-serving.svc.cluster.local`
    - `autoscaler-websocket.knative-serving.svc.cluster.local`
    - `autoscaler-websocket-internal.knative-serving.svc.cluster.local`
  - **Critical**: Fixes DNS resolution issues in activator pods

- **Activator Restart**
  - Restarts `activator` deployment to apply host aliases
  - Waits for deployment to become Available (60s timeout)

#### **Phase 7: Install Knative Eventing**

- **Eventing CRDs**
  - Downloads and applies Knative Eventing CRDs v1.17.1

- **Eventing Core Components**
  - Downloads and applies Knative Eventing core v1.17.1
  - Components: eventing-controller, eventing-webhook, imc-controller, imc-dispatcher

- **Autoscaler WebSocket Service (Public)**
  - Creates `autoscaler-websocket` service (in addition to internal)
  - Exposes WebSocket (8080) and metrics (9090) ports
  - Used by external monitoring and debugging

#### **Phase 8: Apply Additional ConfigMaps**

- **Domain Configuration**
  - Applies `config-domain` ConfigMap with domain mapping
  - Sets `kn.example.com` as default domain for all services

- **Feature Flags**
  - Creates `config-features` ConfigMap:
    - `kubernetes.podspec-dnsconfig: enabled`
    - `kubernetes.podspec-dnspolicy: enabled`
    - `kubernetes.podspec-hostaliases: enabled`
  - Allows advanced pod DNS configuration

- **Autoscaler Configuration**
  - Creates `config-autoscaler` ConfigMap with tuned settings:
    - Container concurrency target: 100 requests per pod
    - Concurrency target percentage: 70% of capacity
    - Scale-to-zero: enabled
    - Max scale-up rate: 1000x per minute
    - Max scale-down rate: 2x per minute
    - Panic window: 10% of stable window
    - Panic threshold: 200% of target concurrency
    - Scale-to-zero grace period: 30s
    - Scale-to-zero retention: 0s (immediate)
    - Stable window: 60s
    - Target burst capacity: 200 requests
    - Requests per second target: 200 RPS

#### **Phase 9: Deploy and Test Sample Service**

- **Service Cleanup**
  - Deletes previous `helloworld-python` service if exists
  - Waits 5 seconds for cleanup to complete

- **Global Domain Configuration Fix**
  - Deletes existing test service to avoid conflicts
  - Patches Kourier service selector to correct gateway pod
  - Re-applies `config-domain` with precise domain mapping
  - Fixes `config-network` with domain template: `{{.Name}}.{{.Domain}}`
  - Sets `auto-tls: disabled` (using wildcard cert instead)
  - Restarts all critical deployments to apply changes
  - Verifies DNS resolution with busybox test pod

- **Harbor Registry Authentication**
  - Loads `HARBOR_ROBOT_TOKEN` from `~/.env` file
  - Creates `harbor-registry-secret` in `kn` namespace
  - Type: `kubernetes.io/dockerconfigjson`
  - Username: `robot$kaniko`
  - Fails deployment if token not available

- **Sample Service Deployment**
  - Creates Knative Service `helloworld-python` in `kn` namespace
  - **Image**: `python:3.12-slim` (ARM64 and x86_64 compatible)
  - **Custom Python HTTP Server**:
    - Listens on port 8080
    - Returns "Hello from Knative!" (from TARGET env var)
    - Suppresses HTTP logs for cleaner output
  - **Autoscaling Annotations**:
    - `autoscaling.knative.dev/min-scale: "1"` (prevents cold starts)
    - `autoscaling.knative.dev/max-scale: "1"` (single replica for testing)
  - **Readiness Probe**:
    - HTTP GET on port 8080
    - Initial delay: 0s
    - Period: 3s
  - **Ingress Annotation**: `networking.knative.dev/ingress.class: kourier.ingress.networking.knative.dev`
  - Waits up to 90s for service to become Ready

- **Service Readiness Verification**
  - Polls service status for up to 300 seconds (10 attempts × 30s)
  - Checks for `condition=Ready=True`
  - Lists pods if service not ready
  - Always succeeds to allow troubleshooting

- **Service Status Check**
  - Displays pod status (wide output)
  - Displays Knative Service status
  - Extracts Ready condition from service
  - Counts running pods
  - Considers service ready if either:
    - Ready status is True, OR
    - At least one pod is Running

- **Sample Service URL**
  - Sets fact: `https://helloworld-python.kn.example.com`

### **Service Discovery**
**File**: [17_configure_discovery.yaml](17_configure_discovery.yaml)

Registers Knative with Thinkube service discovery system:

- **ConfigMap Creation** (`thinkube-service-config` in `knative-serving` namespace)
  - Service type: `optional`
  - Category: `devops`
  - Icon: `/icons/tk_devops.svg`
  - Component version: `0.1.0` (from VERSION file)

- **Endpoints Registered**:
  - Primary: Controller metrics at `http://controller.knative-serving.svc.cluster.local:9090` (health: `/metrics`)
  - Secondary: Webhook service at `http://webhook.knative-serving.svc.cluster.local:9090` (health: `/metrics`)

- **Scaling Configuration**:
  - Resource type: Deployment `controller`
  - Namespace: `knative-serving`
  - Min replicas: 1
  - Can disable: true

- **Code-Server Integration**
  - Updates code-server environment variables via `code_server_env_update` role

## Deployment

This component is automatically deployed via the **thinkube-control Optional Components interface**:

1. Navigate to https://thinkube.example.com/optional-components
2. Locate the **Knative** card in the **Infrastructure** section
3. Click **Install** to deploy the component
4. Monitor real-time deployment progress via WebSocket streaming
5. Verify deployment status in the dashboard

The deployment executes the orchestrator playbook at `/ansible/40_thinkube/optional/knative/00_install.yaml`.

**Deployment Sequence**:
1. Prepare environment (namespace cleanup, TLS setup)
2. Install Knative Serving and Kourier
3. Configure network and domain mapping
4. Setup TLS and wildcard ingress
5. Configure autoscaler and fix DNS resolution
6. Install Knative Eventing
7. Apply autoscaling and feature configurations
8. Deploy sample service for validation
9. Register with service discovery

**Important**: Ensure `HARBOR_ROBOT_TOKEN` is set in `~/.env` before deployment for registry authentication.

## Access Points

Knative services are accessed via wildcard domain:

### Sample Service

After deployment, test the sample service:

```
https://helloworld-python.kn.example.com
```

Should return: `Hello from Knative!`

### Custom Services

Deploy your own Knative services:

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: my-service
  namespace: kn
spec:
  template:
    spec:
      containers:
      - image: gcr.io/knative-samples/helloworld-go
        env:
        - name: TARGET
          value: "World"
```

Accessible at: `https://my-service.kn.example.com`

### Internal Access

Knative services can be accessed from within the cluster using cluster-local domains:

```
http://my-service.kn.svc.cluster.local
```

## Configuration

### Domain Mapping

Knative services use the domain suffix `kn.example.com` by default. To change:

Edit [10_deploy.yaml](10_deploy.yaml:54) and modify:
```yaml
kn_subdomain: "kn"  # Change to desired subdomain
```

### Autoscaling Settings

Autoscaling is configured via annotations on Knative Service:

```yaml
metadata:
  annotations:
    autoscaling.knative.dev/min-scale: "0"  # Scale to zero when idle
    autoscaling.knative.dev/max-scale: "10" # Maximum 10 replicas
    autoscaling.knative.dev/target: "100"   # Target 100 concurrent requests per pod
```

Global autoscaling settings in `config-autoscaler` ConfigMap:

```bash
kubectl edit configmap config-autoscaler -n knative-serving
```

Key settings:
- `container-concurrency-target-default: "100"` - Target requests per pod
- `enable-scale-to-zero: "true"` - Allow scaling to zero
- `scale-to-zero-grace-period: "30s"` - Wait time before scaling to zero
- `stable-window: "60s"` - Metrics window for scaling decisions
- `requests-per-second-target-default: "200"` - Target RPS per pod

### Resource Limits

Set resource limits on Knative Service:

```yaml
spec:
  template:
    spec:
      containers:
      - image: my-image
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "1"
            memory: "512Mi"
```

### TLS/HTTPS

All Knative services use HTTPS by default via wildcard certificate. To disable:

Edit `config-network` ConfigMap:
```bash
kubectl edit configmap config-network -n knative-serving
```

Change:
```yaml
default-external-scheme: "http"
```

### Harbor Registry Integration

For private images from Harbor:

1. Create Harbor robot account secret:
```bash
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.example.com \
  --docker-username=robot\$account \
  --docker-password=<token> \
  -n kn
```

2. Reference in Knative Service:
```yaml
spec:
  template:
    spec:
      imagePullSecrets:
      - name: harbor-secret
      containers:
      - image: harbor.example.com/library/my-app:latest
```

## Usage

### Deploy a Knative Service

Create a file `service.yaml`:

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello
  namespace: kn
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/min-scale: "1"
    spec:
      containers:
      - image: gcr.io/knative-samples/helloworld-go
        ports:
        - containerPort: 8080
        env:
        - name: TARGET
          value: "Knative"
```

Deploy:
```bash
kubectl apply -f service.yaml
```

Access:
```bash
curl https://hello.kn.example.com
```

### Check Service Status

```bash
# List all Knative services
kubectl get ksvc -n kn

# Get service details
kubectl get ksvc hello -n kn -o yaml

# Check service ready condition
kubectl get ksvc hello -n kn -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# List revisions
kubectl get revisions -n kn

# List routes
kubectl get routes -n kn
```

### View Logs

```bash
# Get pod name
kubectl get pods -n kn -l serving.knative.dev/service=hello

# View logs
kubectl logs -n kn <pod-name> -c user-container
```

### Update Service

Knative creates a new revision for each update:

```bash
# Update image
kubectl patch ksvc hello -n kn --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"gcr.io/knative-samples/helloworld-go:v2"}]'

# Update environment variable
kubectl patch ksvc hello -n kn --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/value","value":"New Value"}]'
```

### Traffic Splitting

Route traffic between revisions:

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello
  namespace: kn
spec:
  traffic:
  - revisionName: hello-00001
    percent: 90
  - revisionName: hello-00002
    percent: 10
```

### Scale to Zero Testing

Knative scales to zero after idle period:

```bash
# Watch pods
watch kubectl get pods -n kn

# Make a request (pod will start)
curl https://hello.kn.example.com

# Wait ~30 seconds, pod scales to zero

# Make another request (pod restarts)
curl https://hello.kn.example.com
```

## Integration

### With NATS Messaging

Use Knative Eventing to consume NATS messages:

```yaml
apiVersion: eventing.knative.dev/v1
kind: Broker
metadata:
  name: default
  namespace: kn
spec:
  config:
    apiVersion: v1
    kind: ConfigMap
    name: config-br-defaults
```

### With MLflow

Deploy MLflow models as serverless endpoints:

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: mlflow-model
  namespace: kn
spec:
  template:
    spec:
      containers:
      - image: harbor.example.com/library/mlflow-model:latest
        ports:
        - containerPort: 5000
```

Access: `https://mlflow-model.kn.example.com/invocations`

### With JupyterHub

Deploy models from notebooks:

```python
# In JupyterHub notebook
import subprocess

# Create Knative Service from Python
service_yaml = """
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: notebook-model
  namespace: kn
spec:
  template:
    spec:
      containers:
      - image: my-model:latest
"""

with open('/tmp/service.yaml', 'w') as f:
    f.write(service_yaml)

subprocess.run(['kubectl', 'apply', '-f', '/tmp/service.yaml'])
```

## Monitoring

### Check Knative Controller Status

```bash
kubectl get deployment -n knative-serving
kubectl get pods -n knative-serving
```

### Check Kourier Status

```bash
kubectl get deployment -n kourier-system
kubectl get pods -n kourier-system
kubectl get svc kourier -n kourier-system
```

### View Metrics

Knative exposes Prometheus metrics:

```bash
# Controller metrics
kubectl port-forward -n knative-serving svc/controller 9090:9090
curl http://localhost:9090/metrics

# Autoscaler metrics
kubectl port-forward -n knative-serving svc/autoscaler 9090:9090
curl http://localhost:9090/metrics
```

### Check Autoscaler Decisions

```bash
# View autoscaler logs
kubectl logs -n knative-serving -l app=autoscaler -f

# View activator logs
kubectl logs -n knative-serving -l app=activator -f
```

## Troubleshooting

### Verify Deployment Components

Check all Knative Serving deployments:
```bash
kubectl get deployments -n knative-serving
```

Should show:
- controller
- webhook
- autoscaler
- activator
- net-kourier-controller

Check Kourier:
```bash
kubectl get deployments -n kourier-system
kubectl get svc kourier -n kourier-system
```

### Service Not Accessible Externally

Check ingress:
```bash
kubectl get ingress -n kourier-system
```

Verify TLS secret:
```bash
kubectl get secret -n kourier-system | grep tls
```

Test DNS resolution:
```bash
nslookup helloworld-python.kn.example.com
```

### Service Stuck in Not Ready

Check pod status:
```bash
kubectl get pods -n kn -l serving.knative.dev/service=<service-name>
kubectl describe pod -n kn <pod-name>
```

Check service events:
```bash
kubectl describe ksvc <service-name> -n kn
```

Common issues:
- Image pull errors: Check Harbor credentials
- Readiness probe failures: Check port and path
- Resource limits: Increase CPU/memory

### Webhook Not Ready

If deployment hangs on webhook:

```bash
# Check webhook status
kubectl get deployment webhook -n knative-serving
kubectl logs -n knative-serving -l app=webhook

# Emergency fix (applied by playbook)
kubectl get ValidatingWebhookConfiguration config.webhook.serving.knative.dev -o yaml
# Change failurePolicy: Fail to failurePolicy: Ignore
```

### Autoscaler Issues

Check autoscaler connectivity:

```bash
# Verify autoscaler service
kubectl get svc autoscaler -n knative-serving
kubectl get svc autoscaler-websocket-internal -n knative-serving

# Test from activator pod
kubectl exec -n knative-serving -it <activator-pod> -- \
  wget -O- http://autoscaler.knative-serving.svc.cluster.local:8080/metrics
```

If connection fails, check host aliases in activator deployment:
```bash
kubectl get deployment activator -n knative-serving -o yaml | grep -A10 hostAliases
```

### DNS Resolution Issues

Test DNS from within cluster:

```bash
kubectl run dns-test --image=busybox:1.28 --rm -it --restart=Never -- \
  nslookup kourier.kourier-system.svc.cluster.local
```

Check CoreDNS:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### Harbor Authentication Failures

Verify HARBOR_ROBOT_TOKEN:
```bash
source ~/.env
echo $HARBOR_ROBOT_TOKEN
```

Check secret in namespace:
```bash
kubectl get secret harbor-registry-secret -n kn -o yaml
```

Test image pull:
```bash
kubectl run test --image=harbor.example.com/library/test:latest -n kn --dry-run=client
```

### Service Scales to Zero Too Quickly

Adjust grace period:

```bash
kubectl edit configmap config-autoscaler -n knative-serving
```

Increase:
```yaml
scale-to-zero-grace-period: "60s"  # Default: 30s
```

Or set min-scale on service:
```yaml
metadata:
  annotations:
    autoscaling.knative.dev/min-scale: "1"
```

### Cold Start Latency

For services that need fast response:

1. Set min-scale to 1 (no cold starts)
2. Reduce scale-to-zero grace period
3. Use smaller container images
4. Optimize container startup time

### Common Issues Summary

**Issue**: Service returns 503
- **Solution**: Check if pods are running. May be scaling from zero.

**Issue**: Cannot access service externally
- **Solution**: Verify wildcard ingress and DNS pointing to secondary ingress IP

**Issue**: Service stuck in "Unknown" state
- **Solution**: Check revision status, pod events, and image pull status

**Issue**: Webhook validation errors
- **Solution**: Deployment handles this automatically by changing failurePolicy to Ignore

**Issue**: Autoscaler cannot connect to activator
- **Solution**: Deployment configures host aliases automatically

## Testing

The test playbook [18_test.yaml](18_test.yaml) verifies:
- All Knative components are healthy
- DNS resolution works correctly
- Internal connectivity via ClusterIP
- External connectivity via Ingress
- Autoscaling functionality
- TLS/HTTPS configuration
- Sample service responds correctly

## Rollback

To uninstall Knative:

```bash
cd ~/thinkube
./scripts/tk_ansible ansible/40_thinkube/optional/knative/19_rollback.yaml
```

**Warning**: This will delete all Knative services and configurations. Services deployed in the `kn` namespace will be removed.

## Architecture Notes

### Kourier vs Istio

Knative supports multiple ingress controllers. This deployment uses Kourier because:
- Lightweight (lower resource usage)
- Simpler configuration
- No service mesh overhead
- Sufficient for homelab use

### Mesh Compatibility Mode

Set to `disabled` because:
- Not using service mesh (Istio/Linkerd)
- Simplifies DNS resolution
- Reduces network complexity
- Improves performance

### Scale-to-Zero Implementation

Knative scale-to-zero works via:
1. **Autoscaler** monitors request metrics
2. After idle period (30s default), scales deployment to 0
3. **Activator** intercepts requests when pods are scaled to zero
4. Activator buffers requests and triggers scale-up
5. Once pods are ready, activator forwards buffered requests
6. Subsequent requests go directly to pods (activator is bypassed)

### ARM64 Compatibility

Sample service uses `python:3.12-slim` which supports both ARM64 and x86_64. When deploying custom services, ensure images support target architecture.

## Performance Considerations

- **Cold Start**: ~2-5 seconds for simple Python services
- **Warm Start**: <100ms when pods are already running
- **Autoscaling Response**: 60s stable window for scale decisions
- **Scale-to-Zero Delay**: 30s grace period after last request
- **Concurrent Requests**: Default target of 100 requests per pod

## Security Considerations

**Current Configuration**:
- TLS enabled for all external traffic
- Harbor registry authentication required
- Kourier has cluster-admin permissions (simplifies deployment)

**For Production**:
1. Restrict Kourier RBAC permissions to minimal required
2. Enable Knative authentication (e.g., OAuth2 Proxy)
3. Implement NetworkPolicies for namespace isolation
4. Use Pod Security Standards
5. Enable audit logging for Knative API calls

## References

- [Knative Official Documentation](https://knative.dev/docs/)
- [Knative Serving Concepts](https://knative.dev/docs/serving/)
- [Knative Eventing Guide](https://knative.dev/docs/eventing/)
- [Kourier Documentation](https://github.com/knative/net-kourier)
- [Knative Autoscaling](https://knative.dev/docs/serving/autoscaling/)
- [Knative Samples](https://github.com/knative/docs/tree/main/code-samples)

🤖 [AI-assisted]
