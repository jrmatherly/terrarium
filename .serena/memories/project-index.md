# Terrarium — Complete Project Index

## 1. Project Identity

| Field | Value |
|-------|-------|
| **Name** | Terrarium |
| **Origin** | Cohere |
| **Purpose** | Low-latency Python sandbox for executing untrusted user/LLM-generated code |
| **Core Tech** | Pyodide (CPython→WASM) inside Node.js/Express |
| **License** | MIT |
| **Language** | TypeScript (server), Python (tests/client) |
| **Node target** | ES2018, CommonJS |
| **Docker base** | node:21-alpine3.18 |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Container                      │
│  ┌───────────────────────────────────────────────────┐  │
│  │              Express.js (port 8080)                │  │
│  │  POST /  ─→  doWithLock('python-request') ─→      │  │
│  │              runRequest()                          │  │
│  │  GET /health ─→ "hi!"                             │  │
│  │  GET /stop   ─→ process.exit(1)                   │  │
│  │                                                   │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │    PyodidePythonEnvironment                 │  │  │
│  │  │                                             │  │  │
│  │  │  init() → prepareEnvironment()              │  │  │
│  │  │         → loadEnvironment()                 │  │  │
│  │  │                                             │  │  │
│  │  │  runCode(code, files) →                     │  │  │
│  │  │    loadPackagesFromImports(code)             │  │  │
│  │  │    write input files to WASM FS              │  │  │
│  │  │    runPythonAsync(code)                      │  │  │
│  │  │    collect output files from WASM FS         │  │  │
│  │  │    return CodeExecutionResponse              │  │  │
│  │  │                                             │  │  │
│  │  │  terminate() → set interrupt flag            │  │  │
│  │  │  cleanup()   → loadEnvironment() [recycle]   │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Request Lifecycle
1. `POST /` → `doWithLock` ensures single-request concurrency
2. `waitForReady()` → polls until Pyodide is initialized
3. Parse `code` and optional `files` (base64-encoded) from request body
4. `runCode()` → load packages → write files → execute Python → collect output files
5. `res.write(result)` — response sent but connection kept open
6. `terminate()` → sets interrupt buffer flag
7. `cleanup()` → calls `loadEnvironment()` to fully recycle Pyodide
8. `res.end()` — connection closed (allows GCP to keep CPU alive during recycle)

### Security Model
- **Layer 1 (Pyodide WASM):** No real filesystem, no threading, no subprocess, no network, no host memory access. Environment fully recycled after each call.
- **Layer 2 (Docker/Cloud Run):** Runtime limits, network isolation from internal infrastructure.
- **jsglobals sanitization:** Only timer functions + fake `ImageData`/`document` stubs (for matplotlib-pyodide) are exposed.

---

## 3. File-by-File Reference

### `src/index.ts` — Application Entry Point
- **`pythonEnvironment`** — Singleton `PyodidePythonEnvironment` instance, pre-initialized at startup
- **`terrariumApp`** — Express app with 100MB JSON body limit
- **`runRequest(req, res)`** — Main handler: validates code, runs Python, streams result, recycles env
- **Routes:**
  - `POST ''` — Execute Python code (locked to 1 concurrent request)
  - `GET /health` — Returns `"hi!"`
  - `GET /stop` — `process.exit(1)` for graceful shutdown via API
- **Server** — Listens on port 8080

### `src/services/python-interpreter/service.ts` — Core Sandbox
- **`PyodidePythonEnvironment`** implements `PythonEnvironment`
- **State:** `out_string`, `err_string`, `default_files`, `default_file_names`, `pyodide`, `interruptBufferPyodide`, `interrupt`
- **Methods:**
  - `prepareEnvironment()` — Reads files from `default_python_home/` on host FS into memory
  - `loadEnvironment()` — Creates fresh Pyodide instance with sanitized jsglobals, writes default files, pre-loads numpy/matplotlib/pandas, pre-imports `plt`/`pd`/`np`
  - `init()` — `prepareEnvironment()` + `loadEnvironment()`
  - `waitForReady()` — Polls up to 10s for Pyodide to load
  - `terminate()` — Sets interrupt buffer flag
  - `cleanup()` — Calls `loadEnvironment()` (full recycle)
  - `readHostFileAsync(filePath)` — Reads file from host FS
  - `listFilesRecursive(dir)` — Lists files in Pyodide WASM FS (skipping defaults)
  - `readFileAsBase64(filePath)` — Reads file from WASM FS as base64
  - `bytesToBase64(bytes)` / `base64ToBytes(base64)` — Encoding helpers
  - `runCode(code, files)` — Full execution pipeline (see Request Lifecycle above)

### `src/services/python-interpreter/types.ts` — Type Definitions
- **`CodeExecutionResponse`** — `{ success, final_expression?, output_files?, error?: {type, message}, std_out?, std_err?, code_runtime? }`
- **`FileData`** — `{ filename: string, data: Buffer }`
- **`PythonEnvironment`** — Interface: `init()`, `waitForReady()`, `runCode()`, `cleanup()`, `terminate()`

### `src/utils/async-utils.ts` — Async Utilities
- **`waitFor(ms)`** — Promise-based `setTimeout` wrapper
- **`doWithLock(lockName, task)`** — Named async mutex using promise chains. Ensures single-task execution per lock name.

### `default_python_home/` — Default Files Copied to WASM FS
- **`matplotlibrc`** — Cohere-branded matplotlib style: custom color cycle (green/orange/violet), no top/right spines, dotted grid, 128 DPI, constrained layout, transparent background
- **`README.md`** — Easter egg recruiting message

---

## 4. API Reference

### `POST /`
Execute Python code in the sandbox.

**Request:**
```json
{
  "code": "print('hello')",
  "files": [
    { "filename": "input.txt", "b64_data": "base64..." }
  ]
}
```

**Response (`CodeExecutionResponse`):**
```json
{
  "success": true,
  "final_expression": null,
  "output_files": [
    { "filename": "plot.png", "b64_data": "base64..." }
  ],
  "std_out": "hello\n",
  "std_err": "",
  "code_runtime": 42
}
```

**Error Response:**
```json
{
  "success": false,
  "error": {
    "type": "PythonError",
    "message": "NameError: name 'foo' is not defined\n\nCode context:\n1: foo"
  },
  "std_out": "",
  "std_err": "",
  "code_runtime": 5
}
```

### `GET /health`
Returns `"hi!"` (200 OK). Used by Docker HEALTHCHECK and GCP liveness probes.

### `GET /stop`
Calls `process.exit(1)`. Used by CI for graceful shutdown.

---

## 5. Configuration & Build

| File | Purpose |
|------|---------|
| `package.json` | Dependencies, scripts (build/start/dev/ci) |
| `tsconfig.json` | TS config: ES2018, CommonJS, strict, outDir=dist |
| `nodemon.json` | Dev watcher: watches `src/`, `.ts` files |
| `Dockerfile` | node:21-alpine, ts-node entrypoint, healthcheck kills PID 1 |
| `.gitignore` | `node_modules/` only |
| `CODEOWNERS` | `@jrmatherly` owns all files |

### npm Scripts
| Script | Command | Purpose |
|--------|---------|---------|
| `build` | `tsc` | Compile TypeScript |
| `start` | `ts-node ./src/index.ts` | Run directly |
| `dev` | `nodemon src/index.ts` | Dev with auto-reload |
| `ci` | `pm2 start ... -i max` | Clustered production with auto-restart |

### Dependencies
| Package | Version | Role |
|---------|---------|------|
| `pyodide` | ^0.29.3 | CPython WASM runtime |
| `express` | ^4.19.2 | HTTP server |
| `typescript` | ^5.9.3 | Compiler |
| `@types/express` | ^4.17.21 | Type defs |
| `@types/node` | ^20.11.30 | Type defs |
| `clean` | ^4.0.2 | (unused?) |
| `ts-node` | ^10.9.2 | TS runtime (dev) |
| `nodemon` | ^3.1.11 | Dev watcher |
| `pm2` | ^5.4.3 | Process manager (CI) |
| `node-fetch` | ^3.3.2 | (dev, likely unused) |

---

## 6. CI/CD

### `.github/workflows/dockerize.yml`
- **Trigger:** Push to `main` or manual dispatch (with custom tag)
- **Steps:** Checkout → Docker Buildx → Login to GHCR → Build multi-arch (amd64+arm64) → Push to `ghcr.io/<repo>:latest`
- **Auth:** Uses `secrets.PAT` for GHCR login

---

## 7. Test Suite

All tests are Python scripts run through the `terrarium_client.py` against a live server.

### Functionality Tests (`tests/functionality/`)
| File | Tests |
|------|-------|
| `numpy_simple.py` | NumPy array creation, reshape, arithmetic |
| `sympy_simple.py` | SymPy equation solving |
| `error_wrong_param.py` | Expected Python error (wrong parameter) |
| `error_syntax_error.py` | Expected Python syntax error |
| `error_missing_import.py` | Expected missing import error |
| `super_long_python_file.py` | Stress test with large code |

### Security Tests (`tests/security/`)
| File | Tests |
|------|-------|
| `subprocess.py` | Subprocess access blocked (expected fail) |
| `create_dir.py` | Directory creation in sandbox |
| `list_dirs.py` | Lists home/root dirs (should show only guest FS) |

### File I/O Tests (`tests/file_io/`)
| File | Tests |
|------|-------|
| `simple_matplotlib.py` | Sin/cos plot → PNG, PDF, SVG output |
| `simple_matplotlib_barchart.py` | Bar chart generation |
| `replay_inputs.py` | File input → output round-trip |

---

## 8. Example Client

### `example-clients/python/terrarium_client.py`
- GCP auth via `google.auth.default()` + identity token
- `run_terrarium(server_url, code, file_data)` — Posts code, streams response, parses first JSON line
- `file_to_base64(path)` — Helper for file input encoding
- CLI mode: runs all `tests/**/*.py` files against a server URL
- **Dependencies:** `requests`, `typing_extensions`, `google-auth`

---

## 9. Key Design Decisions

1. **Single-request concurrency:** `doWithLock('python-request')` ensures only one Python execution at a time per process. PM2 cluster mode (`-i max`) handles parallelism at the process level.
2. **Full recycle after each call:** Pyodide environment is completely rebuilt after every execution — no state leakage between requests.
3. **Streaming response trick:** Response is written but not closed until recycle completes, keeping GCP Cloud Run CPU active during cleanup.
4. **Pre-loaded packages:** numpy, matplotlib, pandas are loaded at startup to reduce per-request latency.
5. **Fake DOM stubs:** matplotlib-pyodide requires `document`/`ImageData` globals; stubs are provided since only `savefig` (not `show`) is used.
6. **SharedArrayBuffer interrupt:** Allows terminating runaway Python execution via interrupt buffer.
7. **Custom matplotlibrc:** Cohere-branded defaults for consistent chart styling.

---

## 10. Known Limitations
- No package installation beyond Pyodide built-ins
- No network access from sandbox
- `RangeError: Maximum call stack size exceeded` for complex operations (high DPI, complex pandas)
- Pyodide runs on main Node.js thread — blocks event loop during execution
- No Worker support (would lose matplotlib compatibility)
