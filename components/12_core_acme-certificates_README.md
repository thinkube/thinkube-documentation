# ACME Certificates Component

This component manages SSL/TLS certificates using acme.sh and Let's Encrypt with Cloudflare DNS validation for all platform services.

## Overview

This is an alternative to cert-manager that provides:
- Simple file-based certificate management
- Rate limit protection (checks before issuing)
- Support for base domain + wildcards (*.thinkube.com, *.kn.thinkube.com)
- Drop-in replacement for cert-manager secrets
- Optional encrypted backup to GitHub

## Dependencies

**Required components** (must be deployed first):
- k8s (deployment order #6) - Kubernetes cluster for secret storage
- coredns (deployment order #10) - DNS resolution for certificate validation

**Required by** (which components depend on this):
- ingress (deployment order #13) - Uses TLS certificates for HTTPS
- All HTTPS services - Require valid SSL certificates

**Deployment order**: #12

See [Deployment Dependency Graph](https://github.com/thinkube/thinkube-documentation/blob/main/architecture/deployment-dependency-graph.md) for complete dependency tree.

## Prerequisites

1. **Cloudflare API Token** with DNS edit permissions
2. **Required inventory variables**:
   ```yaml
   domain_name: thinkube.com
   cloudflare_api_token: your-token-here
   admin_email: admin@example.com
   ```
3. **Optional variables** for GitHub backup:
   ```yaml
   github_org: your-github-org                      # Already required by installer
   github_token: ghp_...                           # Already required by installer
   github_certificates_repo: thinkube-certificates  # Repo name (default)
   cert_backup_password: your-password              # Encryption password (defaults to admin_password)
   ```

## Certificate Coverage

The playbook requests a single certificate covering:
- `thinkube.com` (base domain)
- `*.thinkube.com` (wildcard)
- `*.kn.thinkube.com` (Knative services)

## Playbooks

### 10_deploy.yaml
Main certificate management playbook that issues and maintains Let's Encrypt certificates:

- **Package Installation**:
  - Installs cron and openssl packages
  - Ensures cron service is enabled and running

- **Certificate Directory Setup**:
  - Creates `/etc/ssl/thinkube/{{ domain_name }}/` directory with mode 0700
  - Sets ownership to system user

- **acme.sh Installation**:
  - Clones acme.sh from GitHub (https://github.com/acmesh-official/acme.sh)
  - Installs to `~/.acme.sh/` in system user's home directory
  - Sets Let's Encrypt as default CA
  - Registers account with admin email

- **Cloudflare Validation**:
  - Verifies Cloudflare API token is set in `cloudflare_api_token` variable
  - Uses Cloudflare DNS validation (dns_cf) for certificate issuance

- **Certificate Status Check**:
  - Checks if certificate exists at `/etc/ssl/thinkube/{{ domain_name }}/fullchain.cer`
  - Verifies existing certificate domains match requested domains
  - Checks certificate expiry (30-day threshold for renewal)
  - Determines if renewal is needed

- **Certificate Issuance** (if needed):
  - Issues certificate for `{{ domain_name }}`, `*.{{ domain_name }}`, `*.kn.{{ domain_name }}`
  - Uses ECC P-256 key (`--keylength ec-256`)
  - Saves to `/etc/ssl/thinkube/{{ domain_name }}/`
  - Sets file permissions to 0600
  - Configures reload command to restart ingress NGINX pods on renewal

- **Kubernetes Secret Creation**:
  - Deletes existing secret `{{ domain_name | replace('.', '-') }}-tls` in default namespace (if exists)
  - Creates new TLS secret from certificate and key files
  - Labels secret with `app.kubernetes.io/managed-by=acme.sh` and `app.kubernetes.io/name=wildcard-certificate`

- **GitHub Backup** (optional, if `github_org` and `github_token` are defined):
  - Creates private GitHub repository `{{ github_certificates_repo }}` (default: "thinkube-certificates")
  - Encrypts certificate and key files with AES-256-CBC using `cert_backup_password`
  - Creates README with decryption and restore instructions
  - Creates backup metadata JSON file
  - Commits and force-pushes encrypted backup to GitHub

- **Automatic Renewal**:
  - Creates cron job for acme.sh automatic renewal
  - Runs at random minute/hour daily to distribute load
  - Executes `~/.acme.sh/acme.sh --cron`

## Deployment

### Deploy certificates:
```bash
cd ~/thinkube
./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/acme-certificates/10_deploy.yaml
```

### Migration from cert-manager:

1. First ensure you have the required variable in inventory:
   ```yaml
   cloudflare_api_token: "your-cf-api-token"
   ```

2. Run the acme.sh deployment:
   ```bash
   ./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/acme-certificates/10_deploy.yaml
   ```

3. Verify the secret was created:
   ```bash
   kubectl get secret -n default thinkube-com-tls
   ```

4. Remove cert-manager (optional):
   ```bash
   ./scripts/run_ansible.sh ansible/40_thinkube/core/infrastructure/cert-manager/19_rollback.yaml
   ```

## How it Works

1. **Installation**: Installs acme.sh in the user's home directory
2. **Certificate Check**: Verifies if existing certificate is valid and has correct domains
3. **Rate Limit Protection**: Only requests new certificate if:
   - No certificate exists
   - Certificate expires within 30 days
   - Domain list has changed
4. **Kubernetes Integration**: Creates the same secret format as cert-manager
5. **GitHub Backup** (optional): If github_org and github_token are defined:
   - Creates private repository for certificate backups
   - Encrypts certificates before storing
   - Automatically backs up when certificates are issued/renewed
6. **Auto-renewal**: Sets up cron job for automatic renewal

## Certificate Locations

- **Files**: `/etc/ssl/thinkube/thinkube.com/`
- **Kubernetes Secret**: `default/thinkube-com-tls`

## Advantages over cert-manager

1. **Rate limit friendly**: Checks before issuing
2. **Simpler**: No CRDs, operators, or complex configurations
3. **Base domain support**: Can issue certificates for base domain
4. **File backup**: Certificates exist on filesystem for easy backup
5. **Proven reliability**: acme.sh is battle-tested

## Troubleshooting

### Check certificate status:
```bash
openssl x509 -in /etc/ssl/thinkube/thinkube.com/fullchain.cer -text -noout
```

### Manual renewal:
```bash
sudo -u <system_username> ~/.acme.sh/acme.sh --renew -d thinkube.com --force
```

### View acme.sh logs:
```bash
tail -f ~/.acme.sh/acme.sh.log
```

## 🤖 [AI-assisted]