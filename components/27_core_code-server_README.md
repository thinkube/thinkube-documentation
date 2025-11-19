# Code-Server

This component deploys [code-server](https://github.com/coder/code-server) - VS Code in the browser for cloud-based development integrated with the Thinkube platform.

## Overview

Code-Server provides a full VS Code experience accessible from any browser with comprehensive platform integration:

- **Browser-Based IDE**: Complete VS Code functionality without local installation
- **Keycloak SSO**: OAuth2/OIDC authentication via oauth2-proxy with role-based access
- **Shared Code Directory**: Common filesystem shared with JupyterHub for seamless workflow
- **Development Tools**: Pre-configured Node.js, Python, Ansible, Claude Code integration
- **Git Integration**: Configured access to GitHub and Gitea with automated SSH keys
- **CI/CD Ready**: Argo Workflows CLI and Gitea integration for workflow triggers
- **CLI Tools**: kubectl, argocd, argo, tea (Gitea), gh (GitHub), docker configured
- **Custom Extensions**: Thinkube AI integration, CI/CD monitor, custom theme
- **Shell Environment**: Unified bash/zsh/fish configuration with Starship prompt

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster
- ingress (deployment order #13) - For web UI access
- acme-certificates (deployment order #12) - For TLS certificates
- keycloak (deployment order #15) - For SSO authentication
- harbor (deployment order #16) - For container images
- argo-workflows (deployment order #23) - For CI/CD integration (optional but recommended)
- gitea (deployment order #26) - For Git repository hosting (optional but recommended)

**Deployment order**: #27

## Prerequisites

**Required inventory variables** (example values shown):

```yaml
# Code-server configuration
code_server_namespace: code-server
code_server_hostname: code.example.com  # Replace with your domain
shared_code_path: /home/ubuntu/shared-code

# Resource limits
code_server_cpu_request: 1
code_server_cpu_limit: 4
code_server_memory_request: 4Gi
code_server_memory_limit: 8Gi

# OAuth2 proxy settings
oauth2_proxy_client_id: code-server
oauth2_proxy_cookie_domain: example.com  # Replace with your domain

# Keycloak configuration (inherited)
keycloak_url: https://keycloak.example.com  # Replace with your domain
keycloak_realm: thinkube
admin_username: admin
auth_realm_username: tkadmin

# Harbor configuration (inherited)
harbor_registry: harbor.example.com  # Replace with your domain

# Gitea configuration (inherited, if deployed)
gitea_hostname: git.example.com  # Replace with your domain
devpi_api_hostname: devpi-api.example.com  # Replace with your domain

# Kubernetes configuration (inherited)
domain_name: example.com  # Replace with your domain
kubeconfig: /var/snap/k8s/common/etc/admin.conf
kubectl_bin: /snap/k8s/current/bin/kubectl
system_username: ubuntu
```

**Required environment variables**:
- `ADMIN_PASSWORD`: Admin password for Keycloak and service authentication
- `GITHUB_TOKEN`: GitHub personal access token for repository access (optional)

## Playbooks

### 00_install.yaml
Orchestrator playbook that runs all code-server deployment playbooks in sequence:
- Imports 10_deploy.yaml - Deploys code-server with OAuth2 authentication
- Imports 14_configure_shell.yaml - Configures shell environment
- Imports 15_configure_environment.yaml - Installs development tools
- Imports 16_configure_gitea_integration.yaml - Sets up Gitea integration
- Imports 17_configure_discovery.yaml - Configures service discovery

### 10_deploy.yaml
Main deployment playbook for code-server infrastructure:

- **Control Plane Discovery**:
  - Detects Kubernetes control plane node hostname for pod scheduling
  - Ensures code-server runs on specific node with affinity rules

- **Keycloak OAuth2 Integration**:
  - Authenticates with Keycloak admin API
  - Creates `code-server` OpenID Connect client:
    - Client ID: code-server
    - Protocol: openid-connect
    - Standard flow enabled, implicit flow and direct access disabled
    - Redirect URI: `https://code.example.com/oauth2/callback`
    - Token lifespan: 3600 seconds
    - Scopes: email, offline_access, profile, roles
  - Creates realm roles: `code-server-admin` and `code-server-user`
  - Assigns admin user to code-server-admin role
  - Creates audience mapper for JWT token claims
  - Retrieves client secret for OAuth2 Proxy

- **Shared Code Directory**:
  - Creates `/home/{system_username}/shared-code` on host
  - Sets ownership to UID 1000, GID 1000 (thinkube user)
  - Mounts as hostPath volume at `/home/thinkube` in container

- **SSH Infrastructure**:
  - Generates Ed25519 SSH key pairs:
    - `id_ed25519`: For cluster node access
    - `github_ed25519`: For GitHub authentication
  - Creates comprehensive SSH config with:
    - Ansible controller access
    - All k8s control plane nodes with ZeroTier IPs
    - GitHub with identity file and agent forwarding
    - TCP keep-alive and connection pooling
  - Fetches thinkube cluster SSH key from management node
  - Adds GitHub SSH key to user account via `gh` CLI

- **Namespace and Secrets**:
  - Creates `code-server` namespace
  - Creates `code-server-oauth-secret` with OAuth2 client credentials
  - Copies wildcard TLS certificate from default namespace as `code-server-tls-secret`

- **ConfigMaps**:
  - `code-server-config`: code-server application configuration
    - Disables built-in auth (handled by OAuth2 proxy)
    - Bind address: 0.0.0.0:8080
    - Telemetry disabled
  - `code-server-default-settings`: VS Code editor settings
    - Font configuration: FiraCode, JetBrainsMono, Hack (Nerd Fonts)
    - Terminal and editor font sizes and ligatures

- **RBAC for CI/CD Monitoring**:
  - Creates ServiceAccount `code-server` in namespace
  - Creates ClusterRole `thinkube-cicd-monitor` with read permissions:
    - ConfigMaps (all namespaces) for pipeline events
    - Pods, Services, Deployments, ReplicaSets (all namespaces)
  - Creates ClusterRoleBinding granting monitoring role to code-server SA

- **Code-Server Deployment**:
  - Image: `{harbor_registry}/library/code-server-dev:latest`
  - Runs as UID:GID 1000:1000 (thinkube user)
  - Node affinity: Scheduled to specific control plane node
  - Environment variables:
    - TZ: UTC
    - CS_DISABLE_GETTING_STARTED_OVERRIDE: true
  - Command: `code-server` with arguments:
    - `--auth=none` (OAuth proxy handles authentication)
    - `--config=/config/config.yaml`
    - `--proxy-domain=code.example.com`
  - Working directory: `/home/thinkube`
  - Resource requests: 1 CPU, 4Gi memory
  - Resource limits: 4 CPU, 8Gi memory
  - Readiness probe: HTTP GET / on port 8080
  - Volume mounts:
    - `/home/thinkube`: hostPath to shared-code directory
    - `/config`: ConfigMap with code-server configuration
    - `/host-ssh`: Read-only mount of ansible controller SSH keys

- **Service and Ingress**:
  - ClusterIP Service exposing port 8080 internally
  - Ingress configuration:
    - Host: `code.example.com`
    - TLS enabled with wildcard certificate
    - NGINX annotations:
      - OAuth2 auth URL: `https://$host/oauth2/auth`
      - OAuth2 signin: `https://$host/oauth2/start?rd=$escaped_request_uri`
      - Proxy body size: unlimited (0)
      - Timeouts: 3600s for long-running operations

- **Ephemeral Valkey Cache**:
  - Deploys Valkey (Redis-compatible) as Deployment (replicas: 1)
  - Image: `{harbor_registry}/library/valkey:7.2-alpine`
  - Command: `valkey-server --save "" --appendonly no` (ephemeral, no persistence)
  - Resource requests: 50m CPU, 64Mi memory
  - Resource limits: 200m CPU, 256Mi memory
  - Service exposing port 6379 for OAuth2 session storage

- **OAuth2 Proxy Deployment**:
  - Deploys via Helm chart from oauth2-proxy/oauth2-proxy repository
  - Provider: keycloak-oidc
  - OIDC Issuer: `https://keycloak.example.com/realms/{realm}`
  - Client credentials from code-server-oauth-secret
  - Cookie settings:
    - Domain: `.example.com`
    - Secure: true
    - SameSite: none (iframe embedding support)
    - Refresh: 1 hour
  - Session storage: Redis (Valkey) at `redis://ephemeral-valkey.code-server.svc.cluster.local:6379`
  - Reverse proxy mode enabled with XAuth header injection

- **OAuth2 Proxy Ingress**:
  - Routes `/oauth2*` paths to oauth2-proxy service
  - Same TLS certificate and SSL redirect

- **Configuration Verification and Restart**:
  - Verifies ConfigMap has `auth: none` setting
  - Deletes code-server pods to force restart with updated configuration

- **VS Code Integration**:
  - Creates `.vscode` directory in shared code directory
  - Generates `tasks.json` from template for Claude Code integration
  - Creates `settings.json` to disable auto port forwarding

### 14_configure_shell.yaml
Shell environment configuration for unified bash/zsh/fish experience:

- **Deployment Readiness**:
  - Waits for code-server deployment to be ready
  - Gets running code-server pod name for configuration execution

- **Directory Structure**:
  - Creates `/home/thinkube/.thinkube_shared_shell/` for system-wide shell config
  - Creates `/home/thinkube/.user_shared_shell/` for user-specific configurations
  - Subdirectories: `functions/`, `aliases/`, `docs/`
  - Config directories: `~/.config/`, `~/.config/fish/`

- **Core Shell Setup** (via include_tasks):
  - Ensures required packages: git, curl, zsh, fish, nano, jq
  - Initializes directory structure

- **Starship Prompt**:
  - Configures Starship cross-shell prompt with Nerd Font icons
  - Config location: `~/.config/starship.toml`
  - Unified prompt experience across bash/zsh/fish

- **Functions System**:
  - Creates reusable shell functions in `~/.thinkube_shared_shell/functions/`:
    - `load_dotenv`: Load environment variables from .env files
    - `mkcd`: Create directory and cd into it
    - `extract`: Extract various archive types (tar, zip, etc.)
    - `sysinfo`: Display system information
    - `fif`: Find in files (grep wrapper)
    - Git shortcuts: `gst`, `gpl`, `gdf`, `gcm`, `gsh`
    - Management: `list_functions`, `hello`

- **Aliases System**:
  - JSON-based alias system with grouping and filtering
  - 25+ common aliases organized by category:
    - **files**: ll, la, l (ls variants)
    - **navigation**: .., ..., .... (cd shortcuts)
    - **git**: g, gco, gst, gd, gb (git shortcuts)
    - **k8s**: k, kc, mk, kx, kn (kubectl shortcuts)
    - **ansible**: ans, ansp, ansl (ansible shortcuts)
    - **devops**: tf (terraform)
    - **containers**: dk (docker)
    - **network**: sshdev (SSH with no host checking)
    - **thinkube**: runplay (ansible playbook runner)
    - **shell**: set-shell (switch shells)
  - Supports filtering: `aliases --groups` or `aliases -g k8s`

- **Fish Plugins**:
  - Installs fisher package manager
  - Adds plugins:
    - `edc/bass`: Bash compatibility in Fish
    - `PatrickF1/fzf.fish`: Fuzzy finder integration
    - `franciscolourenco/done`: Desktop notifications on command completion
    - `jorgebucaran/autopair.fish`: Auto-pairing for brackets/quotes

- **Shell Configuration**:
  - Configures `.bashrc` for Bash interactive shell
  - Configures `.zshrc` for Zsh interactive shell
  - Configures `~/.config/fish/config.fish` for Fish shell
  - Sources shared functions and aliases
  - Initializes Starship prompt
  - Loads fisher plugins (Fish only)

### 15_configure_environment.yaml
Development environment tools and platform integration:

- **Pod Readiness**:
  - Gets code-server pod name
  - Waits for pod to be in Ready state (300s timeout)

- **Environment File**:
  - Creates `.env` file in shared-code directory with:
    - ANSIBLE_BECOME_PASSWORD
    - ADMIN_PASSWORD
  - File mode: 0600 for security

- **Shell Environment Setup**:
  - Creates `env_setup.sh` (Bash/Zsh compatible):
    - Sets KUBECONFIG to `/home/thinkube/.kube/config`
    - Exports ARGO_TOKEN (Argo Workflows service account)
    - Sets ANSIBLE_CONFIG to `~/.ansible.cfg`
    - Activates Python virtualenv at `~/.venv`
    - Adds npm global bin to PATH
  - Creates `env_setup.fish` (Fish shell compatible) with same variables
  - Appends environment sourcing to shell configs (.bashrc, .zshrc, config.fish)

- **Login Shell Configuration**:
  - Creates `.bash_profile` to source `.bashrc` for bash login shells
  - Creates `.profile` to source `.bashrc` for other login shells

- **Node.js and npm**:
  - Configures npm global directory at `~/.npm-global`
  - Sets npm prefix configuration
  - Installs Claude Code globally: `npm install -g @anthropic-ai/claude-code`
  - Creates wrapper script at `/usr/local/bin/claude` with PATH setup

- **Python Environment**:
  - Creates Python virtualenv at `/home/thinkube/.venv`
  - Installs comprehensive package set:
    - **Core**: ansible, ansible-core, ansible-lint
    - **Python tools**: copier (templates), uv (fast package manager)
    - **Kubernetes**: kubernetes Python client
    - **Databases**: psycopg2-binary (PostgreSQL), redis (Redis client)
    - **Vector DBs**: chromadb, qdrant-client, weaviate-client
    - **Data tools**: opensearch-py, clickhouse-connect
    - **ML/AI**: mlflow, langfuse, argilla
    - **APIs**: requests, boto3 (AWS SDK)
    - **Message queues**: nats-py
    - **Container management**: cvat-cli

- **Package Management**:
  - **pip Configuration**: Creates `~/.config/pip/pip.conf` pointing to DevPI index
  - **uv Configuration**: Creates `~/.config/uv/uv.toml` for DevPI integration
  - Installs uv via official installer script

- **Ansible Configuration**:
  - Creates `.ansible.cfg` with:
    - host_key_checking: False
    - inventory: `~/.ansible/inventory/inventory.yaml`
    - remote_user: system_username
    - private_key_file: `/host-ssh/thinkube_cluster_key`
    - interpreter_python: auto_silent
    - roles_path: `/home/thinkube/thinkube-platform/thinkube/ansible/roles`
    - SSH args for connection pooling

- **Inventory Management**:
  - Checks if Ansible inventory exists in pod
  - Copies entire inventory from installer to shared location if missing
  - Updates Python interpreters:
    - Baremetal group: Uses virtualenv `/home/{system_username}/.venv/bin/python3`
    - Controller host: Uses system Python `/usr/bin/python3`

- **Repository Cloning**:
  - Fetches repository list from thinkube-metadata GitHub repo
  - Filters for repositories marked `clone_for_development: true`
  - Clones all development repositories into `/home/thinkube/thinkube-platform/`
  - Updates existing repositories with `git pull` and force reset to `origin/main`
  - Uses GitHub SSH key for authentication

- **CLI Tool Configuration**:
  - **kubectl**: Copies kubeconfig, modifies API server address to `kubernetes.default.svc.cluster.local:443`
  - **GitHub CLI (gh)**: Authenticates with GITHUB_TOKEN if available
  - **ArgoCD**: Creates `~/.config/argocd/config` with server address and deployment token
  - **Argo Workflows**: Creates `~/.config/argo/config` with gRPC server configuration
  - **Gitea (tea CLI)**: Configures `tea login add` with Gitea admin token
  - **Docker/Harbor**: Generates `~/.docker/config.json` with Harbor authentication
  - **Git**: Sets global user.name and user.email, configures SSH for repositories

- **Host Aliases Configuration**:
  - Builds list of cluster nodes with IP addresses
  - Patches code-server deployment with `hostAliases` for DNS resolution
  - Enables container to resolve cluster node hostnames

- **SSH Key Management**:
  - Removes file versions of GitHub SSH keys (converts to symlinks)
  - Creates symlinks: `~/.ssh/github_ed25519` → `/shared-code/.ssh/github_ed25519`
  - Configures git SSH with identity file

- **VS Code Extensions**:
  - **thinkube-ai-integration**: Builds from source, creates symlink to extensions directory
  - **thinkube-cicd-monitor**: Builds and installs for CI/CD monitoring in sidebar
  - **thinkube-theme**: Clones from GitHub and installs custom theme

- **VS Code Settings**:
  - Creates workspace settings file with excluded patterns:
    - Cache, config, local, npm, vscode directories
    - Ansible and SSH configs
    - Git history and temporary files
  - Preserves existing settings while merging template configuration
  - Disables git tracking for ignored files in search

- **CLI Tool Test Scripts**:
  - Creates `test-cli-tools.sh` (Bash)
  - Creates `test-cli-tools.fish` (Fish shell)
  - Scripts verify all CLI tools are functional

### 16_configure_gitea_integration.yaml
Git and CI/CD integration with Gitea:

- **Git Configuration**:
  - Retrieves Gitea admin token from Kubernetes secret
  - Creates `.gitconfig` with:
    - User name and email settings
    - URL rewriting for automatic authentication: `https://gitea.example.com/` → `https://admin:token@gitea.example.com/`
    - Default push behavior: push current branch

- **Example Workflows**:
  - Creates `/shared-code/examples/gitea-workflows/` directory
  - **python-build.yaml**: Workflow for Python projects
    - Triggered on: push to main/develop, pull requests to main
    - Test job: Sets up Python 3.11, installs pytest/flake8, runs tests and linting
    - Build job: Builds container with Podman, pushes to Harbor with commit SHA and latest tags
  - **nodejs-build.yaml**: Workflow for Node.js projects
    - Triggered on: push to main/develop
    - Sets up Node.js 18 with npm caching
    - Installs dependencies, runs tests, builds application
    - Builds and pushes container to Harbor
  - **argo-integration.yaml**: Workflow using Argo Workflows
    - For complex builds requiring Argo Workflows
    - Installs Argo CLI
    - Submits workflow to gRPC Argo server with parameters

- **Helper Scripts**:
  - **create-gitea-repo.sh**: Creates new Gitea repositories via API
    - Usage: `./create-gitea-repo.sh <repo-name> [description]`
    - Calls Gitea REST API POST /api/v1/user/repos
    - Auto-initializes with README
  - **setup-gitea-workflow.sh**: Auto-detects project type and sets up workflow
    - Detects Node.js (package.json) → nodejs-build.yaml
    - Detects Python (requirements.txt/setup.py) → python-build.yaml
    - Generic → argo-integration.yaml
    - Creates `.gitea/workflows/build.yaml`

- **SSH Public Key Distribution**:
  - Reads code-server SSH public key from shared directory
  - Verifies key format (ssh-ed25519)
  - Adds key to authorized_keys on current control plane node
  - Distributes to all control plane nodes in cluster
  - Enables SSH access from code-server to cluster nodes

### 17_configure_discovery.yaml
Service discovery and platform integration:

- **GitHub Token Secret**:
  - Reads GITHUB_TOKEN from environment
  - Creates Kubernetes Secret `github-token` in code-server namespace
  - Only creates if token is available and non-empty

- **Service Discovery ConfigMap**:
  - Creates `thinkube-service-config` ConfigMap in code-server namespace
  - Labels: `thinkube.io/managed`, `thinkube.io/service-type: core`, `thinkube.io/service-name: code-server`
  - Defines service metadata:
    - Display name: "Code Server"
    - Description: "VS Code in the browser"
    - Category: development
    - Icon: /icons/tk_code.svg
  - Endpoint configuration:
    - Web UI: `https://code.example.com`
    - Health check: `https://code.example.com/healthz`
  - Scaling configuration: Deployment code-server, minimum 1 replica, cannot disable
  - Environment variables: GITHUB_TOKEN (from github-token secret)

## Deployment

Code-Server is automatically deployed by the Thinkube installer at deployment order #27. The installer executes the orchestrator playbook (00_install.yaml) which runs all required playbooks in sequence.

No manual intervention is required during installation.

## Access Points

- **Web UI**: https://code.example.com (Keycloak SSO authentication)

Replace `example.com` with your actual domain.

## Configuration

### Authentication and Access

Users must have one of the following Keycloak realm roles to access code-server:
- `code-server-admin`: Full administrative access
- `code-server-user`: Standard developer access

Roles are automatically assigned during deployment for the admin user.

### Shared Code Directory

The shared code directory at `/home/{system_username}/shared-code` on the host is mounted as `/home/thinkube` in the container. This directory is also accessible from JupyterHub, enabling seamless workflow between development and notebook environments.

Default structure:
```
/home/thinkube/
├── .ssh/                      # SSH keys (github_ed25519, id_ed25519)
├── .kube/                     # kubectl configuration
├── .config/                   # Tool configurations (argocd, argo, pip, uv)
├── .venv/                     # Python virtual environment
├── .npm-global/               # npm global packages
├── thinkube-platform/         # Cloned development repositories
├── examples/                  # Example workflows and scripts
│   └── gitea-workflows/       # Gitea CI/CD workflow templates
└── [user projects]            # Your development projects
```

### Shell Environment

The shell environment is unified across bash, zsh, and fish with:

- **Starship Prompt**: Nerd Font-compatible prompt with git status and context
- **Aliases**: Grouped aliases for files, navigation, git, k8s, ansible, devops
- **Functions**: Utility functions for common tasks (mkcd, extract, fif, etc.)
- **Fish Plugins**: bass, fzf.fish, done, autopair.fish

List available aliases:
```bash
aliases                    # List all aliases
aliases --groups           # List alias groups
aliases -g k8s            # Filter by group
```

### Development Tools

Pre-configured CLI tools:

```bash
# Kubernetes
kubectl get pods -n code-server

# Argo Workflows
argo list -n argo
argo submit workflow.yaml

# ArgoCD
argocd app list
argocd app sync my-app

# Gitea (tea CLI)
tea repos list
tea issues list

# GitHub CLI
gh repo list
gh pr list

# Docker/Harbor
docker login harbor.example.com  # Already authenticated
docker pull harbor.example.com/library/image:tag

# Claude Code
claude                     # Interactive AI assistance
```

### Python Environment

Python virtualenv is automatically activated in shell sessions:

```bash
# Package management
pip install package-name   # Uses DevPI index
uv pip install package-name  # Fast alternative

# Pre-installed packages
python -c "import ansible; print(ansible.__version__)"
python -c "import kubernetes; print(kubernetes.__version__)"
```

### CI/CD Integration

#### Gitea Workflows

Create a new repository and set up CI/CD:

```bash
# Create repository
cd ~/examples
./create-gitea-repo.sh my-project "My awesome project"

# Initialize project
cd ~/my-project
./setup-gitea-workflow.sh  # Auto-detects project type

# Push to trigger workflow
git add .
git commit -m "Initial commit"
git push
```

#### Argo Workflows

Submit workflows directly:

```bash
# Submit from template
argo submit -n argo --from workflowtemplate/build-template \
  -p repo-url=https://git.example.com/user/repo.git \
  -p commit-sha=$(git rev-parse HEAD)

# Watch workflow execution
argo watch -n argo workflow-name
```

### VS Code Extensions

Custom Thinkube extensions are pre-installed:

- **thinkube-ai-integration**: Claude Code AI assistance in sidebar
- **thinkube-cicd-monitor**: Real-time CI/CD pipeline monitoring
- **thinkube-theme**: Custom Thinkube color theme

## Troubleshooting

### Check code-server pods
```bash
kubectl get pods -n code-server
kubectl logs -n code-server deploy/code-server
```

### Verify OAuth2 proxy
```bash
kubectl get pods -n code-server -l app=oauth2-proxy
kubectl logs -n code-server deploy/oauth2-proxy

# Check OAuth2 secret
kubectl get secret -n code-server code-server-oauth-secret -o yaml
```

### Verify Valkey session storage
```bash
kubectl get pods -n code-server -l app=ephemeral-valkey
kubectl exec -n code-server deploy/ephemeral-valkey -- redis-cli ping
# Should respond: PONG
```

### Test CLI tools
```bash
# In code-server terminal
~/test-cli-tools.sh        # Bash version
fish ~/test-cli-tools.fish  # Fish version
```

### Verify Keycloak roles
```bash
# Check if user has required role
# Login to Keycloak admin console
# Navigate to Realm → Users → Select user → Role Mappings
# Verify code-server-admin or code-server-user is assigned
```

### Check shared directory mounting
```bash
# Verify hostPath volume
kubectl get deployment -n code-server code-server -o yaml | grep -A 10 volumes

# Verify permissions on host
ls -la /home/{system_username}/shared-code
# Should show: drwxr-xr-x ubuntu ubuntu (or UID 1000:1000)
```

### SSH key issues
```bash
# Verify SSH keys exist
ls -la ~/shared-code/.ssh/
# Should show: github_ed25519, id_ed25519

# Test GitHub SSH access
ssh -T git@github.com
# Should respond: Hi username! You've successfully authenticated...

# Test cluster node access
ssh {node-hostname}
```

### Repository cloning issues
```bash
# Verify GitHub token
echo $GITHUB_TOKEN

# Manually clone a development repository
cd ~/thinkube-platform
git clone git@github.com:thinkube/thinkube-devpi.git
```

### Environment variable issues
```bash
# Verify env setup is sourced
grep "THINKUBE ENV SETUP" ~/.bashrc

# Manually source environment
source ~/env_setup.sh

# Check key variables
echo $KUBECONFIG
echo $ARGO_TOKEN
echo $ANSIBLE_CONFIG
```

## References

- [code-server Documentation](https://coder.com/docs/code-server)
- [OAuth2 Proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Starship Prompt](https://starship.rs/)
- [Gitea Actions](https://docs.gitea.com/usage/actions/overview)
