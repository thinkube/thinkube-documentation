# Jupyter Flavor Validation Usage

## Overview

Thinkube provides three Jupyter environment flavors, each with specialized packages:

- **ml-gpu**: Base ML/GPU environment (PyTorch, transformers, all service clients)
- **agent-dev**: Agent Development (LangChain, CrewAI, FAISS + ml-gpu)
- **fine-tuning**: Fine-Tuning Lab (Unsloth, QLoRA, PEFT, TRL + ml-gpu)

Each notebook should validate it's running in the correct environment to prevent import errors and confusion.

## Usage in Notebooks

### Basic Validation (Strict Mode)

Add this cell at the beginning of your notebook:

```python
from check_jupyter_flavor import check_flavor

# This will raise an error if running in wrong environment
check_flavor('agent-dev')
```

**Output when correct:**
```
✓ Running in correct environment: agent-dev
  Agent Development (LangChain, CrewAI, FAISS + ml-gpu)
```

**Output when incorrect:**
```
======================================================================
❌ Environment Mismatch!
======================================================================
This notebook requires: agent-dev
Currently running in:   ml-gpu

Required: Agent Development (LangChain, CrewAI, FAISS + ml-gpu)
Current:  Base ML/GPU environment (PyTorch, transformers, all service clients)

Please switch to the correct JupyterHub image:
  1. Stop this server (File → Hub Control Panel → Stop My Server)
  2. Select 'agent-dev' image from the dropdown
  3. Start the server and reopen this notebook
======================================================================
EnvironmentError: [error message]
```

### Warning Only (Non-Strict Mode)

If you want to allow execution but warn the user:

```python
from check_jupyter_flavor import check_flavor

# This will print a warning but continue execution
if not check_flavor('fine-tuning', strict=False):
    print("⚠️  Continuing anyway, but some imports may fail...")
```

### Get Current Flavor

To check the current flavor programmatically:

```python
from check_jupyter_flavor import get_current_flavor

current = get_current_flavor()
print(f"Running in {current} environment")

# Conditional logic based on flavor
if current == 'agent-dev':
    import langchain
elif current == 'fine-tuning':
    import unsloth
```

### Display Environment Information

To display detailed information about available flavors:

```python
from check_jupyter_flavor import get_flavor_info

info = get_flavor_info()
print(f"Current: {info['current']}")
print(f"Description: {info['current_description']}")
print("\nAvailable flavors:")
for flavor, desc in info['available_flavors'].items():
    marker = " ← (current)" if flavor == info['current'] else ""
    print(f"  • {flavor}: {desc}{marker}")
```

## Notebook Examples by Flavor

### For Agent Development Notebooks

```python
# Cell 1: Environment validation
from check_jupyter_flavor import check_flavor
check_flavor('agent-dev')

# Cell 2: Now safe to import agent-dev packages
from langchain import LLMChain
from langchain.prompts import PromptTemplate
import faiss
```

### For Fine-Tuning Notebooks

```python
# Cell 1: Environment validation
from check_jupyter_flavor import check_flavor
check_flavor('fine-tuning')

# Cell 2: Now safe to import fine-tuning packages
from unsloth import FastLanguageModel
from peft import LoraConfig
import bitsandbytes as bnb
```

### For Base ML-GPU Notebooks

```python
# Cell 1: Environment validation
from check_jupyter_flavor import check_flavor
check_flavor('ml-gpu')

# Cell 2: Use base ML packages (available in all flavors)
import torch
import transformers
import pandas as pd
```

## Implementing in Template Notebooks

### Phase 0: Platform Services Validation
**Notebook:** `00-platform-services-test.ipynb`
**Required Flavor:** `ml-gpu` (base environment, tests core services)

```python
from check_jupyter_flavor import check_flavor
check_flavor('ml-gpu')
```

### Phase 1: Agent Development Notebooks

**Notebook:** `01-langchain-basics.ipynb`
**Required Flavor:** `agent-dev`

```python
from check_jupyter_flavor import check_flavor
check_flavor('agent-dev')
```

**Notebook:** `04-rag-pipeline.ipynb`
**Required Flavor:** `agent-dev`

```python
from check_jupyter_flavor import check_flavor
check_flavor('agent-dev')
```

**Notebook:** `05-crewai-agents.ipynb`
**Required Flavor:** `agent-dev`

```python
from check_jupyter_flavor import check_flavor
check_flavor('agent-dev')
```

### Phase 3: Fine-Tuning Notebooks

**Notebook:** `02-qlora-tuning.ipynb`
**Required Flavor:** `fine-tuning`

```python
from check_jupyter_flavor import check_flavor
check_flavor('fine-tuning')
```

**Notebook:** `04-evaluation-deployment.ipynb`
**Required Flavor:** `fine-tuning`

```python
from check_jupyter_flavor import check_flavor
check_flavor('fine-tuning')
```

## Implementation Details

### Flavor Token File

Each Jupyter image contains a flavor identifier at `/home/jovyan/.jupyter_flavor`:

- `ml-gpu`: Contains `"ml-gpu"`
- `agent-dev`: Contains `"agent-dev"`
- `fine-tuning`: Contains `"fine-tuning"`

### Module Location

The validation module is installed in the Python path:
- Source: `/opt/thinkube/check_jupyter_flavor.py`
- Symlinked to: `/usr/local/lib/python3.12/site-packages/check_jupyter_flavor.py`

This makes it importable from any notebook without additional setup.

### Inheritance

The specialized flavors (agent-dev, fine-tuning) inherit from ml-gpu:
- All base packages from ml-gpu are available in specialized flavors
- Notebooks requiring only base packages can run in any flavor
- Notebooks requiring specialized packages must validate the correct flavor

## Best Practices

1. **Always validate at the start** - Add flavor check in the first cell
2. **Use strict mode by default** - Better to fail early than get confusing import errors
3. **Document required packages** - Add a markdown cell explaining why this flavor is needed
4. **Test in correct environment** - Don't develop notebooks in the wrong flavor
5. **Clear error messages** - The validation provides clear instructions for switching environments

## Example Complete Notebook Structure

```python
# Cell 1: Markdown
"""
# RAG Pipeline with LangChain

**Required Environment:** agent-dev

This notebook requires LangChain, FAISS, and other agent development packages.
Make sure you're running in the **agent-dev** Jupyter flavor.
"""

# Cell 2: Validation
from check_jupyter_flavor import check_flavor
check_flavor('agent-dev')

# Cell 3: Imports
from langchain import LLMChain
from langchain.prompts import PromptTemplate
import faiss
import qdrant_client

# Cell 4+: Your notebook code...
```

## Troubleshooting

### `ModuleNotFoundError: No module named 'check_jupyter_flavor'`

This means you're using an older Jupyter image that doesn't include the validation helper.

**Solution:** Rebuild the Jupyter images:
```bash
cd ~/thinkube
./scripts/run_ansible.sh ansible/40_thinkube/core/harbor-images/15_build_jupyter_images.yaml
```

### `FileNotFoundError: Jupyter flavor file not found`

This means you're not running in a Thinkube JupyterHub environment.

**Solution:** Use the validation helper only in Thinkube-managed Jupyter environments.

### Wrong Flavor but Imports Work

Some packages (like PyTorch, pandas) are available in all flavors. The validation is more about ensuring specialized packages are available.

**Solution:** Still use the validation for documentation purposes, even if imports would work.
