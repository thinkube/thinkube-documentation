# ADR-005: Signed Certificates Only (No Self-Signed)

**Status**: Accepted
**Date**: 2024
**Deciders**: Platform Team
**Technical Story**: TLS certificate strategy for all platform HTTPS endpoints

## Context

All Thinkube platform services are exposed via HTTPS and require TLS certificates. The platform must decide between:
1. Self-signed certificates (generated locally)
2. Signed certificates from a Certificate Authority (CA)

Self-signed certificates create numerous operational problems:
- **Browser warnings**: Users must manually accept security exceptions for every service
- **API client issues**: Tools like curl, wget, Python requests require `--insecure` flags or certificate bundle configuration
- **Component failures**: Harbor and ArgoCD have specific certificate trust requirements that break with self-signed certs
- **Trust chain complexity**: Each client must manually trust the self-signed CA
- **No revocation**: Cannot revoke compromised self-signed certificates
- **Professional appearance**: Self-signed certificates signal "not production-ready"

Critical component incompatibilities:
- **Harbor**: Cannot connect to Keycloak OIDC with self-signed certificates - requires Let's Encrypt intermediate certificate chain explicitly mounted in harbor-core container
- **ArgoCD**: CLI requires `--insecure` flag even with signed certificates due to SSL passthrough, would be completely broken with self-signed certs

Let's Encrypt provides free, automated, signed certificates via the ACME protocol, eliminating all self-signed certificate drawbacks.

## Decision

Thinkube platform will **ONLY support signed certificates** obtained via ACME protocol (Let's Encrypt). Self-signed certificates are not supported.

Certificate management implemented via:
- **acme.sh** - Battle-tested shell script for ACME certificate management
- **ACME DNS-01 challenge** - Validates domain ownership via DNS TXT records
- **Cloudflare DNS integration** - Automated DNS challenge handling
- **Wildcard certificate** - Single cert for `domain.com`, `*.domain.com`, `*.kn.domain.com` covers all services

Deployed at Component #12: ACME Certificates

## Consequences

### Positive
- **No browser warnings**: All services trusted by browsers immediately
- **No client configuration**: curl, wget, Python, etc. work without `--insecure` flags
- **Professional appearance**: Real certificates signal production-ready platform
- **Automatic renewal**: acme.sh handles renewal via cron (every 60 days)
- **Revocation support**: Can revoke compromised certificates via ACME
- **Trust by default**: Certificates trusted by all operating systems and browsers
- **Wildcard support**: One certificate covers unlimited subdomains
- **Rate limit protection**: Checks existing certificate before requesting new one
- **File-based backup**: Certificates exist on filesystem, optionally backed up to encrypted GitHub repository
- **Simple**: No Kubernetes operators or CRDs required

### Negative
- **DNS provider dependency**: Requires Cloudflare account with API access
- **Domain requirement**: Requires a real domain name (cannot use IP addresses)
- **Rate limits**: Let's Encrypt has rate limits (50 certs/week per domain)
- **Internet dependency**: Initial certificate issuance requires internet connectivity

### Neutral
- Certificates stored as both files (`/etc/ssl/thinkube/`) and Kubernetes secrets
- All ingress resources reference the same wildcard certificate secret
- 90-day certificate lifetime (auto-renewed at 60 days)

## Implementation Details

### DNS-01 Challenge Workflow

1. User configures domain DNS to point to Cloudflare
2. acme.sh requests certificate from Let's Encrypt
3. Let's Encrypt responds with DNS challenge: "Add TXT record `_acme-challenge.domain.com` with value `xyz`"
4. acme.sh uses Cloudflare API to create TXT record
5. Let's Encrypt validates TXT record exists
6. Let's Encrypt issues signed certificate
7. acme.sh stores certificate files in `/etc/ssl/thinkube/domain.com/`
8. Playbook creates Kubernetes secret from certificate files
9. Ingress controllers use certificate for HTTPS

### Certificate Coverage

Single multi-domain certificate covers:
- `domain.com` (base domain)
- `*.domain.com` (wildcard for all services)
- `*.kn.domain.com` (Knative serverless functions)

Examples covered:
- `auth.domain.com` (Keycloak)
- `registry.domain.com` (Harbor)
- `jupyter.domain.com` (JupyterHub)
- Any other subdomain

### Automatic Renewal

- Cron job runs daily at random time (load distribution)
- Checks certificate expiry
- Renews if within 30 days of expiration
- Restarts ingress NGINX pods to reload new certificate
- No manual intervention required

### Optional GitHub Backup

If `github_org` and `github_token` are configured:
- Creates private GitHub repository for encrypted certificate backup
- Encrypts certificates with AES-256-CBC using `cert_backup_password`
- Commits and force-pushes on each renewal
- Includes decryption instructions in repository README

## Alternatives Considered

### Alternative 1: Self-Signed Certificates
**Description**: Generate certificates locally using OpenSSL

**Pros**:
- No external dependencies
- Works offline
- No rate limits
- Free

**Cons**:
- **Browser warnings on every service**: Users must click through security warnings
- **Breaks API clients**: curl, wget, Python requests all fail without `--insecure`
- **Trust management nightmare**: Every client must manually trust the CA
- **No revocation**: Cannot revoke compromised certificates
- **Unprofessional appearance**: Signals "not production-ready"
- **Setup friction**: Every new user must accept security exceptions

**Rejected because**: Browser warnings and API client issues create unacceptable user friction. Self-signed certificates are not suitable for a production-ready platform.

### Alternative 2: cert-manager
**Description**: Kubernetes-native certificate management via CRDs and operators

**Pros**:
- Native Kubernetes integration
- Automatic renewal via operator
- Popular in Kubernetes ecosystem

**Cons**:
- **Complexity**: Requires CRDs, operators, multiple Kubernetes resources
- **Resource overhead**: Runs operator pod continuously
- **Base domain issues**: Historically had issues with base domain certificates
- **Let's Encrypt rate limits**: No built-in rate limit protection
- **Overkill**: Certificate management doesn't require Kubernetes-native approach

**Rejected because**: acme.sh provides same functionality with simpler file-based approach, better rate limit protection, and no operator overhead.

### Alternative 3: Commercial CA (DigiCert, Sectigo, etc.)
**Description**: Purchase certificates from commercial Certificate Authority

**Pros**:
- Trusted by all browsers
- Multi-year certificates
- EV certificates available
- 24/7 support

**Cons**:
- **Cost**: $50-300/year per certificate
- **Manual renewal**: Must manually renew and redeploy
- **No automation**: Cannot automate via ACME protocol
- **Overkill**: Free Let's Encrypt provides same trust level

**Rejected because**: Let's Encrypt provides equivalent trust with automation and no cost. Commercial CAs offer no advantage for this use case.

### Alternative 4: HTTP-01 Challenge
**Description**: Use ACME HTTP-01 instead of DNS-01

**Pros**:
- No DNS API required
- Simpler for some setups

**Cons**:
- **No wildcard support**: Must request individual cert for each subdomain
- **Port 80 required**: Must expose port 80 to internet
- **Firewall issues**: Blocked by many corporate firewalls
- **VPN incompatible**: Cannot validate through VPN tunnel

**Rejected because**: DNS-01 provides wildcard certificates and works with VPN deployments. HTTP-01 limitations are unacceptable.

## References

- [acme.sh GitHub Repository](https://github.com/acmesh-official/acme.sh)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [ACME Certificates Component README](../components/12_core_acme-certificates_README.md)
- [Cloudflare DNS API](https://developers.cloudflare.com/api/)

---

**Last Updated**: 2025-11-19
**Supersedes**: None
**Superseded By**: None
