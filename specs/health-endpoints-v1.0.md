# Health Endpoints Specification v1.0

## Purpose
Defines the standard for health check endpoints in Thinkube applications to ensure consistency, reliability, and proper integration with Kubernetes health probes.

## Philosophy
**Simple, Consistent, Version-Independent**

- All containers must expose a health endpoint
- Use the same path across all components
- Keep health checks lightweight and fast
- Provide consistent response format

## Standard Health Endpoint

### Path
```
/health
```

**Rationale**:
- Version-independent (not `/api/v1/health`)
- Consistent across all container types
- Simple for Kubernetes probe configuration
- No authentication required

### HTTP Method
```
GET /health
```

### Response Format

#### Success Response
- **Status Code**: 200 OK
- **Content-Type**: application/json
- **Body**:
```json
{
  "status": "healthy",
  "component": "<component-name>",
  "service": "<service-name>"  // Optional: for backend services
}
```

#### Fields
- `status`: Always "healthy" for 200 responses
- `component`: The container name from thinkube.yaml (e.g., "backend", "frontend", "worker")
- `service`: Optional field for backend services containing the project name

### Implementation Examples

#### FastAPI Backend
```python
# In app/__init__.py or main.py
@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": settings.PROJECT_NAME,
        "component": "backend"
    }
```

#### Frontend (Nginx)
```nginx
# In nginx.conf
location /health {
    access_log off;
    add_header Content-Type application/json;
    return 200 '{"status":"healthy","component":"frontend"}';
}
```

#### Node.js Service
```javascript
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        component: 'worker',
        service: process.env.PROJECT_NAME
    });
});
```

## thinkube.yaml Declaration

Every container in thinkube.yaml MUST declare its health endpoint:

```yaml
spec:
  containers:
    - name: backend
      build: ./backend
      port: 8000
      health: /health  # Required
      
    - name: frontend
      build: ./frontend
      port: 80
      health: /health  # Required
      
    - name: worker
      build: ./worker
      # No port needed for workers
      health: /health  # Still required
```

## Kubernetes Integration

The health endpoint is used for both liveness and readiness probes:

```yaml
livenessProbe:
  httpGet:
    path: /health  # From thinkube.yaml
    port: <container-port>
  initialDelaySeconds: 30
  periodSeconds: 10
  
readinessProbe:
  httpGet:
    path: /health  # Same endpoint
    port: <container-port>
  initialDelaySeconds: 5
  periodSeconds: 5
```

## Requirements

### Performance
- Response time < 100ms
- No database queries
- No external service calls
- Minimal CPU/memory usage

### Availability
- Must work immediately after process starts
- No initialization dependencies
- No authentication required
- Available before other routes initialize

### Security
- No sensitive information in response
- No application internals exposed
- Read-only operation
- No side effects

## Anti-Patterns to Avoid

### ❌ Version-Specific Paths
```python
# BAD: Tied to API version
@app.get("/api/v1/health")
```

### ❌ Complex Health Checks
```python
# BAD: Too much logic
@app.get("/health")
async def health():
    db_status = check_database()  # NO!
    redis_status = check_redis()   # NO!
    return {"db": db_status, "redis": redis_status}
```

### ❌ Inconsistent Responses
```python
# BAD: Different format
@app.get("/health")
async def health():
    return "OK"  # Should be JSON
```

### ❌ Missing Component Identification
```python
# BAD: No component info
@app.get("/health")
async def health():
    return {"status": "healthy"}  # Missing component
```

## Testing Requirements

### Manual Testing
```bash
# Should return 200 with JSON
curl http://localhost:8000/health

# Expected response:
{
  "status": "healthy",
  "component": "backend",
  "service": "my-app"
}
```

### Automated Testing
Templates must include health endpoint tests:

```python
def test_health_endpoint(client):
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "component" in data
```

## Migration Guide

For existing applications:

1. **Remove versioned health endpoints** (e.g., `/api/v1/health`)
2. **Add root `/health` endpoint** with standard response
3. **Update thinkube.yaml** to declare `health: /health`
4. **Test locally** before deployment
5. **Deploy** using standard playbook

## Compliance Checklist

- [ ] Health endpoint at `/health` (not versioned)
- [ ] Returns 200 OK when healthy
- [ ] JSON response with required fields
- [ ] Component identification included
- [ ] Declared in thinkube.yaml
- [ ] No external dependencies
- [ ] Response time < 100ms
- [ ] No authentication required

## Version History

- **v1.0** (2024-01-29) - Initial specification
  - Standardized on `/health` path
  - Defined JSON response format
  - Required component identification