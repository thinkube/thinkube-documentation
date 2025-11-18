# Component Name

Brief one-sentence description of what this component does and its role in the Thinkube platform.

## Overview

Expanded description of the component:
- What it provides
- Why it's part of the platform
- Key features

## Dependencies

**Required components** (must be deployed first):
- component-name (deployment order #X) - Why it's needed
- component-name (deployment order #Y) - Why it's needed

**Required by** (which components depend on this):
- component-name - How they use this
- component-name - How they use this

See [Deployment Dependency Graph](https://github.com/thinkube/thinkube-documentation/blob/main/architecture/deployment-dependency-graph.md) for complete dependency tree.

## Prerequisites

### Environment Variables
- `VARIABLE_NAME` - Description and purpose
- `ADMIN_PASSWORD` - Required for authentication (if applicable)

### Configuration Variables
From `inventory/group_vars/k8s.yml`:
```yaml
variable_name: value  # Description
another_variable: value  # Description
```

### External Requirements
- Any tokens, credentials, or external services needed
- GPU requirements (if applicable)
- Storage requirements
- Network requirements

## Playbooks

### 00_install.yaml (or 10_deploy.yaml)
Main deployment playbook that:
- Step 1 description
- Step 2 description
- Step 3 description

### 15_configure_*.yaml (optional)
Post-deployment configuration playbooks (if any):
- What they configure
- When to run them

### 18_test.yaml
Comprehensive test playbook that verifies:
- Kubernetes resources are properly deployed
- Service availability and health endpoints
- Component-specific functionality
- Integration points with dependencies

### 19_rollback.yaml
Cleanup playbook that:
- Removes deployed resources
- Cleans up namespace
- Handles any component-specific cleanup
- May require confirmation flag for safety

## Deployment

### Step 1: Deploy Component

```bash
cd ~/thinkube
export ADMIN_PASSWORD="your-admin-password"  # If required
./scripts/run_ansible.sh ansible/40_thinkube/core/COMPONENT/00_install.yaml
```

### Step 2: Additional Configuration (if applicable)

```bash
./scripts/run_ansible.sh ansible/40_thinkube/core/COMPONENT/15_configure_something.yaml
```

### Step 3: Test Deployment

```bash
./scripts/run_ansible.sh ansible/40_thinkube/core/COMPONENT/18_test.yaml
```

## Configuration

### Basic Configuration

Describe the main configuration options available:
- Option 1: Description
- Option 2: Description

### Advanced Configuration

Any advanced or optional configuration:
- Feature flags
- Performance tuning
- Resource limits

### Example Configuration

```yaml
# Example inventory configuration
component_specific_var: value
resource_limits:
  cpu: 1000m
  memory: 2Gi
```

## Accessing the Component

### From Within the Cluster

```
Service: service-name.namespace
Port: XXXX
```

### From Outside the Cluster

```
URL: https://component.domain.com
```

### Authentication

How to authenticate (if applicable):
- SSO via Keycloak
- API tokens
- Basic auth

## Testing

### Verify Deployment

```bash
# Check pods are running
kubectl get pods -n NAMESPACE

# Check service endpoints
kubectl get svc -n NAMESPACE

# Check ingress
kubectl get ingress -n NAMESPACE
```

### Functional Tests

How to verify the component is working correctly:

```bash
# Example test commands
curl -I https://component.domain.com/health
```

Expected output:
```
HTTP/1.1 200 OK
```

## Troubleshooting

### Common Issue 1

**Symptoms**: Description of what you see

**Root Cause**: Why it happens

**Solution**:
```bash
# Commands to fix it
```

### Common Issue 2

**Symptoms**: Description

**Root Cause**: Explanation

**Solution**:
Steps to resolve

### View Logs

```bash
# View component logs
kubectl logs -n NAMESPACE deployment/COMPONENT-NAME

# View specific pod logs
kubectl logs -n NAMESPACE POD-NAME
```

## Rollback

To completely remove this component:

```bash
./scripts/run_ansible.sh ansible/40_thinkube/core/COMPONENT/19_rollback.yaml
```

**Warning**: This will:
- Remove all deployed resources
- Delete persistent data (if applicable)
- May affect dependent components

**Dependencies**: Before rolling back, ensure no other components depend on this one.

## Integration

### How Other Components Use This

- **component-1**: How it integrates
- **component-2**: How it integrates

### API/Interface

If the component exposes APIs or interfaces:
- API endpoints
- Connection strings
- Client library usage

## Architecture Notes

### Storage

- Where data is stored
- Persistence strategy
- Backup considerations

### Networking

- Ports used
- Ingress configuration
- Service mesh integration (if applicable)

### Security

- Authentication mechanisms
- Authorization model
- TLS/SSL configuration
- Security best practices

## Platform-Specific Notes

### ARM64 Support

Any ARM64-specific considerations or issues.

### GPU Support

GPU requirements and configuration (if applicable).

### DGX Spark Specific

Any DGX Spark-specific notes or workarounds.

## References

- [Official Documentation](https://example.com)
- [Component GitHub](https://github.com/project/component)
- Related Thinkube documentation

---

**Deployment Order**: #X
**Namespace**: namespace-name
**Type**: Core/Optional
**Last Updated**: YYYY-MM-DD
