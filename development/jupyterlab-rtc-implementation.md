# JupyterLab RTC Implementation Guide

This guide provides practical examples and patterns for developers working with JupyterLab's Real-Time Collaboration system in Thinkube.

For architectural overview, see [jupyterlab-rtc-architecture.md](./jupyterlab-rtc-architecture.md).

---

## Table of Contents

1. [Adding New MCP Tools](#adding-new-mcp-tools)
2. [Working with YDoc](#working-with-ydoc)
3. [Cell Manipulation Patterns](#cell-manipulation-patterns)
4. [Metadata Management](#metadata-management)
5. [Testing RTC Features](#testing-rtc-features)
6. [Error Handling](#error-handling)
7. [Common Patterns](#common-patterns)

---

## Adding New MCP Tools

### Tool Template

```python
# tk_ai_extension/mcp/tools/manipulation/my_tool.py

from typing import Any, Optional, Dict
from ..base import BaseTool
from ..utils import get_jupyter_ydoc, get_notebook_path

class MyTool(BaseTool):
    """Description of what this tool does."""

    @property
    def name(self) -> str:
        return "my_tool"

    @property
    def description(self) -> str:
        return "Detailed description for Claude to understand when to use this"

    @property
    def input_schema(self) -> dict:
        return {
            "type": "object",
            "properties": {
                "notebook_path": {
                    "type": "string",
                    "description": "Path to the notebook"
                },
                "param1": {
                    "type": "string",
                    "description": "Description of parameter"
                }
            },
            "required": ["notebook_path", "param1"]
        }

    async def execute(
        self,
        contents_manager: Any,
        kernel_manager: Any,
        kernel_spec_manager: Optional[Any] = None,
        **kwargs
    ) -> Dict[str, Any]:
        """Execute the tool.

        Args:
            contents_manager: Jupyter contents manager
            kernel_manager: Jupyter kernel manager
            kernel_spec_manager: Kernel spec manager
            **kwargs: Tool arguments from Claude

        Returns:
            Dict with success status and result
        """
        # 1. Extract parameters
        notebook_path = kwargs.get("notebook_path")
        param1 = kwargs.get("param1")

        if not notebook_path or not param1:
            return {
                "error": "notebook_path and param1 are required",
                "success": False
            }

        try:
            # 2. Get serverapp
            serverapp = kwargs.get('serverapp')
            if not serverapp:
                serverapp = getattr(contents_manager, 'parent', None)

            if not serverapp:
                return {
                    "error": "ServerApp not available - cannot access YDoc",
                    "success": False
                }

            # 3. Get absolute path
            abs_path = get_notebook_path(serverapp, notebook_path)

            # 4. Get file_id
            file_id_manager = serverapp.web_app.settings.get("file_id_manager")
            if not file_id_manager:
                return {
                    "error": "file_id_manager not available",
                    "success": False
                }

            file_id = file_id_manager.get_id(abs_path)

            # 5. Get YDoc
            ydoc = await get_jupyter_ydoc(serverapp, file_id)
            if not ydoc:
                return {
                    "error": f"YDoc not available for {notebook_path}. Notebook must be open.",
                    "success": False
                }

            # 6. Perform operation on YDoc
            # Example: Count cells
            cell_count = len(ydoc.ycells)

            # 7. Return success
            return {
                "success": True,
                "cell_count": cell_count,
                "message": f"Found {cell_count} cells"
            }

        except Exception as e:
            return {
                "success": False,
                "error": str(e)
            }
```

### Registering the Tool

Add to `tk_ai_extension/mcp/tools/manipulation/__init__.py`:

```python
from .my_tool import MyTool

__all__ = ["MyTool"]
```

Add to `tk_ai_extension/mcp/tools/__init__.py`:

```python
from .manipulation import MyTool

MANIPULATION_TOOLS = [
    # ... existing tools
    MyTool,
]
```

The tool is now available to Claude automatically.

---

## Working with YDoc

### Getting YDoc from Notebook Path

```python
async def get_ydoc_for_notebook(serverapp, notebook_path: str):
    """Get YDoc for a notebook given its path."""
    from pathlib import Path

    # Convert to absolute path
    if not Path(notebook_path).is_absolute():
        root_dir = serverapp.root_dir
        abs_path = str(Path(root_dir) / notebook_path)
    else:
        abs_path = notebook_path

    # Get file_id
    file_id_manager = serverapp.web_app.settings.get("file_id_manager")
    file_id = file_id_manager.get_id(abs_path)

    # Get YDoc
    ydoc_extensions = serverapp.extension_manager.extension_apps.get("jupyter_server_ydoc", set())
    if not ydoc_extensions:
        return None

    ydoc_ext = next(iter(ydoc_extensions))
    ywebsocket_server = ydoc_ext.ywebsocket_server

    room_id = f"json:notebook:{file_id}"
    if ywebsocket_server.room_exists(room_id):
        yroom = await ywebsocket_server.get_room(room_id)
        return yroom._document

    return None
```

### Checking if Notebook is Open

```python
def is_notebook_open(serverapp, notebook_path: str) -> bool:
    """Check if notebook has an active YDoc room."""
    # ... get file_id ...

    ydoc_extensions = serverapp.extension_manager.extension_apps.get("jupyter_server_ydoc", set())
    if not ydoc_extensions:
        return False

    ydoc_ext = next(iter(ydoc_extensions))
    ywebsocket_server = ydoc_ext.ywebsocket_server

    room_id = f"json:notebook:{file_id}"
    return ywebsocket_server.room_exists(room_id)
```

### Accessing Notebook Properties

```python
ydoc = await get_jupyter_ydoc(serverapp, file_id)

# Cell count
num_cells = len(ydoc.ycells)

# Notebook format
nbformat = ydoc._ymeta.get("nbformat")
nbformat_minor = ydoc._ymeta.get("nbformat_minor")

# Metadata
metadata = ydoc._ymeta.get("metadata", {})
if hasattr(metadata, 'to_py'):
    metadata = metadata.to_py()

# Kernel info
kernelspec = metadata.get("kernelspec", {})
print(f"Kernel: {kernelspec.get('display_name')}")
```

---

## Cell Manipulation Patterns

### Insert Cell at Specific Position

```python
def insert_code_cell(ydoc, index: int, source: str):
    """Insert a code cell at the specified index."""
    # Create cell dict
    cell_dict = {
        "cell_type": "code",
        "source": source,
        "execution_count": None,
        "metadata": {"trusted": False}
    }

    # Convert to CRDT cell (this creates Text object for source)
    ycell = ydoc.create_ycell(cell_dict)

    # Validate index
    if index < 0 or index > len(ydoc.ycells):
        raise ValueError(f"Index {index} out of range (0-{len(ydoc.ycells)})")

    # Insert
    ydoc.ycells.insert(index, ycell)

    return ycell
```

### Append Cell to End

```python
def append_markdown_cell(ydoc, source: str):
    """Append markdown cell to end of notebook."""
    cell_dict = {
        "cell_type": "markdown",
        "source": source,
        "metadata": {}
    }

    ycell = ydoc.create_ycell(cell_dict)
    ydoc.ycells.append(ycell)

    return ycell
```

### Update Cell Source

```python
def update_cell_source(ydoc, cell_index: int, new_source: str):
    """Update the source of an existing cell."""
    if cell_index < 0 or cell_index >= len(ydoc.ycells):
        raise ValueError(f"Cell index {cell_index} out of range")

    cell = ydoc.ycells[cell_index]

    # Get cell as dict
    cell_dict = cell.to_py()

    # Update source
    cell_dict["source"] = new_source

    # Create new cell with updated source
    updated_cell = ydoc.create_ycell(cell_dict)

    # Replace in array
    ydoc.ycells[cell_index] = updated_cell
```

### Delete Cell

```python
def delete_cell(ydoc, cell_index: int):
    """Delete cell at the specified index."""
    if cell_index < 0 or cell_index >= len(ydoc.ycells):
        raise ValueError(f"Cell index {cell_index} out of range")

    del ydoc.ycells[cell_index]
```

### Move Cell

```python
def move_cell(ydoc, from_index: int, to_index: int):
    """Move cell from one position to another."""
    if from_index < 0 or from_index >= len(ydoc.ycells):
        raise ValueError(f"Source index {from_index} out of range")

    if to_index < 0 or to_index > len(ydoc.ycells):
        raise ValueError(f"Target index {to_index} out of range")

    # Get cell
    cell = ydoc.ycells[from_index]

    # Remove from old position
    del ydoc.ycells[from_index]

    # Adjust target index if needed
    if to_index > from_index:
        to_index -= 1

    # Insert at new position
    ydoc.ycells.insert(to_index, cell)
```

### Read Cell Content

```python
def get_cell_source(ydoc, cell_index: int) -> str:
    """Get source code from a cell."""
    if cell_index < 0 or cell_index >= len(ydoc.ycells):
        raise ValueError(f"Cell index {cell_index} out of range")

    cell = ydoc.ycells[cell_index]

    # Get source (it's a Text object)
    source = cell["source"]

    # Convert to Python string
    if hasattr(source, 'to_py'):
        return source.to_py()

    return str(source)
```

### Get All Cells as List

```python
def get_all_cells(ydoc) -> list:
    """Get all cells as Python dicts."""
    cells = []

    for i in range(len(ydoc.ycells)):
        cell = ydoc.get_cell(i)  # This method handles conversion
        cells.append(cell)

    return cells
```

---

## Metadata Management

### Read Notebook Metadata

```python
def get_notebook_metadata(ydoc) -> dict:
    """Get notebook metadata as Python dict."""
    metadata = ydoc._ymeta.get("metadata", {})

    # Convert pycrdt Map to Python dict
    if hasattr(metadata, 'to_py'):
        metadata = metadata.to_py()
    else:
        metadata = dict(metadata)

    return metadata
```

### Update Notebook Metadata

```python
from pycrdt import Map

def set_notebook_metadata(ydoc, new_metadata: dict):
    """Update notebook metadata."""
    # Read existing
    existing = get_notebook_metadata(ydoc)

    # Merge
    existing.update(new_metadata)

    # Write back as Map
    ydoc._ymeta["metadata"] = Map(existing)
```

### Update Specific Metadata Field

```python
from pycrdt import Map

def update_metadata_field(ydoc, key: str, value: Any):
    """Update a specific field in notebook metadata."""
    metadata = get_notebook_metadata(ydoc)
    metadata[key] = value
    ydoc._ymeta["metadata"] = Map(metadata)
```

### Read Cell Metadata

```python
def get_cell_metadata(ydoc, cell_index: int) -> dict:
    """Get metadata for a specific cell."""
    cell = ydoc.ycells[cell_index]
    cell_meta = cell.get("metadata", {})

    if hasattr(cell_meta, 'to_py'):
        return cell_meta.to_py()

    return dict(cell_meta)
```

### Custom Metadata Structure

```python
from pycrdt import Map

def save_custom_data(ydoc, data: dict):
    """Save custom data to notebook metadata."""
    metadata = get_notebook_metadata(ydoc)

    # Ensure custom namespace exists
    if 'thinkube' not in metadata:
        metadata['thinkube'] = {}

    # Update custom data
    metadata['thinkube'].update(data)

    # Write back
    ydoc._ymeta["metadata"] = Map(metadata)
```

### Example: Save Conversation History

```python
from pycrdt import Map

async def save_conversation(serverapp, notebook_path: str, messages: list):
    """Save conversation history to notebook metadata."""
    # Get YDoc
    abs_path = get_notebook_path(serverapp, notebook_path)
    file_id_manager = serverapp.web_app.settings.get("file_id_manager")
    file_id = file_id_manager.get_id(abs_path)
    ydoc = await get_jupyter_ydoc(serverapp, file_id)

    if not ydoc:
        return False

    # Get metadata
    metadata = get_notebook_metadata(ydoc)

    # Ensure structure
    if 'tk_ai' not in metadata:
        metadata['tk_ai'] = {}

    # Save conversation (limit to last 100 messages)
    metadata['tk_ai']['conversation_history'] = messages[-100:]

    # Write back
    ydoc._ymeta["metadata"] = Map(metadata)

    return True
```

---

## Testing RTC Features

### Test Setup

1. **Start JupyterLab**
2. **Open a test notebook**
3. **Open browser console** (F12)
4. **Call tool from backend or use Thinky**
5. **Verify changes appear without refresh**

### Manual Test

```python
# In a Jupyter terminal or Python console on the server

import asyncio
from jupyter_server.serverapp import ServerApp

async def test_insert_cell():
    """Test cell insertion via YDoc."""
    # Get serverapp instance
    serverapp = ServerApp.instance()

    # Import tool
    from tk_ai_extension.mcp.tools.manipulation.insert_cell import InsertCellTool

    tool = InsertCellTool()

    # Execute
    result = await tool.execute(
        contents_manager=serverapp.contents_manager,
        kernel_manager=None,
        serverapp=serverapp,
        notebook_path="thinkube/notebooks/test.ipynb",
        cell_index=1,
        cell_type="code",
        source="# Test cell from backend\nprint('Hello from RTC!')"
    )

    print(result)

# Run test
asyncio.run(test_insert_cell())
```

### Verify YDoc State

```python
async def debug_ydoc_state(serverapp, notebook_path: str):
    """Print current YDoc state for debugging."""
    from pathlib import Path

    # Get YDoc
    abs_path = str(Path(serverapp.root_dir) / notebook_path)
    file_id_manager = serverapp.web_app.settings.get("file_id_manager")
    file_id = file_id_manager.get_id(abs_path)

    ydoc_extensions = serverapp.extension_manager.extension_apps.get("jupyter_server_ydoc", set())
    ydoc_ext = next(iter(ydoc_extensions))
    ywebsocket_server = ydoc_ext.ywebsocket_server

    room_id = f"json:notebook:{file_id}"

    print(f"File ID: {file_id}")
    print(f"Room ID: {room_id}")
    print(f"Room exists: {ywebsocket_server.room_exists(room_id)}")

    if ywebsocket_server.room_exists(room_id):
        yroom = await ywebsocket_server.get_room(room_id)
        ydoc = yroom._document

        print(f"Cell count: {len(ydoc.ycells)}")
        print(f"Notebook format: {ydoc._ymeta.get('nbformat')}.{ydoc._ymeta.get('nbformat_minor')}")

        # Print cells
        for i in range(len(ydoc.ycells)):
            cell = ydoc.ycells[i]
            cell_type = cell["cell_type"]
            source = cell["source"]
            if hasattr(source, 'to_py'):
                source = source.to_py()
            print(f"  Cell {i} ({cell_type}): {source[:50]}...")
```

### Check Browser State

Open browser console while notebook is open:

```javascript
// Get current notebook panel
const panel = window.jupyterapp.shell.currentWidget;

// Get document_id
const docId = panel.content.model.sharedModel.getState('document_id');
console.log('document_id:', docId);

// Get cell count
const cellCount = panel.content.model.sharedModel.cells.length;
console.log('Cell count:', cellCount);

// Get first cell source
const firstCell = panel.content.model.sharedModel.cells.get(0);
console.log('First cell source:', firstCell.getSource());
```

---

## Error Handling

### Common Error Patterns

```python
async def safe_ydoc_operation(serverapp, notebook_path: str):
    """Example of comprehensive error handling."""
    try:
        # 1. Validate serverapp
        if not serverapp:
            return {
                "error": "ServerApp not available",
                "success": False,
                "code": "NO_SERVERAPP"
            }

        # 2. Get absolute path
        try:
            abs_path = get_notebook_path(serverapp, notebook_path)
        except Exception as e:
            return {
                "error": f"Invalid path: {e}",
                "success": False,
                "code": "INVALID_PATH"
            }

        # 3. Get file_id_manager
        file_id_manager = serverapp.web_app.settings.get("file_id_manager")
        if not file_id_manager:
            return {
                "error": "file_id_manager not available - collaboration not enabled",
                "success": False,
                "code": "NO_FILE_ID_MANAGER"
            }

        # 4. Get file_id
        try:
            file_id = file_id_manager.get_id(abs_path)
        except Exception as e:
            return {
                "error": f"File not found: {abs_path}",
                "success": False,
                "code": "FILE_NOT_FOUND"
            }

        # 5. Get YDoc
        ydoc = await get_jupyter_ydoc(serverapp, file_id)
        if not ydoc:
            return {
                "error": f"Notebook not open in JupyterLab: {notebook_path}",
                "success": False,
                "code": "NOTEBOOK_NOT_OPEN",
                "hint": "Open the notebook in JupyterLab first"
            }

        # 6. Perform operation
        # ... your code here ...

        return {"success": True}

    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        return {
            "error": f"Internal error: {str(e)}",
            "success": False,
            "code": "INTERNAL_ERROR"
        }
```

### Graceful Degradation

```python
async def get_cell_count_with_fallback(serverapp, notebook_path: str) -> int:
    """Get cell count, falling back to file read if YDoc unavailable."""
    import json
    from pathlib import Path

    # Try YDoc first (fast, real-time)
    try:
        ydoc = await get_ydoc_for_notebook(serverapp, notebook_path)
        if ydoc:
            return len(ydoc.ycells)
    except Exception:
        pass  # Fall through to file read

    # Fallback to file read (slower, not real-time)
    try:
        abs_path = get_notebook_path(serverapp, notebook_path)
        with open(abs_path, 'r') as f:
            nb = json.load(f)
            return len(nb.get('cells', []))
    except Exception:
        return 0
```

---

## Common Patterns

### Pattern: Safe Cell Access

```python
def safe_get_cell(ydoc, index: int, default=None):
    """Get cell safely, returning default if out of range."""
    try:
        if 0 <= index < len(ydoc.ycells):
            return ydoc.get_cell(index)
    except Exception:
        pass
    return default
```

### Pattern: Find Cell by ID

```python
def find_cell_by_id(ydoc, cell_id: str) -> tuple[int, dict]:
    """Find cell by ID, returns (index, cell_dict) or (None, None)."""
    for i in range(len(ydoc.ycells)):
        cell = ydoc.ycells[i]
        if cell.get("id") == cell_id:
            return (i, ydoc.get_cell(i))
    return (None, None)
```

### Pattern: Find Cell by Content

```python
def find_cell_by_content(ydoc, search_text: str) -> list[int]:
    """Find all cells containing search_text, returns list of indices."""
    matches = []

    for i in range(len(ydoc.ycells)):
        cell = ydoc.ycells[i]
        source = cell["source"]

        if hasattr(source, 'to_py'):
            source = source.to_py()

        if search_text in source:
            matches.append(i)

    return matches
```

### Pattern: Batch Cell Operations

```python
def insert_multiple_cells(ydoc, start_index: int, cells: list[dict]):
    """Insert multiple cells starting at index."""
    # Create all cells first
    ycells = [ydoc.create_ycell(cell_dict) for cell_dict in cells]

    # Insert in order
    for i, ycell in enumerate(ycells):
        ydoc.ycells.insert(start_index + i, ycell)
```

### Pattern: Transaction Safety

YDoc auto-manages transactions, but for complex operations:

```python
from pycrdt import Transaction

def complex_operation(ydoc):
    """Perform multiple changes atomically."""
    # Note: pycrdt transactions are handled automatically
    # This is just for documentation

    # All changes to ydoc are automatically transactional
    ydoc.ycells.insert(0, new_cell_1)
    ydoc.ycells.insert(1, new_cell_2)
    metadata = get_notebook_metadata(ydoc)
    metadata['modified'] = True
    ydoc._ymeta["metadata"] = Map(metadata)

    # These all happen in one sync to clients
```

### Pattern: Logging for Debugging

```python
import logging

logger = logging.getLogger(__name__)

async def logged_ydoc_operation(serverapp, notebook_path: str, operation: str):
    """Template for logged operations."""
    logger.info(f"Starting {operation} on {notebook_path}")

    try:
        # Get YDoc
        abs_path = get_notebook_path(serverapp, notebook_path)
        logger.debug(f"Absolute path: {abs_path}")

        file_id_manager = serverapp.web_app.settings.get("file_id_manager")
        file_id = file_id_manager.get_id(abs_path)
        logger.debug(f"File ID: {file_id}")

        ydoc = await get_jupyter_ydoc(serverapp, file_id)
        if not ydoc:
            logger.error(f"YDoc not found for {notebook_path}")
            return {"success": False, "error": "Notebook not open"}

        logger.debug(f"YDoc retrieved, {len(ydoc.ycells)} cells")

        # Perform operation
        # ...

        logger.info(f"Completed {operation} successfully")
        return {"success": True}

    except Exception as e:
        logger.error(f"Failed {operation}: {e}", exc_info=True)
        return {"success": False, "error": str(e)}
```

---

## Best Practices

1. **Always check if notebook is open** before attempting YDoc operations
2. **Use create_ycell()** for all cell creation to ensure proper CRDT types
3. **Never modify files directly** - use YDoc API exclusively
4. **Return descriptive errors** with error codes for better debugging
5. **Log important operations** to help trace issues
6. **Validate indices** before accessing cells to prevent crashes
7. **Use type hints** to make code more maintainable
8. **Test with notebook open** in JupyterLab UI to verify sync
9. **Handle async properly** - always await YDoc operations
10. **Document your tools** with clear descriptions for Claude

---

## Resources

- Main Architecture Doc: [jupyterlab-rtc-architecture.md](./jupyterlab-rtc-architecture.md)
- jupyter-server-ydoc API: https://github.com/jupyter-server/jupyter-server-ydoc
- pycrdt Documentation: https://github.com/jupyter-server/pycrdt
- JupyterLab RTC: https://jupyterlab.readthedocs.io/en/latest/user/rtc.html

---

*Guide Version: 1.0*
*Last Updated: 2025-10-12*
*Thinkube Project*
