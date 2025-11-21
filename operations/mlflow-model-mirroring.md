# MLflow Model Mirroring System

## Overview

The MLflow Model Mirroring system automatically downloads and registers AI models from HuggingFace Hub into the Thinkube MLflow Model Registry. This system uses a custom workaround to handle MLflow 3.0+ architecture changes and ensure proper artifact visibility in the MLflow UI.

## Architecture

### Components

1. **Backend API Endpoint** (`/api/models/mirror`)
   - Location: `thinkube-control/backend/app/routes/model_routes.py`
   - Receives model mirroring requests from the frontend
   - Validates model parameters
   - Triggers Argo Workflow

2. **Model Downloader Service** (`model_downloader.py`)
   - Location: `thinkube-control/backend/app/services/model_downloader.py`
   - Creates Argo Workflows for model downloads
   - Implements manual S3 upload workaround
   - Handles model registration using MLflow Client API

3. **Argo Workflow**
   - Orchestrates the model download and registration process
   - Runs in isolated Kubernetes pod with GPU support
   - Uses Harbor registry image: `registry.{domain}/library/model-mirror:latest`

4. **Storage Backend**
   - **SeaweedFS**: S3-compatible object storage for model artifacts
   - **MLflow Database**: PostgreSQL for run metadata and model registry

### Workflow Flow

```
User Request → Backend API → Argo Workflow → Download Model → Upload to S3 → Register in MLflow
```

## MLflow 3.0+ Challenge and Solution

### The Problem

MLflow 3.0+ introduced a "Logged Models" API that fundamentally changed where model artifacts are stored:

- **Old behavior**: Artifacts stored at `s3://mlflow/artifacts/{run_id}/model`
- **New behavior (Logged Models)**: Artifacts stored at `s3://mlflow/artifacts/models/m-{model_id}/artifacts/`

**Impact:**
- Using `mlflow.transformers.log_model()` stores artifacts in the new location
- The MLflow UI looks for artifacts at the run location
- Result: UI shows "No Artifacts Recorded" even though artifacts exist in S3

**Root Cause:**
In MLflow's `runs_artifact_repo.py:177`, the `_list_model_artifacts()` method returns an empty list when called without a path parameter:

```python
def _list_model_artifacts(self, path: str | None = None) -> list[FileInfo]:
    full_path = f"{self.artifact_uri}/{path}" if path else self.artifact_uri
    run_id, rel_path = RunsArtifactRepository.parse_runs_uri(full_path)
    if not rel_path:
        # At least one part of the path must be present
        return []  # <-- Returns empty for basic list_artifacts(run_id)
```

### The Solution: Manual S3 Upload + create_model_version

We implement a **manual S3 upload workaround** that:
1. Downloads model from HuggingFace
2. Manually uploads artifacts to the run's S3 location using boto3
3. Registers the model using `client.create_model_version()` (not `mlflow.register_model()`)

This ensures:
- ✅ Artifacts are visible when viewing runs in MLflow UI
- ✅ Models can be registered in the Model Registry
- ✅ Users can browse and download artifacts from the UI
- ✅ Model versions show as "READY" in the registry

## Implementation Details

### 1. S3 Artifact Path Calculation

**Critical:** MLflow's run artifact URI includes an `/artifacts` subdirectory that must be extracted:

```python
run_id = run.info.run_id
# Extract S3 path from artifact_uri to get correct path with /artifacts subdirectory
# e.g., s3://mlflow/artifacts/{run_id}/artifacts -> artifacts/{run_id}/artifacts
artifact_uri = run.info.artifact_uri
s3_base_path = artifact_uri.replace('s3://mlflow/', '')
s3_artifact_prefix = f'{s3_base_path}/model'
```

**Example:**
- Artifact URI: `s3://mlflow/artifacts/abc123/artifacts`
- Extracted path: `artifacts/abc123/artifacts`
- Upload prefix: `artifacts/abc123/artifacts/model`

**Bug if done wrong:**
```python
# WRONG: Hard-coded path missing /artifacts subdirectory
s3_artifact_prefix = f'artifacts/{run_id}/model'  # Missing /artifacts!
```

### 2. Manual File Upload

Upload all model files and MLflow metadata to S3:

```python
# Upload model files
for root, dirs, files in os.walk(temp_model_path):
    for file in files:
        local_path = os.path.join(root, file)
        relative_path = os.path.relpath(local_path, temp_model_path)
        s3_key = f'{s3_artifact_prefix}/{relative_path}'

        with open(local_path, 'rb') as f:
            s3_client.put_object(
                Bucket=s3_bucket,
                Key=s3_key,
                Body=f
            )

# Create and upload MLflow metadata
temp_mlmodel_dir = tempfile.mkdtemp()
mlflow.transformers.save_model(
    transformers_model=temp_model_path,
    path=temp_mlmodel_dir,
    task=model_task
)

# Upload metadata files (MLmodel, requirements.txt, conda.yaml, python_env.yaml)
for metadata_file in ['MLmodel', 'requirements.txt', 'conda.yaml', 'python_env.yaml']:
    metadata_path = os.path.join(temp_mlmodel_dir, metadata_file)
    if os.path.exists(metadata_path):
        s3_key = f'{s3_artifact_prefix}/{metadata_file}'
        with open(metadata_path, 'rb') as f:
            s3_client.put_object(Bucket=s3_bucket, Key=s3_key, Body=f)
```

### 3. Model Registration Using create_model_version

**Critical:** Use `client.create_model_version()` instead of `mlflow.register_model()`:

```python
model_uri = f'runs:/{run_id}/model'

client = mlflow.MlflowClient()

# Ensure registered model exists
try:
    client.create_registered_model(model_name)
except Exception as e:
    if 'already exists' not in str(e).lower():
        print(f'Warning creating registered model: {e}', flush=True)

# Create model version (what the UI uses)
version = client.create_model_version(
    name=model_name,
    source=model_uri,
    run_id=run_id
)
```

**Why not `mlflow.register_model()`?**
- `register_model()` requires a `logged_model` database entry
- Manual uploads don't create this database entry
- `create_model_version()` is what the MLflow UI uses and works with manual uploads

### 4. Required Environment Variables

The workflow pod must have these environment variables:

```python
# MLflow tracking
MLFLOW_TRACKING_URI: "http://mlflow.mlflow.svc.cluster.local:5000"
MLFLOW_TRACKING_TOKEN: "{keycloak_access_token}"

# S3 configuration for direct uploads
AWS_ACCESS_KEY_ID: "seaweedfs"
AWS_SECRET_ACCESS_KEY: "{seaweedfs_password}"
AWS_S3_ENDPOINT: "http://seaweedfs-filer.seaweedfs.svc.cluster.local:8333"
AWS_DEFAULT_REGION: "us-east-1"

# MLflow S3 configuration for artifact listing/reading
MLFLOW_S3_ENDPOINT_URL: "http://seaweedfs-filer.seaweedfs.svc.cluster.local:8333"
MLFLOW_S3_IGNORE_TLS: "true"
```

## Code Locations

### Main Implementation

**File:** `thinkube-control/backend/app/services/model_downloader.py`

**Key sections:**
- Lines 501-506: S3 path calculation from artifact_uri
- Lines 508-526: Model file upload loop
- Lines 528-551: MLflow metadata creation and upload
- Lines 553-573: Model registration using create_model_version

### API Endpoint

**File:** `thinkube-control/backend/app/routes/model_routes.py`

**Endpoint:** `POST /api/models/mirror`

**Request body:**
```json
{
  "model_id": "gpt2",
  "model_name": "gpt2",
  "task": "text-generation"
}
```

## MLflow Server Configuration

The MLflow server must be configured with `--default-artifact-root` (NOT `--serve-artifacts`):

```yaml
command:
  - mlflow
  - server
  - --host=0.0.0.0
  - --port=5000
  - --backend-store-uri=postgresql://...
  - --default-artifact-root=s3://mlflow/artifacts
  # DO NOT USE: --serve-artifacts (causes OOM and prevents direct uploads)
```

**Why `--default-artifact-root`?**
- Allows clients to upload directly to S3
- Server doesn't proxy artifact uploads (prevents OOM)
- Necessary for manual boto3 uploads to work

## Testing

A complete test script is available at `/home/thinkube/test-complete-workflow.py` that demonstrates:

1. Model download from HuggingFace
2. Manual S3 upload to correct path
3. Artifact visibility verification via `client.list_artifacts()`
4. Model registration using `create_model_version()`
5. Direct S3 verification

**Run test:**
```bash
cd /home/thinkube
source .venv/bin/activate
python3 test-complete-workflow.py
```

**Expected output:**
- ✅ Artifacts visible in UI
- ✅ Model registered with READY status
- ✅ All files present in S3

## Monitoring

### Check Workflow Status

```bash
kubectl get workflows -n argo-workflows
```

### View Workflow Logs

```bash
kubectl logs -n argo-workflows -l workflows.argoproj.io/workflow={workflow-name} --tail=100
```

### Check MLflow Run

Navigate to MLflow UI:
- Experiments: https://mlflow.{domain}/#/experiments
- Specific run: https://mlflow.{domain}/#/experiments/{exp_id}/runs/{run_id}
- Model registry: https://mlflow.{domain}/#/models/{model_name}

### Verify S3 Artifacts

```bash
kubectl exec -it deployment/seaweedfs-filer -n seaweedfs -- \
  weed shell <<EOF
fs.ls /buckets/mlflow/artifacts/{run_id}/artifacts/model/
EOF
```

## Troubleshooting

### Issue: "No Artifacts Recorded" in MLflow UI

**Symptom:** MLflow UI shows no artifacts when viewing run

**Causes:**
1. Wrong S3 upload path (missing `/artifacts` subdirectory)
2. Missing MLFLOW_S3_ENDPOINT_URL environment variable
3. Artifacts uploaded to logged model location instead of run location

**Solution:**
- Verify S3 path extracted from `run.info.artifact_uri`
- Check artifacts exist: `s3://mlflow/artifacts/{run_id}/artifacts/model/`
- Ensure environment variables are set correctly

### Issue: Model Registration Fails

**Symptom:** `MlflowException: Unable to find a logged_model with artifact_path`

**Cause:** Using `mlflow.register_model()` which requires logged_model database entry

**Solution:** Use `client.create_model_version()` instead (lines 568-572 in model_downloader.py)

### Issue: MLflow Server OOM (Out of Memory)

**Symptom:** MLflow server crashes when uploading large models

**Cause:** Using `--serve-artifacts` flag, causing server to proxy all uploads

**Solution:**
- Remove `--serve-artifacts` flag
- Use `--default-artifact-root=s3://mlflow/artifacts`
- This enables direct client-to-S3 uploads

## Historical Context

This implementation was developed after discovering that MLflow 3.0+ Logged Models API doesn't make artifacts visible in the run UI. After 5+ days of debugging and multiple approaches:

1. **Attempted:** Using `mlflow.transformers.log_model()` with `registered_model_name`
   - Result: Models registered but artifacts not visible in run UI

2. **Attempted:** Using MLflow server `--serve-artifacts` mode
   - Result: Server OOM crashes on large models

3. **Final Solution:** Manual S3 upload + `create_model_version()`
   - Result: ✅ Artifacts visible, ✅ Registration works, ✅ No OOM issues

## Related Documentation

- MLflow Logged Models API: https://mlflow.org/docs/latest/models.html
- MLflow Model Registry: https://mlflow.org/docs/latest/model-registry.html
- Argo Workflows: https://argoproj.github.io/argo-workflows/

## Maintenance Notes

**When upgrading MLflow:**
- Test that manual S3 upload still works
- Verify artifact_uri format hasn't changed
- Check if `create_model_version()` API remains stable

**When modifying model_downloader.py:**
- Do NOT change S3 path calculation (lines 502-506)
- Do NOT switch back to `mlflow.register_model()`
- Always test with `client.list_artifacts()` to verify UI visibility
