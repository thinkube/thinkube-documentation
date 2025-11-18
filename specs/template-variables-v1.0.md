# Template Variables Specification v1.0

## Purpose
Documents all variables available to Thinkube templates during processing by Copier.

## Variable Categories

### 1. Standard Parameters (Always Available)
These are provided by thinkube-control for every template deployment:

| Variable | Description | Example |
|----------|-------------|---------|
| `project_name` | Application name (lowercase-hyphenated) | `my-app` |
| `project_description` | Brief description of the application | `My awesome application` |
| `author_name` | Developer/deployer name | `John Doe` |
| `author_email` | Developer/deployer email | `john@example.com` |

### 2. Domain Variables
These are installation-specific values from the inventory:

| Variable | Description | Example |
|----------|-------------|---------|
| `domain_name` | Platform domain | `thinkube.com` |
| `container_registry` | Harbor registry URL | `registry.thinkube.com` |
| `admin_username` | Platform admin username | `tkadmin` |

### 3. Template-Specific Parameters
Additional parameters defined in `manifest.yaml`:

```yaml
# From manifest.yaml
parameters:
  - name: enable_api_docs
    type: bool
    description: Include OpenAPI documentation?
    default: true
```

These become available as variables in templates.

## Usage in Templates

### In Python Code (.py.jinja)
```python
# server.py.jinja
APP_NAME = "{{ project_name }}"
APP_DESCRIPTION = "{{ project_description }}"
DOMAIN = "{{ domain_name }}"
AUTHOR = "{{ author_name }} <{{ author_email }}>"
```

### In Dockerfiles (.Dockerfile.jinja)
```dockerfile
# Dockerfile.jinja
FROM {{ container_registry }}/library/python:3.12-slim
LABEL maintainer="{{ author_name }} <{{ author_email }}>"
LABEL description="{{ project_description }}"
```

### In YAML Files (.yaml.jinja)
```yaml
# config.yaml.jinja
app:
  name: {{ project_name }}
  host: {{ project_name }}.{{ domain_name }}
  registry: {{ container_registry }}
```

### In Documentation (.md.jinja)
```markdown
# {{ project_name }}

{{ project_description }}

## Author
{{ author_name }} ({{ author_email }})

## Access
https://{{ project_name }}.{{ domain_name }}
```

## Important Notes

1. **thinkube.yaml is STATIC** - It does NOT support variables except:
   - `{{ project_name }}` in metadata.name
   - That's it!

2. **Only .jinja files are processed** - Files without .jinja extension are copied as-is

3. **Variable naming** - Use the exact names listed above (case-sensitive)

4. **No custom variables** - Only the documented variables are available

## Common Mistakes

### ❌ Wrong: Using variables in thinkube.yaml
```yaml
# thinkube.yaml - THIS WON'T WORK
spec:
  containers:
    - name: backend
      image: {{ container_registry }}/... # NO!
```

### ❌ Wrong: Using wrong variable names
```python
# server.py.jinja
registry = "{{ harbor_registry }}"  # Wrong - use container_registry
domain = "{{ domain }}"             # Wrong - use domain_name
```

### ✅ Correct: Using documented variables
```python
# server.py.jinja
registry = "{{ container_registry }}"
domain = "{{ domain_name }}"
```

## Version History

- **v1.0** (2024-01-29) - Initial specification
  - Documented standard parameters
  - Listed domain variables
  - Clarified thinkube.yaml limitations