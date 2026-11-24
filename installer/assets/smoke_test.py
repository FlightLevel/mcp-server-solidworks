"""Build-time check, run by build.ps1 with the BUNDLED Python from the staged adapters/claude folder.

Imports the whole adapter (which eagerly imports cad-planner/drawing and its deps) exactly as
Claude Desktop will launch it, and checks the adapter resolves the bundled execution server.
"""
import os

import dotenv  # noqa: F401
import ezdxf  # noqa: F401
import httpx  # noqa: F401
import mcp  # noqa: F401

import config
import execution_client  # noqa: F401
import response_mapper  # noqa: F401
import server  # noqa: F401
from ir_execution_port import run_feature_graph  # noqa: F401  (pulls in compiler/solidworks)

assert os.path.isfile(config.EXECUTION_EXE_PATH), config.EXECUTION_EXE_PATH
assert os.path.basename(os.path.dirname(config.EXECUTION_EXE_PATH)) == "server", config.EXECUTION_EXE_PATH
print("adapter imports OK; execution server:", config.EXECUTION_EXE_PATH)
