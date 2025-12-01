# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Primary Mission

Build the **AI Research Lab Assistant** application while documenting the development process. This is documentation-driven development - we build real working code and document as we go.

**Application Goal**: AI assistant for managing ML/AI papers and experiments that:
- Ingests and indexes ArXiv papers
- Answers research questions using RAG
- Summarizes papers and extracts findings
- Links papers to MLflow experiments
- Uses multi-agent coordination

## Platform Architecture: 100% Self-Contained

Thinkube runs entirely on-premise with no external API dependencies:

| Capability | Template/Service | Model |
|------------|------------------|-------|
| **Chat/Completion** | `tkt-tensorrt-llm` | GPT-OSS 20B, Llama, Qwen, Phi (via TensorRT-LLM) |
| **Embeddings** | `tkt-text-embeddings` | nomic-embed-text-v1.5 (Apache 2.0) |
| **LLM Gateway** | LiteLLM | Routes to local models |

Models are stored in MLflow Model Registry (on SeaweedFS/JuiceFS) and mounted at runtime.

## Notebooks (in thinkube-ai-examples repo)

The implementation lives in `thinkube-ai-examples/`:

```
thinkube-ai-examples/
├── 00-platform-validation.ipynb   # Validate 7 platform services
├── 01-register-litellm.ipynb      # Register LLM & embeddings in LiteLLM
└── research-assistant/
    ├── 02-langchain-rag.ipynb     # RAG pipeline for papers
    ├── 03-multi-agent.ipynb       # CrewAI multi-agent system
    └── 04-fine-tuning.ipynb       # Unsloth fine-tuning
```

**Current state**:
- `00-platform-validation.ipynb` - Educational framework complete
- `01-register-litellm.ipynb` - Complete - registers models in LiteLLM
- `02-langchain-rag.ipynb` - Structure only, needs implementation
- `03-multi-agent.ipynb` - Structure only, needs implementation
- `04-fine-tuning.ipynb` - Structure only, needs implementation

## Getting Started Guide

See `guides/thinkube-ai-lab-getting-started.md` for the full setup flow:

1. Download models (GPT-OSS 20B, nomic-embed-text-v1.5)
2. Deploy services (tkt-tensorrt-llm, tkt-text-embeddings)
3. Start JupyterHub and run setup notebooks (00, 01)
4. Build the Research Assistant (02, 03, 04)

## Platform Services

| Service | Purpose | Key Environment Variables |
|---------|---------|---------------------------|
| LiteLLM | LLM gateway | `LITELLM_ENDPOINT`, `LITELLM_MASTER_KEY` |
| Qdrant | Vector database | `QDRANT_URL` |
| Langfuse | Observability | `LANGFUSE_HOST`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY` |
| MLflow | Experiment tracking | `MLFLOW_TRACKING_URI` + OAuth vars |
| PostgreSQL | Metadata storage | `POSTGRES_HOST`, `POSTGRES_PASSWORD` |
| Valkey | Caching | `VALKEY_HOST`, `VALKEY_PORT` |
| NATS | Agent messaging | `NATS_URL` |

## Documentation to Create

Write guides in `guides/` as notebooks are completed:

| Guide | Status | Content |
|-------|--------|---------|
| `thinkube-ai-lab-getting-started.md` | ✅ Complete | Full setup flow |
| `platform-services-integration.md` | Pending | Service connection patterns |
| `fine-tuning-for-agents.md` | Pending | Unsloth workflow |
| `ai-agent-development-lifecycle.md` | Pending | Complete lifecycle |

## Implementation Approach

1. **Work in JupyterHub** - Use `tk-jupyter-agent-dev` or `tk-jupyter-fine-tuning` images
2. **No TODO stubs** - Every cell must execute
3. **Real services** - Connect to actual platform, not mocks
4. **Document issues** - If something doesn't work, document why

## Key Specifications

Reference these when building:
- `specs/thinkube-yaml-v1.0.md` - Deployment descriptor format
- `specs/template-manifest-v1.0.md` - Template repository structure
- `specs/health-endpoints-v1.0.md` - Health check requirements

## Current Status

Check `BLOCKERS_STATUS.md` for blockers and issues.

## Related Repositories

| Repository | Path | Purpose |
|------------|------|---------|
| thinkube-ai-examples | `/home/thinkube/thinkube-platform/thinkube-ai-examples/` | Notebook implementations |
| thinkube-control | `/home/thinkube/thinkube-platform/thinkube-control/` | Deployment backend |
| thinkube | `/home/thinkube/thinkube-platform/thinkube/` | Infrastructure playbooks |
