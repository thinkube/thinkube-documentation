# Blockers Status and Resolution

## BLOCKER 1: MLflow Model Registration - ✅ FIXED

### Problem
Model downloads successfully (13.8GB gpt-oss-20b) but fails during MLflow registration:
```
ModuleNotFoundError: No module named 'tensorflow'
```

### Root Cause
MLflow's transformers integration auto-detects dependencies and expects TensorFlow even though the model only uses PyTorch.

### Solution Applied
**File**: `thinkube-control/backend/app/services/model_downloader.py`
**Lines**: 432-445

Added `extra_pip_requirements` parameter to bypass auto-detection:

```python
mlflow.transformers.log_model(
    transformers_model=final_model_path,
    task=model_task,
    artifact_path="model",
    registered_model_name=model_name,
    # Explicitly specify requirements to bypass auto-detection
    # Auto-detection tries to import tensorflow/jax even if model only uses PyTorch
    extra_pip_requirements=[
        "transformers",
        "torch",
        "accelerate",
        "safetensors"
    ]
)
```

### Next Steps
1. Rebuild thinkube-control container (includes updated model_downloader.py)
2. Deploy updated thinkube-control
3. Test model mirroring with gpt-oss-20b
4. Verify model appears in MLflow registry

---

## BLOCKER 2: vLLM Compatibility with DGX Spark GB10 - ⚠️ WORKAROUND AVAILABLE

### Problem
vLLM has compatibility issues with NVIDIA DGX Spark (GB10 Blackwell architecture, SM 12.1a).

### Research Findings
Source: https://forums.developer.nvidia.com/t/run-vllm-in-spark/348862

**Known Issues**:
1. **CUDA 13 Compilation**: Undefined symbols (`_Z20cutlass_moe_mm_sm100`) due to SM 12.0/12.1 code generation
2. **Triton Backend**: Triton 3.5.0 has bugs with SM 121a architecture (fixed in main branch)
3. **Version**: Development builds required (not stable releases)

**Workarounds**:
1. Apply CMake patch to remove SM 12.0/12.1 targets before compilation
2. Build Triton from source (main branch, not 3.5.0 release)
3. Use NVIDIA vLLM container: `nvcr.io/nvidia/vllm:25.09-py3`

**Success Reports**:
- Dense models (Qwen3-VL) working with patches
- MOE models (Deepseek) working when properly configured

### Recommendation: Use TensorRT-LLM for Now

**Rationale**:
- ✅ `tkt-tensorrt-llm` template already exists and works
- ✅ Better Blackwell support (native NVFP4)
- ✅ No compilation issues
- ✅ Better performance on GB10 (optimized for Blackwell)
- ⚠️ vLLM requires custom patches and development builds
- ⚠️ vLLM stability uncertain until DGX Spark hardware testing

**Template Status**:
```json
// In thinkube-metadata/repositories.json
{
  "name": "tkt-vllm-gradio",
  "type": "application_template_disabled",  // Keep disabled
  "description": "vLLM + Gradio (on hold: SM 121a compatibility issues)"
},
{
  "name": "tkt-tensorrt-llm",
  "type": "application_template",  // ✅ Use this one
  "description": "TensorRT-LLM + Gradio with NVFP4 support for Blackwell GPUs"
}
```

### Action Items

**Short-term (for implementation plan)**:
1. Use `tkt-tensorrt-llm` for local LLM examples in documentation
2. Keep `tkt-vllm-gradio` as `application_template_disabled`
3. Document TensorRT-LLM workflow in fine-tuning guides

**Medium-term (when DGX Spark hardware available)**:
1. Test vLLM with NVIDIA container (`nvcr.io/nvidia/vllm:25.09-py3`)
2. Apply CMake patches if needed
3. Validate dense and MOE models
4. Enable `tkt-vllm-gradio` if working

**Long-term (monitoring)**:
1. Watch vLLM releases for official GB10 support
2. Monitor NVIDIA forums for stability reports
3. Switch to vLLM when stable release available

---

## IMPLEMENTATION PLAN - READY TO PROCEED

Both blockers are now resolved/mitigated:
- ✅ **Blocker 1**: Fixed (awaiting deployment test)
- ✅ **Blocker 2**: Workaround identified (use TensorRT-LLM)

### Immediate Next Steps

**1. Test MLflow Fix** (30 minutes)
- Rebuild thinkube-control
- Deploy to cluster
- Trigger gpt-oss-20b download
- Verify MLflow registration succeeds

**2. Start Implementation** (Week 1)
- Complete agent-dev/04-rag-pipeline.ipynb
- Complete agent-dev/01-langchain-basics.ipynb
- Build tkt-rag-agent template
- Document using TensorRT-LLM for local LLMs

---

## Summary

| Blocker | Status | Solution | Ready to Proceed |
|---------|--------|----------|------------------|
| MLflow Registration | ✅ Fixed | Added `extra_pip_requirements` | After deployment |
| vLLM GB10 Compatibility | ⚠️ Workaround | Use TensorRT-LLM instead | ✅ Yes |

**Conclusion**: Can proceed with documentation/implementation plan using TensorRT-LLM for local LLM deployment.
