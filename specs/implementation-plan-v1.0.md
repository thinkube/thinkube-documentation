# Implementation Plan for Specification Alignment v1.0

## Executive Summary

**Goal**: Align Thinkube with the principle that **many simple templates are better than one complex configurable template**.

**Current State**: 
- Templates use Jinja2 conditionals in thinkube.yaml
- Complex parameter systems with 10+ options
- Hardcoded assumptions about 2 containers (frontend/backend)
- Mixing of deployment logic in templates

**Target State**:
- Static thinkube.yaml files (no conditionals)
- Templates with 0-2 parameters maximum
- Support for N containers (not hardcoded to 2)
- Clean separation of concerns

## Core Principles (Guardrails)

1. **thinkube.yaml is STATIC** - No {% if %} blocks, only {{ project_name }} substitutions
2. **Templates are FOCUSED** - Each does one thing well
3. **Parameters are MINIMAL** - Only for fundamental architectural changes
4. **Deployment is FLEXIBLE** - Supports 1 to N containers
5. **Health Endpoints are STANDARD** - All containers expose `/health` (see health-endpoints-v1.0.md)

## Changes by Component

### 1. Template Structure Changes

**From**:
```
tkt-webapp-vue-fastapi/
├── template.yaml (16 parameters)
├── thinkube.yaml (with {% if %} conditionals)
└── ...
```

**To**:
```
fastapi-crud/
├── manifest.yaml (0 parameters)
├── thinkube.yaml (static, includes PostgreSQL)
└── ...

fastapi-webhook/
├── manifest.yaml (0 parameters)
├── thinkube.yaml (static, no PostgreSQL)
└── ...
```

**Required Changes**:
1. Split complex templates into multiple focused ones
2. Rename `template.yaml` → `manifest.yaml`
3. Remove ALL Jinja2 conditionals from thinkube.yaml
4. Create separate templates for each use case

### 2. thinkube-control Changes

#### 2.1 CopierGenerator Updates

**File**: `/home/thinkube/thinkube/thinkube-control/backend/app/utils/copier_generator.py`

**Changes**:
```python
# Line 52-53: Update kind validation
if self.template.get('kind') != 'TemplateManifest':
    raise ValueError("kind must be 'TemplateManifest'")

# Add parameter count warning
if len(self.template.get('parameters', [])) > 2:
    logger.warning(f"Template '{self.template['metadata']['name']}' has {len(parameters)} parameters. "
                  f"Consider splitting into focused templates instead.")

# Support both file names for backward compatibility
# Look for manifest.yaml first, then template.yaml
```

#### 2.2 Template API Updates

**File**: `/home/thinkube/thinkube/thinkube-control/backend/app/api/templates.py`

**Changes**:
```python
# Lines 187-193: Try manifest.yaml first
manifest_urls = [
    f"https://raw.githubusercontent.com/{org}/{repo}/main/manifest.yaml",
    f"https://raw.githubusercontent.com/{org}/{repo}/master/manifest.yaml",
    f"https://raw.githubusercontent.com/{org}/{repo}/main/template.yaml",  # backward compat
    f"https://raw.githubusercontent.com/{org}/{repo}/master/template.yaml",  # backward compat
]
```

### 3. Deployment Pipeline Changes

#### 3.1 Remove thinkube.yaml Rendering

**File**: `/home/thinkube/thinkube/thinkube-control/tasks/generate_k8s_manifests.yaml`

**Changes**:
```yaml
# DELETE lines 16-42 (entire rendering section)
# REPLACE with simple file read:
- name: Read thinkube.yaml
  ansible.builtin.slurp:
    src: "{{ local_repo_path }}/thinkube.yaml"
  register: thinkube_content

- name: Parse thinkube.yaml
  ansible.builtin.set_fact:
    thinkube_spec: "{{ thinkube_content.content | b64decode | from_yaml }}"
```

### 4. Webhook Adapter Changes

**File**: `/home/thinkube/thinkube/ansible/40_thinkube/core/argocd/15_deploy_webhook_adapter.yaml`

**Critical Changes to Python Script** (lines 79-571):

#### 4.1 Add ConfigMap Reading
```python
def get_app_containers(app_name):
    """Get container definitions from app-metadata ConfigMap"""
    try:
        # Use Kubernetes API to read ConfigMap
        import urllib3
        urllib3.disable_warnings()
        
        # Read service account token
        with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'r') as f:
            token = f.read()
        
        headers = {'Authorization': f'Bearer {token}'}
        url = f'https://kubernetes.default.svc/api/v1/namespaces/{app_name}/configmaps/{app_name}-metadata'
        
        response = requests.get(url, headers=headers, verify=False)
        if response.status_code == 200:
            cm_data = response.json()
            containers_json = cm_data.get('data', {}).get('containers', '[]')
            return json.loads(containers_json)
        else:
            logger.warning(f"Could not get ConfigMap for {app_name}, using defaults")
            return [{'name': 'backend'}, {'name': 'frontend'}]  # Fallback
    except Exception as e:
        logger.error(f"Error reading ConfigMap: {e}")
        return [{'name': 'backend'}, {'name': 'frontend'}]  # Fallback
```

#### 4.2 Update Image Checking (lines 447-454)
```python
# OLD CODE (DELETE):
backend_exists = check_harbor_image('thinkube', f'{app_name}-backend', tag)
frontend_exists = check_harbor_image('thinkube', f'{app_name}-frontend', tag)
if backend_exists and frontend_exists:

# NEW CODE:
containers = get_app_containers(app_name)
all_images_exist = all(
    check_harbor_image('thinkube', f'{app_name}-{container["name"]}', tag)
    for container in containers
)
if all_images_exist:
    logger.info(f"All {len(containers)} images found for {app_name}:{tag}")
```

#### 4.3 Update Git Image List (lines 324-338)
```python
# OLD CODE (DELETE):
f.write(f'  - registry.thinkube.com/thinkube/{app_name}-backend:{tag}\n')
f.write(f'  - registry.thinkube.com/thinkube/{app_name}-frontend:{tag}\n')

# NEW CODE:
containers = get_app_containers(app_name)
for container in containers:
    f.write(f'  - registry.thinkube.com/thinkube/{app_name}-{container["name"]}:{tag}\n')
```

#### 4.4 Add RBAC for ConfigMap Access
```yaml
# Add after line 651
- name: Create ServiceAccount for webhook adapter
  kubernetes.core.k8s:
    kubeconfig: "{{ kubeconfig }}"
    state: present
    definition:
      apiVersion: v1
      kind: ServiceAccount
      metadata:
        name: "{{ adapter_name }}"
        namespace: "{{ adapter_namespace }}"

- name: Create ClusterRole for ConfigMap reading
  kubernetes.core.k8s:
    kubeconfig: "{{ kubeconfig }}"
    state: present
    definition:
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRole
      metadata:
        name: "{{ adapter_name }}-configmap-reader"
      rules:
      - apiGroups: [""]
        resources: ["configmaps"]
        verbs: ["get", "list"]

- name: Create ClusterRoleBinding
  kubernetes.core.k8s:
    kubeconfig: "{{ kubeconfig }}"
    state: present
    definition:
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      metadata:
        name: "{{ adapter_name }}-configmap-reader"
      roleRef:
        apiGroup: rbac.authorization.k8s.io
        kind: ClusterRole
        name: "{{ adapter_name }}-configmap-reader"
      subjects:
      - kind: ServiceAccount
        name: "{{ adapter_name }}"
        namespace: "{{ adapter_namespace }}"
```

## Migration Strategy

### Phase 1: Infrastructure Updates (Week 1)
1. Update CopierGenerator to support TemplateManifest
2. Update template API to look for manifest.yaml
3. Update webhook adapter to read ConfigMaps
4. Remove thinkube.yaml rendering logic

### Phase 2: Template Migration (Week 2)
1. Split `tkt-webapp-vue-fastapi` into:
   - `fastapi-crud` (with PostgreSQL)
   - `fastapi-api` (stateless API)
   - `vue-dashboard` (admin UI)
   - `vue-app` (basic web app)
2. Create static thinkube.yaml for each
3. Rename template.yaml → manifest.yaml
4. Reduce parameters to 0-2 per template

### Phase 3: New Templates (Week 3)
1. Create focused AI templates:
   - `ai-chatbot`
   - `ai-agent`
   - `ai-rag-service`
2. Validate all templates follow guidelines
3. Update documentation

## Testing Strategy

### Unit Tests
1. **CopierGenerator Tests**:
   - Validates TemplateManifest kind
   - Warns on too many parameters
   - Handles both manifest.yaml and template.yaml

2. **Webhook Adapter Tests**:
   - Correctly reads ConfigMaps
   - Handles N containers
   - Falls back gracefully

### Integration Tests
1. **Template Deployment**:
   - Deploy template with 1 container
   - Deploy template with 3 containers
   - Verify correct manifests generated

2. **CI/CD Pipeline**:
   - Push images for all containers
   - Verify webhook adapter updates Git correctly
   - Confirm ArgoCD deploys all containers

### End-to-End Validation
1. Create new template following guidelines
2. Deploy via Thinkube UI
3. Push code changes
4. Verify full CI/CD pipeline works

## Guardrails to Prevent Deviation

### 1. Automated Checks

**Pre-commit Hook** for templates:
```bash
#!/bin/bash
# Check thinkube.yaml has no Jinja2 conditionals
if grep -q '{%' thinkube.yaml; then
  echo "ERROR: thinkube.yaml must not contain Jinja2 conditionals"
  exit 1
fi

# Check manifest.yaml has <= 2 parameters
param_count=$(yq eval '.parameters | length' manifest.yaml)
if [ "$param_count" -gt 2 ]; then
  echo "WARNING: Template has $param_count parameters. Consider splitting into focused templates."
fi
```

### 2. Template Review Checklist
- [ ] No Jinja2 conditionals in thinkube.yaml
- [ ] 0-2 parameters in manifest.yaml
- [ ] Clear, focused template name
- [ ] Each parameter changes 5+ files
- [ ] Template does one thing well

### 3. Documentation Requirements
- Every template must have clear README
- Document what the template provides (not what it could provide)
- No "configuration options" - just what it does

### 4. Anti-Pattern Detection

**Red Flags**:
- Parameter named `*_version` (be opinionated)
- Parameter for styling/theming (runtime concern)
- More than 2 boolean parameters (split template)
- Conditional features in thinkube.yaml
- Generic names like "webapp" or "api"

## Success Metrics

1. **Template Simplicity**:
   - Average parameters per template: ≤ 1
   - Templates with 0 parameters: > 50%
   - No template with > 2 parameters

2. **Deployment Flexibility**:
   - Support apps with 1-10 containers
   - No hardcoded container names
   - All templates use static thinkube.yaml

3. **Developer Experience**:
   - Template selection time: < 30 seconds
   - No decision paralysis from parameters
   - Clear what each template provides

## Timeline

- **Week 1**: Infrastructure changes (webhook adapter, thinkube-control)
- **Week 2**: Template migration (split existing templates)
- **Week 3**: New template creation
- **Week 4**: Testing and documentation
- **Week 5**: Rollout and monitoring

## Risk Mitigation

1. **Backward Compatibility**:
   - Support template.yaml temporarily
   - Webhook adapter fallback for 2 containers
   - Clear migration documentation

2. **Template Explosion**:
   - Limit initial templates to 10-15
   - Focus on most common use cases
   - Regular review to merge similar templates

3. **User Confusion**:
   - Clear template naming convention
   - Comprehensive template gallery
   - Migration guide for existing users

## Conclusion

This plan aligns Thinkube with its core philosophy: **simplicity and opinion over configuration**. By following these changes and guardrails, we ensure that Thinkube remains a fast, opinionated platform for building AI applications without the complexity that crept into the previous implementation.