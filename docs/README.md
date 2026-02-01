# Documentation

## Contents

- [AWS Setup](aws-setup.md) - One-time AWS infrastructure setup using CLI
- [Techniques](techniques.md) - Deep dive on each optimization technique
- [Benchmarking](benchmarking.md) - How to run and interpret benchmarks

## Architecture

```
┌─────────────────┐
│  HTTP API       │
│  POST /instance │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Launcher       │
│  (technique)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐      ┌─────────────────┐
│  EC2 API        │ ──── │  Metrics        │
│  RunInstances   │      │  Collector      │
└────────┬────────┘      └─────────────────┘
         │
         ▼
┌─────────────────┐
│  SSH Probe      │
│  (auth check)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Response       │
│  {ip, timings}  │
└─────────────────┘
```

## Timing Phases

```
Request ──┬── t0 (request received)
          │
          ├── EC2 API call
          │
          ├── t1 (instance ID returned)
          │
          ├── Wait for "running" state
          │
          ├── t2 (state = running)
          │
          ├── TCP probe port 22
          │
          ├── t3 (TCP accepts)
          │
          ├── SSH auth handshake
          │
          └── t4 (auth success)

Total time = t4 - t0
```
