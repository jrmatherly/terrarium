# Terrarium - Project Overview

## What It Is
A low-latency Python sandbox service (by Cohere) that executes untrusted user/LLM-generated Python code safely. Runs CPython compiled to WebAssembly via [Pyodide](https://pyodide.org/) inside a Node.js/Express server, deployed as a Docker container (typically on GCP Cloud Run).

## Tech Stack
- **Runtime:** Node.js + TypeScript (ts-node)
- **Python Execution:** Pyodide (CPython→WASM)
- **Server:** Express.js
- **Build:** TypeScript (`tsc`), nodemon for dev, pm2 for CI
- **Deployment:** Docker (node:21-alpine3.18), GCP Cloud Run

## Project Structure
```
src/
  index.ts                              # Express app, routes (/health, POST /)
  services/python-interpreter/
    service.ts                          # PyodidePythonEnvironment class (core sandbox)
    types.ts                            # Type definitions
  utils/
    async-utils.ts                      # Lock/async utilities
tests/
  functionality/                        # Python test scripts (numpy, sympy, errors)
  security/                             # Security tests (subprocess, dir access)
  file_io/                              # File I/O tests (matplotlib, file input/output)
example-clients/python/
  terrarium_client.py                   # Python client with file I/O support
.github/workflows/dockerize.yml         # CI: Docker image build
```

## Key Architecture
- **Sandbox layers:** Pyodide WASM (no FS/network/threading) + Docker container isolation
- **No state between calls:** Full Pyodide environment recycled after every invocation
- **File I/O:** Base64-encoded files in request/response
- **Health check:** `/health` endpoint, Docker HEALTHCHECK kills PID 1 on failure

## API
- `POST /` — Execute Python code. Body: `{"code": "...", "files": [...]}`. Returns: `{"output_files":[], "final_expression":..., "success":true, "std_out":"", "std_err":"", "code_runtime":...}`
- `GET /health` — Health check

## Commands
- `npm run dev` — Development server with nodemon
- `npm run build` — TypeScript build
- `npm run start` — Production start
- `npm run ci` — PM2 clustered start with auto-restart

## Key Symbols
- `PyodidePythonEnvironment` (service.ts) — Core class managing Pyodide lifecycle and code execution
- `terrariumApp` (index.ts) — Express application with route handlers
