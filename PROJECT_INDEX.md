# Project Index: Terrarium

Generated: 2026-02-16

## Project Structure

```
terrarium/
├── src/
│   ├── index.ts                              # Express app entry point (72 LOC)
│   ├── services/
│   │   └── python-interpreter/
│   │       ├── service.ts                    # PyodidePythonEnvironment class (293 LOC)
│   │       └── types.ts                      # Interfaces & types (24 LOC)
│   └── utils/
│       └── async-utils.ts                    # waitFor(), doWithLock() (76 LOC)
├── tests/
│   ├── functionality/                        # 5 Python test scripts
│   ├── security/                             # 3 Python test scripts
│   └── file_io/                              # 3 Python test scripts + fixtures
├── example-clients/python/
│   ├── terrarium_client.py                   # Python client with GCP auth
│   └── requirements.txt                      # requests, google-auth
├── default_python_home/
│   ├── matplotlibrc                          # Cohere-branded matplotlib style
│   └── README.md                             # Easter egg
├── .github/workflows/dockerize.yml           # CI: Docker build → GHCR
├── Dockerfile                                # node:21-alpine3.18, ts-node entrypoint
├── package.json                              # Dependencies & scripts
├── tsconfig.json                             # ES2018, CommonJS, strict
└── nodemon.json                              # Dev watcher config
```

**Stats**: 4 TypeScript source files, 465 LOC total, 11 Python test scripts

## Entry Points

- **Server**: `src/index.ts` — Express app on port 8080
- **Docker**: `Dockerfile` — `ENTRYPOINT ["ts-node", "src/index.ts"]`
- **Tests**: `example-clients/python/terrarium_client.py` — Runs all test/*.py against server
- **CI**: `.github/workflows/dockerize.yml` — Build & push Docker image on main

## Core Modules

### Module: index (`src/index.ts`)
- **Exports**: None (entry point)
- **Purpose**: Express HTTP server with 3 routes, request locking, Pyodide lifecycle management
- **Key symbols**: `pythonEnvironment`, `terrariumApp`, `runRequest()`, `server`

### Module: python-interpreter/service (`src/services/python-interpreter/service.ts`)
- **Exports**: `PyodidePythonEnvironment`
- **Purpose**: Core sandbox — manages Pyodide WASM lifecycle, code execution, file I/O, environment recycling
- **Key methods**: `init()`, `loadEnvironment()`, `runCode()`, `terminate()`, `cleanup()`, `listFilesRecursive()`, `readFileAsBase64()`

### Module: python-interpreter/types (`src/services/python-interpreter/types.ts`)
- **Exports**: `CodeExecutionResponse`, `FileData`, `PythonEnvironment`
- **Purpose**: TypeScript interfaces for the sandbox API contract

### Module: async-utils (`src/utils/async-utils.ts`)
- **Exports**: `waitFor()`, `doWithLock()`
- **Purpose**: Promise-based timer and named async mutex for request serialization

## API Surface

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/` | POST | Execute Python code. Body: `{code, files?:[{filename, b64_data}]}` → `{success, final_expression, output_files, error, std_out, std_err, code_runtime}` |
| `/health` | GET | Health check → `"hi!"` |
| `/stop` | GET | Graceful shutdown → `process.exit(1)` |

## Configuration

| File | Purpose |
|------|---------|
| `package.json` | npm deps & scripts (build/start/dev/ci) |
| `tsconfig.json` | TypeScript: ES2018, CommonJS, strict mode |
| `nodemon.json` | Dev: watch `src/`, `.ts` extension |
| `Dockerfile` | Docker: alpine, healthcheck (curl /health or kill PID 1) |
| `default_python_home/matplotlibrc` | Matplotlib defaults: Cohere colors, 128 DPI, constrained layout, transparent bg |

## Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `pyodide` | ^0.29.3 | CPython compiled to WASM — the core sandbox engine |
| `express` | ^4.19.2 | HTTP server framework |
| `typescript` | ^5.9.3 | TypeScript compiler |
| `ts-node` | ^10.9.2 | TypeScript runtime (dev/prod) |
| `pm2` | ^5.4.3 | Process manager for clustered CI mode |
| `nodemon` | ^3.1.11 | Dev auto-reload |

## Test Coverage

- **Functionality tests**: 5 files (numpy, sympy, error handling)
- **Security tests**: 3 files (subprocess blocked, dir listing sandboxed)
- **File I/O tests**: 3 files (matplotlib PNG/PDF/SVG, file round-trip)
- **Runner**: `terrarium_client.py` against live server (no unit test framework)

## Architecture Decisions

1. **Single-request concurrency** — `doWithLock` serializes requests per process; PM2 `-i max` for parallelism
2. **Full recycle** — Pyodide completely reloaded after every execution (no state leakage)
3. **Streaming response** — `res.write()` before recycle, `res.end()` after (keeps GCP CPU alive)
4. **Pre-loaded packages** — numpy, matplotlib, pandas loaded at startup to reduce per-request latency
5. **Fake DOM stubs** — Minimal `document`/`ImageData` shims for matplotlib-pyodide (`savefig` only)
6. **SharedArrayBuffer interrupt** — Enables terminating runaway Python execution

## Quick Start

1. `npm install && mkdir -p pyodide_cache`
2. `npm run dev` (starts on http://localhost:8080)
3. `curl -X POST -H "Content-Type: application/json" --url http://localhost:8080 --data-raw '{"code": "1 + 1"}'`
