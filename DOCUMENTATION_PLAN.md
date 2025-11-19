# Documentation Plan: Complete AI Agent Development Lifecycle

## Strategic Understanding

The AI Agent Development Lifecycle on Thinkube includes:
1. **Prototype** - Build agent in JupyterHub (LangChain/CrewAI)
2. **Fine-tune** - Custom models for specific tasks/domains/cost-reduction
3. **Deploy** - Production deployment via CI/CD
4. **Observe** - Monitor with Langfuse
5. **Optimize** - Iterate based on metrics

**What EXISTS** ✅:
- tk-jupyter-agent-dev image (LangChain, CrewAI, FAISS)
- tk-jupyter-fine-tuning image (Unsloth, QLoRA, PEFT, TRL)
- All platform services (LiteLLM, Qdrant, Langfuse, MLflow, NATS)
- CI/CD pipeline (Gitea → ArgoCD)
- Educational notebooks (agent-dev + fine-tuning, ~30-60 TODOs each)

**What's MISSING** ❌:
- Agent templates (tkt-rag-agent, etc.)
- LLM router library
- Agent testing framework
- Complete notebook implementations

---

## NEW DOCUMENTS TO CREATE

### 1. **Complete AI Agent Development Lifecycle** (NEW - CRITICAL)
**File**: `guides/ai-agent-development-lifecycle.md`

**Content**:

**The Five Phases**:

**Phase 1: Prototype**
- Build agent in tk-jupyter-agent-dev (LangChain/CrewAI)
- Use agent-dev notebooks as learning guides
- Integrate platform services (LiteLLM, Qdrant, Langfuse)
- Test and iterate quickly

**Phase 2: Fine-Tune (Optional but Powerful)**
- Why fine-tune:
  - Domain-specific knowledge (legal, medical, technical)
  - Cost reduction (smaller custom model vs large generic)
  - Privacy (local model, no API calls)
  - Latency (faster inference)
  - Task-specific optimization
- Use tk-jupyter-fine-tuning image (Unsloth, QLoRA)
- Fine-tuning workflows:
  - QLoRA for efficient fine-tuning on consumer GPUs
  - Unsloth for 2x faster training
  - PEFT for parameter-efficient techniques
- Track experiments with MLflow
- Deploy fine-tuned model via vLLM/TensorRT-LLM
- Use fine-tuned model in agent via LiteLLM

**Phase 3: Deploy**
- Convert prototype to application (FastAPI + Gradio)
- Use tkt-webapp-vue-fastapi template as starting point
- Deploy via thinkube-control
- Automatic Gitea → ArgoCD pipeline

**Phase 4: Observe**
- Langfuse for agent tracing
- MLflow for model metrics
- LiteLLM dashboard for costs
- Performance monitoring

**Phase 5: Optimize**
- Analyze Langfuse traces
- Improve prompts
- Fine-tune further if needed
- Route between local/cloud LLMs
- A/B testing

### 2. **Fine-Tuning Guide for Agent Development** (NEW - CRITICAL)
**File**: `guides/fine-tuning-for-agents.md`

**Content**:

**Why Fine-Tune for Agents**:
- **Domain Expertise**: Train on legal documents for legal agent
- **Tool Usage**: Fine-tune on examples of tool calling patterns
- **Cost Reduction**: 7B fine-tuned model vs GPT-4 ($0 vs $0.03/1K tokens)
- **Privacy**: Local fine-tuned model, no data to cloud
- **Latency**: Faster inference, better user experience
- **Agent-Specific Behaviors**: Train on conversation patterns, safety constraints

**Available Tools** ✅:
- **tk-jupyter-fine-tuning image** with:
  - Unsloth 2025.9.9 (2x faster training)
  - QLoRA / bitsandbytes 0.47.0 (4-bit quantization)
  - PEFT 0.17.1 (LoRA adapters)
  - TRL 0.23.0 (reinforcement learning)
- **MLflow** - Track experiments, compare models
- **GPU Support** - Fine-tune on platform GPUs

**Fine-Tuning Workflows**:

**Workflow 1: QLoRA Fine-Tuning**
```
1. Select base model (Llama 3, Mistral, Qwen)
2. Prepare dataset (agent conversations, tool usage examples)
3. Configure QLoRA (4-bit quantization, LoRA adapters)
4. Train with Unsloth (2x faster)
5. Log to MLflow (metrics, checkpoints)
6. Evaluate on validation set
7. Deploy via vLLM/TensorRT-LLM
8. Use in agent via LiteLLM
```

**Workflow 2: Full Fine-Tuning** (for larger GPUs)
**Workflow 3: DPO/RLHF** (for alignment)

**Fine-Tuning Notebooks** ⚠️:
- Located in `/home/jovyan/thinkube/examples-repo/fine-tuning/`
- 4 notebooks: unsloth-basics, qlora-tuning, dataset-preparation, evaluation-deployment
- Educational templates (~30-60 TODOs each)
- Provide structure and patterns but require implementation

**Integration with Agent Deployment**:
```
Fine-tuned Model → vLLM/TensorRT-LLM → LiteLLM → Agent
```

**Example Use Cases**:
- Customer support agent trained on company's support tickets
- Code review agent trained on codebase patterns
- Legal document agent trained on case law
- Medical diagnosis agent trained on clinical notes

### 3. **Platform Services Integration** (NEW - CRITICAL)
**File**: `guides/platform-services-integration.md`

**Content**:

**LiteLLM - Unified LLM Gateway** ✅
- Why: Access 100+ LLM providers with OpenAI-compatible API
- URL: `https://litellm.{domain}/v1/`
- Code example:
```python
from openai import OpenAI
import os

client = OpenAI(
    base_url=os.getenv('LITELLM_ENDPOINT'),
    api_key=os.getenv('LITELLM_MASTER_KEY')
)

response = client.chat.completions.create(
    model="gpt-4",
    messages=[{"role": "user", "content": "Hello!"}]
)
```
- Integration with LangChain
- Cost tracking

**Qdrant - Vector Database** ✅
- Why: Semantic search for RAG
- Code example:
```python
from qdrant_client import QdrantClient
import os

client = QdrantClient(
    host=os.getenv('QDRANT_GRPC_HOST'),
    grpc_port=int(os.getenv('QDRANT_GRPC_PORT')),
    prefer_grpc=True
)
```
- RAG pipeline integration

**Langfuse - Agent Observability** ✅
- Why: Trace execution, track costs
- Code example:
```python
from langfuse import Langfuse
import os

langfuse = Langfuse(
    public_key=os.getenv('LANGFUSE_PUBLIC_KEY'),
    secret_key=os.getenv('LANGFUSE_SECRET_KEY'),
    host=os.getenv('LANGFUSE_HOST')
)
```
- LangChain integration

**MLflow - Experiment Tracking** ✅
- Why: Track fine-tuning experiments
- URL: `https://mlflow.{domain}/`
- Code example:
```python
import mlflow
import os

mlflow.set_tracking_uri(os.getenv('MLFLOW_TRACKING_URI'))

with mlflow.start_run():
    mlflow.log_param("model", "llama-3-8b")
    mlflow.log_param("lora_rank", 16)
    mlflow.log_metric("loss", loss)
```

**NATS - Messaging** ✅
- Why: Multi-agent communication

**PostgreSQL, Valkey, SeaweedFS** ✅
- State, caching, storage

### 4. **JupyterHub Images for AI Agent Development** (NEW - CRITICAL)
**File**: `guides/jupyterhub-images-agent-development.md`

**Content**:

**Three Specialized Images** ✅:

**1. tk-jupyter-ml-gpu** - Base ML Development
- PyTorch CUDA 12.6, transformers, datasets
- Use for: General ML, data preparation, model evaluation
- Pre-integrated services: All platform services

**2. tk-jupyter-agent-dev** - Agent Development
- Inherits from tk-jupyter-ml-gpu
- **Additional**: LangChain 0.3.27, CrewAI 0.203.1, FAISS 1.12.0
- Use for: Building RAG agents, multi-agent systems, tool-calling agents
- Example notebooks: agent-dev/ directory (6 notebooks)

**3. tk-jupyter-fine-tuning** - LLM Fine-Tuning
- Inherits from tk-jupyter-ml-gpu
- **Additional**: Unsloth 2025.9.9, QLoRA, PEFT 0.17.1, TRL 0.23.0
- Use for: Fine-tuning base models for agent-specific tasks
- Example notebooks: fine-tuning/ directory (4 notebooks)

**Image Selection Workflow**:
- Start: tk-jupyter-agent-dev (prototype agent)
- Fine-tune: tk-jupyter-fine-tuning (if custom model needed)
- Deploy: Convert to application, deploy via CI/CD

**All Images Include** ✅:
- Service discovery (automatic environment variables)
- Integration with: PostgreSQL, Valkey, Qdrant, Weaviate, OpenSearch, MLflow, SeaweedFS, LiteLLM, NATS, ClickHouse

### 5. **Example: RAG Agent with Custom Fine-Tuned Model** (NEW - CRITICAL)
**File**: `examples/rag-agent-with-fine-tuning.md`

**Content** - Complete end-to-end workflow:

**Scenario**: Legal document Q&A agent with domain expertise

**Phase 1: Build RAG Agent Prototype**
- Use tk-jupyter-agent-dev
- LangChain + Qdrant for RAG
- Test with GPT-4 via LiteLLM
- Cost: $0.03/1K tokens

**Phase 2: Fine-Tune for Legal Domain**
- Switch to tk-jupyter-fine-tuning image
- Prepare dataset: legal Q&A pairs
- Fine-tune Llama 3 8B with QLoRA
- Log experiments to MLflow
- Evaluate: domain accuracy improves, cost drops

**Phase 3: Deploy Fine-Tuned Model**
- Deploy via tkt-vllm-gradio or tkt-tensorrt-llm
- Register in LiteLLM as local model
- Cost: $0/query (local inference)

**Phase 4: Update Agent to Use Fine-Tuned Model**
- Modify agent to use local fine-tuned model
- LiteLLM routing: local model → cloud fallback
- Monitor with Langfuse

**Results**:
- Domain accuracy: +25% (legal terminology understanding)
- Cost: $0.03/1K → $0/1K (100% cost reduction)
- Latency: Improved (local inference)
- Privacy: Data never leaves platform

**Complete working code for all phases**

### 6. **Template System Guide** (NEW - HIGH)
**File**: `guides/template-system.md`

**Content**:

**What Templates Are**:
- Pre-configured application scaffolds
- Copier-based with `manifest.yaml` + `thinkube.yaml`
- Automatic deployment via thinkube-control

**Available Templates** (✅ VERIFIED):
1. **tkt-webapp-vue-fastapi** - Full-stack web app (Vue + FastAPI + PostgreSQL)
   - Best starting point for building custom agents
   - Replace Vue with Gradio or remove frontend entirely
2. **tkt-vllm-gradio** - Local LLM inference (vLLM + Gradio)
   - For running local LLMs
3. **tkt-tensorrt-llm** - TensorRT-LLM for Blackwell GPUs
   - DGX Spark optimized
4. **tkt-stable-diffusion** - Image generation

**Planned Agent Templates** (❌ NOT IMPLEMENTED):
- tkt-rag-agent, tkt-tool-agent, tkt-multi-agent, tkt-agentic-workflow
- See roadmap in keys_to_success/MISSING_PIECES.md

**Using Templates**:
- Deploy from thinkube-control UI: `https://control.{domain}/`
- Template parameters and customization
- How GitOps processes templates

**Creating Custom Templates**:
- manifest.yaml format (apiVersion: thinkube.io/v1)
- thinkube.yaml deployment spec
- Copier templating with Jinja2
- Publishing to thinkube-metadata repository

### 7. **CI/CD Workflow Documentation** (NEW - CRITICAL)
**File**: `guides/cicd-deployment-workflow.md`

**Content** - Based on VERIFIED deploy-application.yaml:

**Complete Workflow** (✅ WORKING):
```
User → thinkube-control UI
  ↓
Template Deployment API
  ↓
Gitea Repository Creation (thinkube-deployments org)
  ↓
Code Push to Gitea
  ↓
Webhook Trigger
  ↓
ArgoCD Sync
  ↓
Kubernetes Deployment
  ↓
Service Discovery Registration
```

**Step-by-Step**:
1. **Select Template** - From thinkube-control UI
2. **Configure Parameters** - Template-specific variables
3. **Deploy** - API creates Gitea repo, pushes code, configures webhook
4. **Automatic Build** - ArgoCD syncs manifests
5. **Deployment** - Application deployed to Kubernetes
6. **Registration** - Service auto-registered in thinkube-control

**Monitoring**:
- CI/CD monitoring via thinkube-control
- ArgoCD dashboard for deployment status
- Pod logs for runtime debugging

**Manual Override**:
- How to push updates to Gitea repo
- Trigger manual ArgoCD sync
- Rollback procedures

### 8. **Using Thinkube AI Lab** (NEW - CRITICAL)
**File**: `guides/thinkube-ai-lab-quickstart.md`

**Content**:

**Three Workflow Paths**:

**Path 1: Agent Development**
- Image: tk-jupyter-agent-dev
- Notebooks: agent-dev/ (6 notebooks)
- Build: RAG agents, tool-calling agents, multi-agent systems
- Tools: LangChain, CrewAI, FAISS

**Path 2: Model Fine-Tuning**
- Image: tk-jupyter-fine-tuning
- Notebooks: fine-tuning/ (4 notebooks)
- Build: Custom fine-tuned models for agent tasks
- Tools: Unsloth, QLoRA, PEFT, TRL

**Path 3: General ML**
- Image: tk-jupyter-ml-gpu
- Notebooks: ml-gpu/ common/
- Build: Data preparation, model evaluation, ML workflows
- Tools: PyTorch, transformers, pandas, scikit-learn

**Complete Lifecycle Example**:
```
Day 1-2: Prototype agent (tk-jupyter-agent-dev)
Day 3-4: Fine-tune model (tk-jupyter-fine-tuning)
Day 5: Deploy fine-tuned model (tkt-vllm-gradio)
Day 6: Update agent with fine-tuned model
Day 7: Deploy to production (CI/CD)
```

---

## UPDATES TO EXISTING DOCUMENTS

### 9. **Platform Overview** (UPDATE)
**File**: `architecture/platform-overview.md`

**ADD Section**: "AI Agent Development Lifecycle Support"

**Components by Lifecycle Phase**:

**Prototyping**:
- Thinkube AI Lab (JupyterHub) with tk-jupyter-agent-dev
- LangChain, CrewAI frameworks
- Platform services (LiteLLM, Qdrant, Langfuse, NATS)

**Fine-Tuning**:
- Thinkube AI Lab with tk-jupyter-fine-tuning
- Unsloth, QLoRA, PEFT, TRL
- MLflow for experiment tracking
- GPU support for training

**Deployment**:
- Template system (4 templates available)
- CI/CD pipeline (Gitea → ArgoCD)
- tkt-vllm-gradio / tkt-tensorrt-llm for model serving

**Observability**:
- Langfuse for agent tracing
- MLflow for model metrics
- LiteLLM for cost tracking

**Optimization**:
- LiteLLM routing (local → cloud fallback)
- Performance monitoring
- A/B testing capabilities

### 10. **README.md** (UPDATE)
**File**: `README.md`

**Headline**: "AI Agent Development Platform with Integrated Fine-Tuning"

**Quick Start**:
```
1. Prototype agent in JupyterHub (tk-jupyter-agent-dev)
2. Fine-tune custom model (tk-jupyter-fine-tuning) [optional]
3. Deploy via CI/CD (Gitea → ArgoCD)
4. Monitor with Langfuse
5. Optimize with metrics
```

**Key Features**:
- ✅ Complete infrastructure (29 components)
- ✅ Agent development (LangChain, CrewAI)
- ✅ Model fine-tuning (Unsloth, QLoRA)
- ✅ Local LLM serving (vLLM, TensorRT-LLM)
- ✅ Observability (Langfuse, MLflow)
- ✅ CI/CD automation

---

## CRITICAL ACKNOWLEDGMENTS IN DOCUMENTATION

**What Works** ✅:
- tk-jupyter-agent-dev image (LangChain, CrewAI)
- tk-jupyter-fine-tuning image (Unsloth, QLoRA, PEFT, TRL)
- All platform services deployed and integrated
- MLflow experiment tracking
- CI/CD pipeline
- Template system (4 templates)

**What's Educational** ⚠️:
- Agent-dev notebooks (30% complete, learning guides with TODOs)
- Fine-tuning notebooks (30% complete, learning guides with TODOs)
- Users must implement the TODO sections

**What's Missing** ❌:
- Agent-specific templates (tkt-rag-agent, etc.)
- LLM router library
- Agent testing framework
- Production-ready notebook implementations

---

## DOCUMENTATION STRUCTURE

```
guides/
├── ai-agent-development-lifecycle.md      ⭐⭐⭐ (NEW)
├── fine-tuning-for-agents.md              ⭐⭐⭐ (NEW)
├── platform-services-integration.md       ⭐⭐⭐ (NEW)
├── jupyterhub-images-agent-development.md ⭐⭐⭐ (NEW)
├── thinkube-ai-lab-quickstart.md          ⭐⭐⭐ (NEW)
├── template-system.md                     ⭐⭐  (NEW)
└── cicd-deployment-workflow.md            ⭐⭐  (NEW)

examples/
├── rag-agent-with-fine-tuning.md          ⭐⭐⭐ (NEW - complete workflow)
└── building-rag-agent.md                  ⭐⭐  (NEW - simpler, no fine-tuning)

architecture/
└── platform-overview.md                   ⭐⭐  (UPDATE)

README.md                                   ⭐⭐  (UPDATE)
```

---

## IMPLEMENTATION PRIORITY

**Week 1: Complete Lifecycle Documentation** (CRITICAL)
1. AI Agent Development Lifecycle ⭐⭐⭐
2. Fine-Tuning for Agents ⭐⭐⭐
3. JupyterHub Images Guide ⭐⭐⭐
4. RAG Agent with Fine-Tuning Example ⭐⭐⭐

**Week 2: Integration & Infrastructure** (HIGH)
5. Platform Services Integration ⭐⭐
6. Thinkube AI Lab Quickstart ⭐⭐
7. Template System ⭐⭐
8. CI/CD Workflow ⭐⭐

**Week 3: Polish** (MEDIUM)
9. Platform Overview Update ⭐
10. README Update ⭐

---

## SUCCESS CRITERIA

**Documentation reflects complete agent lifecycle**:
✅ Shows Prototype → Fine-tune → Deploy → Observe → Optimize
✅ Explains fine-tuning as part of agent development
✅ Integrates MLflow for experiment tracking
✅ Shows tk-jupyter-fine-tuning image and capabilities
✅ Provides end-to-end examples with fine-tuning

**Developer can**:
✅ Build agent prototype (tk-jupyter-agent-dev)
✅ Fine-tune custom model (tk-jupyter-fine-tuning)
✅ Deploy fine-tuned model (vLLM/TensorRT-LLM)
✅ Use fine-tuned model in agent (via LiteLLM)
✅ Track experiments (MLflow)
✅ Monitor in production (Langfuse)
✅ Understand cost benefits ($0.03/1K → $0/1K)

**Strategic alignment**:
✅ Positions fine-tuning as competitive advantage
✅ Shows cost reduction through custom models
✅ Emphasizes privacy (local fine-tuned models)
✅ Demonstrates complete agent development platform
