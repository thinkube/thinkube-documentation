# Validation Checklist for Thinkube Specifications

## Purpose
This checklist ensures all components comply with Thinkube specifications and prevents deviation from core principles.

## 🔍 Template Validation

### Manifest File (manifest.yaml)
- [ ] File is named `manifest.yaml` (not template.yaml)
- [ ] `kind: TemplateManifest` (not Template)
- [ ] Has clear, specific template name (e.g., `fastapi-crud`, not `webapp`)
- [ ] Has 0-2 parameters maximum
- [ ] Each parameter has a clear `description`
- [ ] Boolean parameters have defaults
- [ ] No version selection parameters (e.g., python_version)
- [ ] No style/theme parameters
- [ ] No runtime configuration parameters

### thinkube.yaml File
- [ ] **NO Jinja2 conditionals** (`{% if %}`, `{% for %}`, etc.)
- [ ] Only basic substitutions allowed: `{{ project_name }}`, `{{ domain_name }}`
- [ ] Static container definitions (no conditional containers)
- [ ] All containers have `name` and `build` fields
- [ ] All containers have `health: /health` field
- [ ] Routes map to actual container names
- [ ] Services are simple strings or `type:name` format

### Anti-Patterns to Check
- [ ] ❌ NO parameters for versions (Python, Node, etc.)
- [ ] ❌ NO parameters for UI themes or colors
- [ ] ❌ NO parameters for performance tuning
- [ ] ❌ NO complex conditionals in any file
- [ ] ❌ NO "kitchen sink" templates that do everything

## 🔧 Code Component Validation

### CopierGenerator (thinkube-control)
- [ ] Validates `kind: TemplateManifest`
- [ ] Warns when parameters > 2
- [ ] Supports both manifest.yaml and template.yaml (backward compat)
- [ ] Adds standard parameters automatically

### Template API (thinkube-control)
- [ ] Looks for manifest.yaml first
- [ ] Falls back to template.yaml for compatibility
- [ ] Returns proper error if neither exists
- [ ] Correctly parses TemplateManifest kind

### Deployment Pipeline
- [ ] Does NOT render thinkube.yaml as template
- [ ] Reads thinkube.yaml as static file
- [ ] Generates ConfigMap with container info
- [ ] Creates manifests for N containers (not hardcoded to 2)

### Webhook Adapter
- [ ] Reads container list from ConfigMap
- [ ] Waits for ALL container images (not just 2)
- [ ] Updates Git with correct image list
- [ ] Has RBAC to read ConfigMaps
- [ ] Falls back gracefully if ConfigMap missing

## 🏥 Health Endpoint Validation

### Implementation Check
- [ ] All containers implement `/health` endpoint
- [ ] Returns 200 OK with JSON response
- [ ] Response includes `status` and `component` fields
- [ ] No authentication required
- [ ] Response time < 100ms
- [ ] No external dependencies in health check

### Response Format
- [ ] Content-Type: application/json
- [ ] Includes `"status": "healthy"`
- [ ] Includes `"component": "<name>"`
- [ ] Backend services include `"service": "<project_name>"`

## 📋 Template Review Checklist

### Before Accepting a New Template

**1. Template Focus**
- [ ] Does ONE thing well
- [ ] Clear use case
- [ ] Not trying to be configurable for multiple scenarios

**2. Parameter Minimalism**
- [ ] 0 parameters is ideal
- [ ] Maximum 2 parameters
- [ ] Each parameter affects 5+ files
- [ ] Parameters are for fundamental architecture only

**3. Naming Convention**
- [ ] Descriptive name (what it does, not generic)
- [ ] Examples: `fastapi-crud`, `ai-chatbot`, `vue-dashboard`
- [ ] NOT: `webapp`, `api`, `fullstack`

**4. Static Configuration**
- [ ] thinkube.yaml has no conditionals
- [ ] All features are included or not (no toggles)
- [ ] Clear about what's provided

## 🚨 Red Flags - Immediate Rejection

1. **Jinja2 in thinkube.yaml**
   ```yaml
   # ❌ REJECT
   {% if use_postgresql %}
   - name: DATABASE_URL
   {% endif %}
   ```

2. **Too Many Parameters**
   ```yaml
   # ❌ REJECT - 5+ parameters
   parameters:
     - python_version
     - database_type
     - ui_framework
     - enable_cache
     - api_style
   ```

3. **Version Selection**
   ```yaml
   # ❌ REJECT
   - name: node_version
     type: choice
     choices: ["16", "18", "20"]
   ```

4. **Generic Template Names**
   ```yaml
   # ❌ REJECT
   metadata:
     name: webapp  # Too generic!
   ```

## ✅ Good Examples

### Good Template Structure
```yaml
# manifest.yaml
apiVersion: thinkube.io/v1
kind: TemplateManifest
metadata:
  name: fastapi-crud
  title: FastAPI CRUD API
  
parameters: []  # No parameters needed!
```

```yaml
# thinkube.yaml
apiVersion: thinkube.io/v1
kind: ThinkubeDeployment
metadata:
  name: "{{ project_name }}"
  
spec:
  containers:
    - name: api
      build: .
      port: 8000
      
  services:
    - database  # Always included, no conditionals
```

### Good Parameter (When Needed)
```yaml
parameters:
  - name: enable_public_access
    type: bool
    description: Allow unauthenticated access?
    default: false
    # This fundamentally changes auth middleware, routes, and security
```

## 📊 Metrics to Track

### Template Quality Metrics
- Average parameters per template: **Target ≤ 1**
- Templates with 0 parameters: **Target > 50%**
- Templates with 3+ parameters: **Target = 0**

### Implementation Compliance
- Templates with static thinkube.yaml: **Target = 100%**
- Webhook adapter handling N containers: **Must work**
- No hardcoded container assumptions: **Target = 100%**

## 🔄 Regular Review Process

### Monthly Template Audit
1. Check all templates against this checklist
2. Identify templates that could be split
3. Remove unused or overly complex templates
4. Ensure naming remains clear and consistent

### Quarterly Architecture Review
1. Verify no conditional logic crept into thinkube.yaml
2. Check average parameter count trend
3. Ensure webhook adapter remains flexible
4. Review and update this checklist

## 🛡️ Enforcement

### Automated Checks (CI/CD)
```bash
# Add to template CI pipeline
- name: Validate no conditionals in thinkube.yaml
  run: |
    if grep -q '{%' thinkube.yaml; then
      echo "ERROR: thinkube.yaml contains Jinja2 conditionals"
      exit 1
    fi

- name: Check parameter count
  run: |
    count=$(yq eval '.parameters | length' manifest.yaml)
    if [ "$count" -gt 2 ]; then
      echo "ERROR: Too many parameters ($count). Maximum is 2."
      exit 1
    fi
```

### Manual Review Required
- New templates must be reviewed against this checklist
- Major updates require re-validation
- Document any exceptions (should be rare)

## 📝 Sign-off

**Template Name**: _______________________

**Reviewed By**: _______________________

**Date**: _______________________

**Checklist Complete**: [ ] Yes [ ] No

**Exceptions Noted**: _______________________

---

*This checklist is version controlled. Updates require architecture team approval.*