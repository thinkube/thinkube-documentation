# Thinkube AI Lab: Getting Started

This guide walks you through setting up a complete, self-contained AI development environment on Thinkube.

## Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Setup Flow                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Download Models (Thinkube Control → Model Catalog)              │
│     ├── Chat LLM: openai/gpt-oss-20b (MXFP4)                        │
│     └── Embedding: nomic-ai/nomic-embed-text-v1.5                   │
│              ↓                                                       │
│  2. Deploy Services (Thinkube Control → Templates)                  │
│     ├── tkt-tensorrt-llm → verify via Gradio UI                    │
│     └── tkt-text-embeddings → verify via Gradio UI                 │
│              ↓                                                       │
│  3. Start Thinkube AI Lab (JupyterHub)                              │
│     ├── 00-platform-validation.ipynb                                │
│     └── 01-register-litellm.ipynb                                   │
│              ↓                                                       │
│  4. Build the Research Assistant                                     │
│     ├── research-assistant/02-langchain-rag.ipynb                   │
│     ├── research-assistant/03-multi-agent.ipynb                     │
│     └── research-assistant/04-fine-tuning.ipynb                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Thinkube platform deployed with AI components
- Access to Thinkube Control (`https://control.{domain}`)
- Access to JupyterHub (`https://jupyter.{domain}`)
- DGX Spark or GPU node available

## Step 1: Download Models

Models are downloaded from HuggingFace and stored in MLflow Model Registry.

### Open Thinkube Control

Navigate to `https://control.{domain}` → **Model Catalog**

### Download Chat LLM

| Field | Value |
|-------|-------|
| Model | `openai/gpt-oss-20b` |
| Quantization | MXFP4 |
| Size | ~10GB |

1. Find `openai/gpt-oss-20b` in the catalog
2. Click **Download**
3. Wait for completion (progress shown in UI)

### Download Embedding Model

| Field | Value |
|-------|-------|
| Model | `nomic-ai/nomic-embed-text-v1.5` |
| License | Apache 2.0 |
| Size | ~550MB |

1. Find `nomic-ai/nomic-embed-text-v1.5` in the catalog
2. Click **Download**
3. Wait for completion

## Step 2: Deploy Services

### Deploy Chat LLM

1. Navigate to **Templates** → `tkt-tensorrt-llm`
2. Select your downloaded model: `openai/gpt-oss-20b`
3. Configure:
   - **Name**: `gpt-oss` (or your preference)
   - **Namespace**: default or dedicated
4. Click **Deploy**
5. Wait for pod to become healthy

**Verify**: Open the Gradio UI link and test with a prompt:
```
User: Hello, how are you?
```

### Deploy Embedding Service

1. Navigate to **Templates** → `tkt-text-embeddings`
2. Select: `nomic-ai/nomic-embed-text-v1.5`
3. Configure:
   - **Name**: `nomic-embed` (or your preference)
4. Click **Deploy**
5. Wait for pod to become healthy

**Verify**: Open the Gradio UI and test embedding generation.

## Step 3: Start Thinkube AI Lab

### Launch JupyterHub

1. Navigate to `https://jupyter.{domain}`
2. Login with your credentials
3. Select image: **tk-jupyter-agent-dev**
4. Start server

### Clone Examples Repository

In JupyterHub terminal:
```bash
git clone https://github.com/{org}/thinkube-ai-examples.git
cd thinkube-ai-examples
```

### Run Setup Notebooks

Run these notebooks **in order**:

#### 00-platform-validation.ipynb

Validates all platform services are accessible:
- LiteLLM gateway
- Qdrant vector database
- Langfuse observability
- MLflow experiment tracking
- PostgreSQL database
- Valkey cache
- NATS messaging

**Expected result**: All services show green checkmarks.

#### 01-register-litellm.ipynb

Registers your deployed models in LiteLLM:
- Discovers your running LLM and embedding services
- Registers them via LiteLLM API
- Tests the unified API

**After this notebook**, you can use LiteLLM as your single gateway:

```python
from openai import OpenAI

client = OpenAI(
    base_url=os.environ['LITELLM_ENDPOINT'],
    api_key=os.environ['LITELLM_MASTER_KEY']
)

# Chat completion
response = client.chat.completions.create(
    model="gpt-oss",  # Your registered model name
    messages=[{"role": "user", "content": "Hello!"}]
)

# Embeddings
embeddings = client.embeddings.create(
    model="nomic-embed",  # Your registered model name
    input="Text to embed"
)
```

## Step 4: Build the Research Assistant

Continue with the application notebooks in `research-assistant/`:

| Notebook | What You'll Build |
|----------|-------------------|
| `02-langchain-rag.ipynb` | RAG pipeline for ArXiv papers |
| `03-multi-agent.ipynb` | Multi-agent system with CrewAI |
| `04-fine-tuning.ipynb` | Fine-tune GPT-OSS with Unsloth |

### What You'll Learn

- **RAG Pipeline**: Ingest papers, chunk, embed, store in Qdrant, query with context
- **Multi-Agent**: Paper Summarizer, Experiment Tracker, Insight Finder agents coordinating via NATS
- **Fine-Tuning**: QLoRA with Unsloth, track experiments in MLflow

## Architecture Summary

After completing setup, your environment looks like:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Your Application                             │
├─────────────────────────────────────────────────────────────────┤
│                           │                                      │
│                      LiteLLM Gateway                             │
│                     (unified API)                                │
│                      /          \                                │
│                     ▼            ▼                               │
│           ┌─────────────┐  ┌─────────────┐                      │
│           │ gpt-oss-20b │  │ nomic-embed │                      │
│           │ (TensorRT)  │  │ (embeddings)│                      │
│           └─────────────┘  └─────────────┘                      │
│                                                                  │
│  Platform Services:                                              │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐        │
│  │ Qdrant │ │Langfuse│ │ MLflow │ │Postgres│ │ Valkey │        │
│  └────────┘ └────────┘ └────────┘ └────────┘ └────────┘        │
│                                                                  │
│  Multi-Agent: NATS messaging                                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**100% self-contained** - no external API calls required.

## Troubleshooting

### Model download stuck

Check MLflow UI for download status. Large models may take time depending on network.

### Service not healthy

```bash
kubectl get pods -n {namespace}
kubectl logs -n {namespace} {pod-name}
```

### LiteLLM registration failed

Verify the service endpoints are accessible from JupyterHub:
```python
import requests
requests.get("http://{service}.{namespace}.svc:8355/health")
```

## Next Steps

After completing the Research Assistant notebooks:

1. **Create your own template** based on what you've built
2. **Deploy via Thinkube Control** for production use
3. **Fine-tune models** for your specific domain
