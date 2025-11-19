# Argo Workflows & Argo Events

This component deploys [Argo Workflows](https://argoproj.github.io/workflows/) and [Argo Events](https://argoproj.github.io/events/) for workflow orchestration and event-driven automation in the Thinkube platform.

## Overview

Argo Workflows is a container-native workflow engine for orchestrating parallel jobs on Kubernetes. Argo Events is an event-driven workflow automation framework. Together they provide:

- **Workflow Orchestration**: DAG-based workflow definitions for complex multi-step processes
- **Event-Driven Automation**: React to events from Gitea webhooks and trigger workflows automatically
- **Artifact Storage**: Integration with SeaweedFS S3 for workflow artifacts and outputs
- **Keycloak SSO**: Centralized authentication for web UI access
- **CLI Access**: Command-line interface with token authentication for programmatic workflow management
- **gRPC API**: Separate gRPC endpoint for CLI/API access with TLS and HTTP/2

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster
- ingress (deployment order #13) - For web UI and gRPC API access
- acme-certificates (deployment order #12) - For TLS certificates
- keycloak (deployment order #15) - For SSO authentication on web UI
- seaweedfs (deployment order #21) - For artifact storage via S3 API

**Deployment order**: #23

## Prerequisites

**Required inventory variables** (example values shown):

```yaml
# Argo Workflows configuration
argo_namespace: argo
argo_domain: argo.example.com  # Replace with your domain
argo_grpc_domain: grpc-argo.example.com  # Replace with your domain
argo_oidc_client_id: argo
argo_release_name: argo-workflows
argo_chart_repo: https://argoproj.github.io/argo-helm
argo_chart_name: argo-workflows
argo_events_release_name: argo-events
argo_events_chart_name: argo-events
argo_service_type: ClusterIP

# Keycloak configuration (inherited)
keycloak_url: https://keycloak.example.com  # Replace with your domain
keycloak_realm: thinkube
admin_username: admin

# SeaweedFS configuration (inherited)
seaweedfs_namespace: seaweedfs
seaweedfs_s3_hostname: s3.example.com  # Replace with your domain

# Kubernetes configuration (inherited)
domain_name: example.com  # Replace with your domain
kubeconfig: /var/snap/k8s/common/etc/admin.conf
kubectl_bin: /snap/k8s/current/bin/kubectl
helm_bin: /snap/k8s/current/bin/helm
```

**Required environment variables**:
- `ADMIN_PASSWORD`: Keycloak admin password for OAuth2 client configuration and S3 access

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all Argo Workflows deployment playbooks in sequence:
- Imports 10_configure_keycloak.yaml - Configures Keycloak OAuth2 client
- Imports 11_deploy.yaml - Deploys Argo Workflows and Argo Events
- Imports 12_setup_token.yaml - Installs CLI and configures service account token
- Imports 13_setup_artifacts.yaml - Configures SeaweedFS S3 artifact storage
- Imports 15_configure_gitea_events.yaml - Configures Gitea webhook integration
- Imports 17_configure_discovery.yaml - Configures service discovery

### 10_configure_keycloak.yaml
Keycloak OAuth2 client configuration for Argo web UI authentication:

- **Keycloak Client Creation**:
  - Creates Argo OAuth2/OIDC client in Keycloak realm
  - Client ID: `argo`
  - Protocol: openid-connect
  - Enables standard flow (authorization code flow)
  - Disables direct access grants

- **Redirect URI Configuration**:
  - Configures redirect URIs: `https://argo.{{ domain_name }}/oauth2/callback`, `https://argo.{{ domain_name }}/*`
  - Sets web origins: `https://argo.{{ domain_name }}`

- **Client Mappers**:
  - Configures audience mapper for token validation
  - Maps client audience to `argo` for ID token and access token claims

### 11_deploy.yaml
Main deployment playbook for Argo Workflows and Argo Events:

- **Namespace Setup**:
  - Creates `argo` namespace
  - Copies wildcard TLS certificate from default namespace to argo namespace

- **Keycloak Integration**:
  - Retrieves Keycloak admin token for API access
  - Verifies Argo OAuth2 client exists in Keycloak
  - Updates client redirect URIs and web origins
  - Retrieves OAuth2 client secret from Keycloak API
  - Adds protocol mappers for username and email claims
  - Stores client secret in `argo-server-sso` Kubernetes secret

- **Argo Workflows Helm Deployment**:
  - Adds argo-helm Helm repository
  - Deploys Argo Workflows via Helm chart
  - Configures dual authentication modes: SSO (web UI) and client token (CLI)
  - Configures OIDC authentication with Keycloak issuer
  - Sets OIDC redirect URL, scopes (openid, profile, email)
  - Disables RBAC (using Keycloak for authorization)
  - Sets resource limits: server (500m CPU, 256Mi memory), controller (1000m CPU, 512Mi memory)
  - Service type: ClusterIP

- **Argo Events Helm Deployment**:
  - Deploys Argo Events for event-driven automation
  - Installs and keeps CRDs (EventBus, EventSource, Sensor)
  - Enables eventbus, eventsource, and sensor components
  - Sets controller resource limits (100m CPU, 128Mi memory)
  - Verifies CRDs are installed (eventbus, eventsources, sensors)

- **Web UI Ingress**:
  - Creates Ingress `argo-ingress` at `argo.{{ domain_name }}`
  - TLS enabled with wildcard certificate
  - SSL redirect annotation
  - Routes to argo-workflows-server service port 2746

- **gRPC API Ingress**:
  - Creates separate Ingress `argo-grpc-ingress` at `grpc-argo.{{ domain_name }}`
  - Backend protocol: GRPC with HTTP/2 enabled
  - TLS enabled with wildcard certificate
  - Routes to argo-workflows-server service port 2746
  - Used by Argo CLI for workflow management

### 12_setup_token.yaml
CLI installation and service account token configuration:

- **Argo CLI Installation**:
  - Downloads Argo CLI v3.6.2 binary (linux-amd64)
  - Decompresses gzip archive
  - Creates `~/.local/bin` directory
  - Installs binary to `~/.local/bin/argo` with executable permissions
  - Verifies CLI installation with version command

- **Service Account Token Secret**:
  - Creates `argo-workflows-server-sa-token` secret in argo namespace
  - Type: kubernetes.io/service-account-token
  - Annotated with service account: argo-workflows-server
  - Provides long-lived token for programmatic access

- **Token Verification**:
  - Retrieves service account token from secret
  - Tests connectivity to gRPC endpoint at `grpc-argo.{{ domain_name }}:443`
  - Verifies token authentication works via `argo version` command

### 13_setup_artifacts.yaml
SeaweedFS S3 artifact storage configuration:

- **SeaweedFS Integration**:
  - Verifies SeaweedFS filer StatefulSet is deployed and ready
  - Retrieves S3 credentials from `seaweedfs-s3-config` secret in seaweedfs namespace
  - Extracts access_key and secret_key for S3 authentication

- **Argo S3 Credentials Secret**:
  - Creates `argo-artifacts-s3` secret in argo namespace
  - Contains S3 accessKey and secretKey for artifact storage

- **Artifact Repository ConfigMap**:
  - Creates/updates `artifact-repositories` ConfigMap in argo namespace
  - Configures default artifact repository (default-v1):
    - S3 endpoint: `seaweedfs-filer.seaweedfs.svc.cluster.local:8333` (internal)
    - Bucket: `argo-artifacts`
    - Insecure: true (internal traffic, no TLS needed)
    - Force path style: true (required for SeaweedFS S3 compatibility)
    - Key format: `{{workflow.name}}/{{pod.name}}`
    - References argo-artifacts-s3 secret for credentials

- **S3 Bucket Creation**:
  - Gets SeaweedFS filer pod name
  - Executes `weed shell` command to create `argo-artifacts` bucket if not exists
  - Verifies bucket exists and is accessible

### 15_configure_gitea_events.yaml
Argo Events configuration for Gitea webhook integration and CI/CD automation:

- **EventBus Creation**:
  - Creates default EventBus in argo namespace
  - NATS streaming backend with 3 replicas
  - Token-based authentication
  - Waits for EventBus to be deployed and ready (checks Deployed condition)

- **Webhook Secret**:
  - Creates `gitea-webhook-secret` in argo namespace
  - Generates random 32-character secret for webhook authentication

- **Webhook EventSource**:
  - Creates `gitea-webhook` EventSource
  - Listens on port 12000 at endpoint `/gitea`
  - Accepts POST requests from Gitea
  - Validates webhook secret for authentication
  - Waits for EventSource deployment to be created and ready (checks readyReplicas)

- **Webhook Service**:
  - Creates `gitea-webhook-eventsource` Service
  - Exposes EventSource on port 12000 (TCP)
  - Selector matches EventSource pods (eventsource-name: gitea-webhook)

- **Webhook Ingress**:
  - Copies wildcard TLS certificate to argo namespace as `argo-events-tls-secret`
  - Creates Ingress `argo-events-webhook-ingress` at `argo-events.{{ domain_name }}/gitea`
  - HTTPS with cert-manager Let's Encrypt certificate
  - Backend protocol: HTTP
  - Routes to gitea-webhook-eventsource service port 12000

- **RBAC Configuration**:
  - Creates `argo-events-sensor-role` Role in argo namespace with permissions:
    - workflows, workflowtemplates, workflowtaskresults: get, list, create, watch, patch, update
    - pods, pods/log: get, list, watch
  - Creates `argo-events-sensor-rolebinding` RoleBinding granting role to default ServiceAccount
  - Creates `kaniko-builder-workflow-rolebinding` RoleBinding granting role to kaniko-builder ServiceAccount

- **Gitea Push Sensor**:
  - Creates `gitea-push` Sensor to trigger workflows on git push events
  - Dependencies: Subscribes to gitea-webhook EventSource, gitea event
  - Filters:
    - Header filter: X-Gitea-Event: push
    - Lua script filter: Skips events with only `.argocd-source-*.yaml` file changes
  - Trigger workflow template:
    - Creates workflow with generateName: `webhook-build-`
    - Runs on control plane node (nodeSelector matches inventory_hostname)
    - Uses default ServiceAccount
    - Workflow parameters: repo-url, repo-name, repo-org, webhook-timestamp
  - Workflow script (tk-service-discovery image):
    - Converts HTTPS URLs to SSH format for git operations
    - Extracts app name from repository name (removes `-deployment` suffix)
    - Searches for WorkflowTemplate with labels:
      - `app.kubernetes.io/name=$APP_NAME`
      - `app.kubernetes.io/part-of=thinkube`
      - `thinkube.io/trigger=webhook`
    - Creates workflow from matching template with repository parameters
    - Lists available templates if not found
  - Parameter bindings from webhook payload:
    - repo-url: body.repository.clone_url
    - repo-name: body.repository.name
    - repo-org: body.repository.owner.login
    - webhook-timestamp: context.time (when webhook received)

**Note**: This creates the Argo Events infrastructure for webhook reception. Gitea webhook configuration is handled separately by the Gitea component.

### 17_configure_discovery.yaml
Service discovery configuration:

- **Service Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in argo namespace
  - Labels: `thinkube.io/managed`, `thinkube.io/service-type: core`, `thinkube.io/service-name: argo-workflows`
  - Defines service metadata:
    - Display name: "Argo Workflows"
    - Description: "Workflow orchestration engine"
    - Category: devops
    - Icon: /icons/tk_devops.svg
  - Endpoint configuration:
    - Web UI: https://argo.{{ domain_name }}
    - Health check: https://argo.{{ domain_name }}/api/v1/version
  - Dependencies: seaweedfs
  - Scaling configuration: Deployment argo-workflows-server, minimum 1 replica
  - Environment variables: ARGO_SERVER, ARGO_NAMESPACE, ARGO_SECURE

## Deployment

Argo Workflows is automatically deployed by the Thinkube installer at deployment order #23. The installer executes the orchestrator playbook (00_install.yaml) which runs all required playbooks in sequence.

No manual intervention is required during installation.

## Access Points

- **Web UI**: https://argo.{{ domain_name }} (Keycloak SSO authentication)
- **gRPC API**: https://grpc-argo.{{ domain_name }} (Token authentication for CLI)
- **Webhook Endpoint**: https://argo-events.{{ domain_name }}/gitea (Gitea webhook receiver)

Replace `{{ domain_name }}` with your actual domain (e.g., example.com).

## Configuration

### CLI Authentication

The Argo CLI is installed at `~/.local/bin/argo` and configured for token-based authentication via the gRPC endpoint:

```bash
# List workflows
argo list -n argo

# Submit workflow
argo submit -n argo workflow.yaml

# Watch workflow execution
argo submit -n argo --watch workflow.yaml

# Get workflow logs
argo logs -n argo workflow-name

# Get workflow status
argo get -n argo workflow-name
```

The CLI connects to `grpc-argo.{{ domain_name }}:443` using the service account token for authentication.

### Artifact Storage

Workflows can store and retrieve artifacts using the configured S3 storage (SeaweedFS):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: artifact-example
  namespace: argo
spec:
  entrypoint: main
  templates:
  - name: main
    outputs:
      artifacts:
      - name: result
        path: /tmp/result.txt
        s3:
          key: "{{workflow.name}}/result.txt"
    container:
      image: alpine:latest
      command: [sh, -c]
      args: ["echo 'hello world' > /tmp/result.txt"]
```

Artifacts are automatically stored in the `argo-artifacts` bucket in SeaweedFS using the internal S3 endpoint.

### Event-Driven Workflows

Argo Events triggers workflows based on Gitea webhooks. When a git push event occurs in a Gitea repository:

1. Gitea sends webhook to `https://argo-events.{{ domain_name }}/gitea`
2. EventSource receives and validates the webhook with secret authentication
3. Sensor filters the event (skips commits with only `.argocd-source-*.yaml` changes)
4. Sensor creates a webhook-build workflow that finds the matching WorkflowTemplate
5. WorkflowTemplate executes the build/deployment process

Applications must deploy their WorkflowTemplates with proper labels for automatic triggering:
- `app.kubernetes.io/name`: Application name (extracted from repo name)
- `app.kubernetes.io/part-of`: thinkube
- `thinkube.io/trigger`: webhook

## Troubleshooting

### Check Argo Workflows pods
```bash
kubectl get pods -n argo
kubectl logs -n argo deploy/argo-workflows-server
kubectl logs -n argo deploy/argo-workflows-workflow-controller
```

### Verify OIDC configuration
```bash
# Check SSO secret
kubectl get secret -n argo argo-server-sso -o yaml

# Test web UI access (should redirect to Keycloak)
curl -I https://argo.example.com  # Replace with your domain
```

### Check artifact storage
```bash
# Verify S3 credentials secret exists
kubectl get secret -n argo argo-artifacts-s3

# Check artifact repository configuration
kubectl get configmap -n argo artifact-repositories -o yaml

# Verify argo-artifacts bucket exists in SeaweedFS
kubectl exec -n seaweedfs seaweedfs-filer-0 -- weed shell <<< "fs.ls /"
```

### Verify Argo Events
```bash
# Check EventBus
kubectl get eventbus -n argo

# Check EventSource
kubectl get eventsource -n argo
kubectl get pods -n argo -l eventsource-name=gitea-webhook

# Check Sensor
kubectl get sensor -n argo
kubectl get pods -n argo -l sensor-name=gitea-push

# Check webhook ingress
kubectl get ingress -n argo argo-events-webhook-ingress

# Test webhook endpoint
curl -I https://argo-events.example.com/gitea  # Replace with your domain
```

### Test CLI connectivity
```bash
# Verify CLI can connect to gRPC endpoint
argo version

# List workflows
argo list -n argo

# Check gRPC ingress
kubectl get ingress -n argo argo-grpc-ingress
```

### Monitor webhook-triggered workflows
```bash
# Watch for workflows created by webhooks
kubectl get workflows -n argo -l source=webhook -w

# Get logs from webhook adapter workflow
kubectl logs -n argo -l workflows.argoproj.io/workflow=webhook-build-<name>
```

## References

- [Argo Workflows Documentation](https://argoproj.github.io/workflows/)
- [Argo Events Documentation](https://argoproj.github.io/argo-events/)
- [Argo Helm Charts](https://github.com/argoproj/argo-helm)
