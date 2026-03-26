# CPU to GPU: Republic AI Compute Setup

## Problem
Default inference runs on CPU (~77 seconds per job).

## Solution
Change Docker base image to CUDA-enabled version.

## Step 1: Install nvidia-container-toolkit
```bash
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

## Step 2: Change Dockerfile Base Image

**Before (CPU only):**
```dockerfile
FROM python:3.10-slim
RUN pip install torch>=2.0.0
```

**After (GPU enabled):**
```dockerfile
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04
RUN pip3 install torch --index-url https://download.pytorch.org/whl/cu118
```

## Step 3: Run with GPU
```bash
docker run --rm --gpus all \
  -v /var/lib/republic/jobs:/output \
  republic-llm-inference:latest
```

## Results
| Device | Time | 
|--------|------|
| CPU | ~77 seconds |
| RTX 3090 (CUDA) | ~8 seconds |
| Speedup | **10x faster** |

## How it works
inference.py automatically detects GPU:
```python
device = "cuda" if torch.cuda.is_available() else "cpu"
```
With CUDA base image, `torch.cuda.is_available()` returns `True` → GPU used automatically!
