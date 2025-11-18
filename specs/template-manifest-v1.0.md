# Template Manifest Specification v1.0

## Purpose
Defines metadata and parameters for Thinkube application templates. This manifest is converted to copier.yml for template processing while maintaining simplicity and safety.

## Philosophy
**Many Simple Templates > One Complex Template**

- Create multiple focused templates instead of one configurable template
- Each template should do one thing well
- Most templates need 0-2 additional parameters
- Be opinionated about technology choices

## File Name
`manifest.yaml` - Located in the root of each template directory

## Schema

```yaml
apiVersion: thinkube.io/v1
kind: TemplateManifest
metadata:
  name: string          # Template identifier (lowercase-hyphenated)
  title: string         # Human-readable title
  description: string   # Clear description of what this template provides
  tags: [string]        # Categories for template discovery

parameters: []          # Additional parameters (usually 0-2)
  - name: string       # Parameter identifier (snake_case)
    type: string       # Data type: str, bool, int, choice
    description: string # Help text shown in UI
    default: any       # Default value (optional, required for bool)
    # Type-specific fields...

secrets: []            # Required secrets for the application
  - name: string       # Secret name (e.g., API_KEY, DATABASE_PASSWORD)
    description: string # Help text explaining what this secret is for
    required: bool     # Whether the secret is required (default: true)
```

## Standard Parameters (Always Included)

These parameters are automatically available in every template:

- `project_name` - Application name (lowercase-hyphenated)
- `project_description` - Brief description
- `author_name` - Developer name
- `author_email` - Developer email

These are injected by CopierGenerator and don't need to be defined in manifest.yaml.

## Secrets Management

Applications can declare required secrets (API keys, tokens, passwords) that will be:
1. Validated during deployment - deployment fails if required secrets are missing
2. Injected as environment variables via Kubernetes Secrets
3. Managed centrally through thinkube-control UI

### Secret Declaration
```yaml
secrets:
  - name: OPENAI_API_KEY
    description: OpenAI API key for GPT models
    required: true
    
  - name: SLACK_WEBHOOK_URL
    description: Slack webhook for notifications (optional)
    required: false
```

### How Secrets Work
1. **Declaration**: Templates declare needed secrets in manifest.yaml
2. **Management**: Admins add secrets through thinkube-control UI
3. **Injection**: During deployment, secrets are:
   - Retrieved from thinkube-control's encrypted storage
   - Created as Kubernetes Secret in the app namespace
   - Mounted to containers via `envFrom`
4. **Access**: Applications read secrets as environment variables

### Security Notes
- Secrets are encrypted at rest using Fernet symmetric encryption
- Each application only gets access to its declared secrets
- Secrets are never exposed in Git repositories or logs
- API requires authentication to access secret values

## Additional Parameters

Only add parameters that:
1. Fundamentally change the template structure
2. Affect multiple files (5+ locations)
3. Are difficult to change after generation
4. Represent clear architectural decisions

### Parameter Types

#### bool - Yes/No decisions
```yaml
- name: enable_websockets
  type: bool
  description: Include WebSocket support?
  default: false
```

#### str - Text input (rarely needed)
```yaml
- name: api_prefix
  type: str
  description: API route prefix
  default: "/api/v1"
  pattern: "^/[a-zA-Z][a-zA-Z0-9/_-]*$"  # Optional validation
```

#### int - Numbers (rarely needed)
```yaml
- name: worker_count
  type: int
  description: Number of worker processes
  default: 4
  min: 1
  max: 16
```

#### choice - Selection (avoid when possible)
```yaml
- name: auth_provider
  type: choice
  description: Authentication provider
  choices: ["keycloak", "auth0"]
  default: "keycloak"
```

## Template Naming Convention

Use clear, specific names that describe exactly what the template provides:

```
# API Templates
fastapi-crud          # CRUD API with PostgreSQL
fastapi-webhook       # Webhook receiver (no database)
fastapi-graphql       # GraphQL API

# Web App Templates  
vue-dashboard         # Admin dashboard with auth
vue-landing          # Marketing landing page
react-dashboard      # React version of dashboard

# AI Templates
ai-chatbot           # LLM chat interface
ai-agent             # Basic AI agent
ai-rag-service       # RAG with vector store

# Service Templates
worker-queue         # Background job processor
scheduler-service    # Cron job scheduler
data-pipeline        # ETL pipeline
```

## Examples

### Simple API (No Additional Parameters)
```yaml
apiVersion: thinkube.io/v1
kind: TemplateManifest
metadata:
  name: fastapi-crud
  title: FastAPI CRUD API
  description: REST API with PostgreSQL database and CRUD operations
  tags: ["api", "database", "crud", "rest"]

parameters: []  # No additional parameters needed!
```

This template always includes PostgreSQL, auth, and OpenAPI docs - no choices needed.

### AI Chatbot (One Parameter)
```yaml
apiVersion: thinkube.io/v1
kind: TemplateManifest
metadata:
  name: ai-chatbot
  title: AI Chatbot Interface
  description: Chat interface for LLM interactions with Claude/GPT
  tags: ["ai", "chat", "llm", "webapp"]

parameters:
  - name: enable_history
    type: bool
    description: Store conversation history in database?
    default: true

secrets:
  - name: ANTHROPIC_API_KEY
    description: Anthropic API key for Claude models
    required: true
```

Just one parameter that determines if PostgreSQL is included, plus required API key.

### Complex Service (Two Parameters)
```yaml
apiVersion: thinkube.io/v1
kind: TemplateManifest
metadata:
  name: ai-agent
  title: AI Agent Service  
  description: Autonomous AI agent with tool execution capabilities
  tags: ["ai", "agent", "llm", "automation"]

parameters:
  - name: enable_web_tools
    type: bool
    description: Allow agent to browse the web?
    default: false
    
  - name: enable_code_execution
    type: bool
    description: Allow agent to execute Python code?
    default: false
```

Two security-related parameters that fundamentally change what the agent can do.

### ML/AI Service (With Secrets)
```yaml
apiVersion: thinkube.io/v1
kind: TemplateManifest
metadata:
  name: vllm-inference
  title: vLLM Inference Server
  description: High-performance LLM inference with vLLM engine
  tags: ["ai", "llm", "vllm", "inference", "gpu"]

parameters:
  - name: model_id
    type: str
    description: Hugging Face model ID (e.g., mistralai/Mistral-7B)
    pattern: "^[a-zA-Z0-9-]+/[a-zA-Z0-9._-]+$"

secrets:
  - name: HF_TOKEN
    description: Hugging Face API token for accessing gated models
    required: true
```

Model selection as parameter, authentication as secret.

## What NOT to Do

### ❌ BAD: Too Many Parameters
```yaml
# Don't create a "configurable everything" template
parameters:
  - name: python_version      # Be opinionated!
  - name: database_type       # Pick one!
  - name: frontend_framework  # Separate templates!
  - name: enable_redis        # Just include it!
  - name: api_rate_limit      # Runtime config!
  - name: log_level          # Environment variable!
  - name: theme_color        # User can change!
```

### ❌ BAD: Configuration Parameters
```yaml
# Don't add parameters for runtime configuration
parameters:
  - name: max_upload_size    # Put in config file
  - name: session_timeout    # Put in config file
  - name: smtp_server       # Environment variable
```

### ✅ GOOD: Structural Parameters Only
```yaml
# Only parameters that fundamentally change the template
parameters:
  - name: include_admin_ui
    type: bool
    description: Include admin interface?
    default: false
    # This affects: routes, dependencies, components, build
```

## Parameter Guidelines

### When to Add a Parameter
- Changes fundamental architecture
- Affects 5+ files when toggled
- Adds/removes major dependencies
- Security boundary decision

### When NOT to Add a Parameter
- Version selections (be opinionated)
- Style/theme preferences
- Performance tuning values
- Runtime configuration
- Feature flags (add in code)

## Processing Flow

1. **Template Creation**
   - Author creates focused template
   - Adds manifest.yaml with minimal parameters

2. **Template Discovery**
   - User browses templates by tags/name
   - Sees clear description of what each provides

3. **Form Generation**
   - UI shows standard fields (project_name, etc.)
   - Shows 0-2 additional parameters if any

4. **Template Processing**
   - CopierGenerator converts to copier.yml
   - Copier processes template with user values

## Best Practices

1. **Start with Zero Parameters**
   - Try to create template with no additional parameters
   - Only add if absolutely necessary

2. **Clone, Don't Configure**
   - Instead of parameters, create template variants
   - `vue-dashboard` and `react-dashboard` not `dashboard` with framework parameter

3. **Clear Defaults**
   - Boolean parameters should have safe defaults
   - Usually `false` for features that add complexity

4. **Descriptive Names**
   - Template name should tell user exactly what they get
   - No surprises or hidden complexity

## Version History

- **v1.0** (2024-01-29) - Initial specification
  - Focus on simplicity
  - Promote many simple templates
  - Minimal parameter philosophy