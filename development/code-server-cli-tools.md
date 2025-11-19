# code-server CLI Tools Inventory

Complete inventory of CLI tools available in the code-server development environment.

**Last Updated**: 2025-11-19

---

## How Tools Are Installed

Tools are installed in three ways:

1. **Pre-installed in Docker image** (`code-server-dev.Containerfile.j2`) - Available immediately when pod starts
2. **Auto-installed by deployment playbooks** (`15_configure_environment.yaml`) - Installed during environment setup
3. **Manual installation required** - User must install themselves

---

## Platform Core Tools

### 1. kubectl - Kubernetes CLI
**Status**: ✅ Pre-installed in image
**Version**: v1.30.0
**Source**: Containerfile line 282-284
**Configuration**: Auto-configured by playbook (kubeconfig at `~/.kube/config`)

### 2. helm - Kubernetes Package Manager
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 287
**Configuration**: Uses same kubeconfig as kubectl

### 3. k9s - Terminal UI for Kubernetes
**Status**: ✅ Pre-installed in image
**Version**: v0.32.0
**Source**: Containerfile line 290-293

### 4. podman - Container Management
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 129
**Note**: Platform uses Podman exclusively (Docker is banned)
**Additional**: Also includes `skopeo` and `podman-compose`

### 5. git - Version Control
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 35
**Configuration**: Auto-configured by playbook (user.name, user.email, SSH keys)

---

## Kubernetes Extended Tools

### 6. stern - Multi-pod Log Tailing
**Status**: ✅ Pre-installed in image
**Version**: v1.28.0
**Source**: Containerfile line 296-299

### 7. kubectx / kubens - Context/Namespace Switcher
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 302-304

---

## Argo Tools (Workflows + CD)

### 8. argo - Argo Workflows CLI
**Status**: ✅ Pre-installed in image
**Version**: v3.5.5
**Source**: Containerfile line 311-314
**Configuration**: Auto-configured by playbook (config at `~/.config/argo/config`)

### 9. argocd - ArgoCD CLI
**Status**: ✅ Pre-installed in image
**Version**: v2.10.0
**Source**: Containerfile line 317-319
**Configuration**: Auto-configured by playbook (config at `~/.config/argocd/config`)

---

## Git Tools

### 10. gh - GitHub CLI
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 326-333
**Configuration**: Auto-configured by playbook with GitHub token

### 11. tea - Gitea CLI
**Status**: ✅ Pre-installed in image
**Version**: 0.9.2
**Source**: Containerfile line 336-337
**Configuration**: Auto-configured by playbook with Gitea token

---

## Messaging & Service CLIs

### 12. nats - NATS CLI
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 344-345

---

## Development Tools

### 13. jq - JSON Processor
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 54 (apt package)

### 14. yq - YAML Processor
**Status**: ✅ Pre-installed in image
**Version**: v4.40.5
**Source**: Containerfile line 348-349

### 15. ripgrep - Fast Text Search
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 147

### 16. fd - Fast File Finder
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 148
**Note**: Symlinked as `fd` (from `fdfind`)

### 17. bat - Enhanced Cat with Syntax Highlighting
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 149
**Note**: Symlinked as `bat` (from `batcat`)

### 18. httpie - HTTP Client
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 150

### 19. curl - HTTP Client
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 33

---

## Database Clients

### 20. psql - PostgreSQL CLI Client
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 138 (postgresql-client)

### 21. redis-cli - Redis/Valkey Client
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 139 (redis-tools)

---

## Python Runtime & Tools

### 22. python3 - Python Runtime
**Status**: ✅ Pre-installed in image
**Version**: 3.12
**Source**: Containerfile line 41-42

### 23. pip - Python Package Installer
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 44

### 24. uv - Fast Python Package Manager
**Status**: ✅ Auto-installed by playbook
**Source**: 15_configure_environment.yaml line 329-331

---

## Python Packages (Installed in ~/.venv)

These are installed by `15_configure_environment.yaml` (lines 304-326) into `/home/thinkube/.venv`:

### 25. ansible & ansible-core - Infrastructure Automation
**Status**: ✅ Auto-installed by playbook
**Configuration**: Auto-configured with inventory at `~/.ansible/inventory/`

### 26. copier - Project Scaffolding
**Status**: ✅ Auto-installed by playbook

### 27. ansible-lint - Ansible Linting
**Status**: ✅ Auto-installed by playbook

### 28. mlflow - ML Experiment Tracking
**Status**: ✅ Auto-installed by playbook

### 29. devpi-client - Python Package Registry
**Status**: ✅ Auto-installed by playbook

### 30. kubernetes - Python Kubernetes Client
**Status**: ✅ Auto-installed by playbook

### 31. Service SDKs
**Status**: ✅ Auto-installed by playbook
**Packages**:
- opensearch-py
- weaviate-client
- langfuse
- argilla
- clickhouse-connect
- cvat-cli
- requests
- psycopg2-binary
- boto3
- redis (Python client)
- qdrant-client
- nats-py
- chromadb

---

## Node.js & NPM

### 32. node - Node.js Runtime
**Status**: ✅ Pre-installed in image
**Version**: 20.x LTS
**Source**: Containerfile line 83-85

### 33. npm - Node Package Manager
**Status**: ✅ Pre-installed in image
**Configuration**: Configured for global installs at `~/.npm-global`

### 34. claude - Claude Code CLI
**Status**: ✅ Auto-installed by playbook
**Source**: 15_configure_environment.yaml line 269-291
**Installed via**: npm global (`@anthropic-ai/claude-code`)

---

## Shells & Prompts

### 35. bash - Bourne Again Shell
**Status**: ✅ Pre-installed in image
**Default shell**: Yes

### 36. zsh - Z Shell
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 56

### 37. fish - Friendly Interactive Shell
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 57

### 38. starship - Cross-shell Prompt
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 274

---

## System Utilities

### 39. vim - Text Editor
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 48

### 40. nano - Text Editor
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 49

### 41. tree - Directory Tree Viewer
**Status**: ✅ Pre-installed in image
**Source**: Containerfile line 51

---

## Not Installed (Would Require Image Rebuild)

The following tools are **NOT** installed by image or playbooks.

**IMPORTANT**: Manual installation inside the pod will NOT persist across pod restarts. To add these tools permanently, they must be added to the Containerfile and the image rebuilt.

- pnpm - Fast Node package manager (could add to Containerfile)
- clickhouse-client - ClickHouse database client CLI (Python client `clickhouse-connect` is installed)
- just - Command runner (could add to Containerfile)

To add tools permanently:
1. Edit `ansible/40_thinkube/core/harbor-images/base-images/code-server-dev.Containerfile.j2`
2. Rebuild image: `./scripts/run_ansible.sh ansible/40_thinkube/core/harbor-images/16_build_codeserver_image.yaml`
3. Redeploy code-server: `./scripts/run_ansible.sh ansible/40_thinkube/core/code-server/19_rollback.yaml && ./scripts/run_ansible.sh ansible/40_thinkube/core/code-server/10_deploy.yaml`

---

## Installation Summary

**Pre-installed in image** (from code-server-dev.Containerfile.j2):
- 31 tools total including kubectl, helm, k9s, podman, argo, argocd, gh, tea, nats, jq, yq, ripgrep, fd, bat, httpie, psql, redis-cli, python3, node, npm, git, stern, kubectx/kubens, vim, nano, tree, curl, bash, zsh, fish, starship

**Auto-installed by playbooks** (from 15_configure_environment.yaml):
- uv (Python package manager)
- claude (Claude Code CLI via npm)
- ansible + 20+ Python packages in virtualenv

**Not installed** (would require image rebuild to add permanently):
- pnpm
- clickhouse-client CLI
- just

---

## Verification

To verify all tools are available, run inside code-server:

```bash
# From Bash
./test-cli-tools.sh

# From Fish
fish test-cli-tools.fish
```

Test scripts are auto-generated by deployment playbooks.

---

## See Also

- [code-server Deployment Guide](../operations/code-server-deployment-guide.md)
- [Developer Workflow](developer-workflow.md)
- Code-server Containerfile: `ansible/40_thinkube/core/harbor-images/base-images/code-server-dev.Containerfile.j2`
- Environment Setup: `ansible/40_thinkube/core/code-server/15_configure_environment.yaml`
