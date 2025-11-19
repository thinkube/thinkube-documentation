# ADR-003: Authentication Provider (Keycloak)

**Status**: Accepted
**Date**: 2024
**Deciders**: Platform Team
**Technical Story**: Central authentication and SSO for all platform services

## Context

Thinkube platform consists of 45+ components, each requiring authentication. Without centralized auth:
- Users manage multiple passwords
- No single sign-on (SSO)
- Inconsistent access control
- Complex user management

Requirements:
- OIDC/OAuth2 support for modern web apps
- SAML support for enterprise integrations
- User/group management
- Integration with all platform services
- Self-hosted (no cloud dependency)

## Decision

Use **Keycloak** as the central Identity Provider (IdP) and SSO solution for the Thinkube platform.

Deployed as Component #15 at: `https://auth.{domain_name}`

## Consequences

### Positive
- **Single Sign-On**: One login for all platform services
- **Standard protocols**: OIDC, OAuth2, SAML2 support
- **Enterprise features**: Groups, roles, realms, federated identity
- **Battle-tested**: Widely used open-source solution (Red Hat/IBM backed)
- **Extensible**: Custom authenticators, themes, plugins
- **PostgreSQL backend**: Integrates with platform database (#14)
- **OAuth2 Proxy integration**: Protect any HTTP service with SSO

### Negative
- **Resource usage**: Java-based, higher memory footprint (~500MB-1GB)
- **Complexity**: Rich feature set means learning curve
- **Startup time**: Can take 30-60 seconds to start
- **Database dependency**: Requires PostgreSQL

### Neutral
- All platform services integrate via OIDC
- Each service gets dedicated Keycloak client
- Admin realm vs. application realm separation

## Integration Pattern

All authenticated services follow this pattern:

1. **Create Keycloak Client** - OIDC client in `thinkube` realm
2. **Get Client Secret** - For service configuration
3. **Configure Service** - Set OIDC endpoints, client ID, secret
4. **Optional: OAuth2 Proxy** - For services without native OIDC

Examples:
- Harbor (#16) - Native OIDC integration
- JupyterHub (#29) - OAuthenticator
- Grafana, ArgoCD, Gitea - Native OIDC
- pgAdmin (#41), CVAT (#45) - OAuth2 Proxy

## Alternatives Considered

### Alternative 1: Dex
**Description**: Lightweight OIDC provider
**Pros**:
- Smaller footprint (Go-based)
- Simpler configuration
- Fast startup

**Cons**:
- Limited UI
- Fewer enterprise features
- Less community support
- No built-in user management

**Rejected because**: Keycloak's richer feature set worth the resource cost

### Alternative 2: Authelia
**Description**: Authentication server for reverse proxies
**Pros**:
- Lightweight
- Good for simple use cases

**Cons**:
- Not a full IdP
- Limited protocol support
- Smaller ecosystem

**Rejected because**: Not suitable for complex multi-service platform

### Alternative 3: Auth0 / Okta (Cloud)
**Description**: Managed authentication services
**Pros**:
- No maintenance
- Enterprise support
- High availability

**Cons**:
- Cloud dependency (against platform philosophy)
- Recurring costs
- Vendor lock-in
- Data sovereignty concerns

**Rejected because**: Platform must be self-hosted to avoid cloud dependencies

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Keycloak Component README](../components/15_core_keycloak_README.md)
- [OAuth2 Proxy Pattern](../development/authentication-patterns.md) (if created)

---

**Last Updated**: 2025-11-19
**Supersedes**: None
**Superseded By**: None
