# CPU to GPU: Docker Setup for Republic AI Compute

## Why GPU?
| Device | Inference Time | 
|--------|---------------|
| CPU | ~77 seconds |
| RTX 3090 (CUDA) | ~8 seconds |
| Speedup | **10x faster** |

## Step 1: Verify GPU & Docker
```bash
# Check GPU
nvidia-smi

# Check Docker GPU support
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

## Step 2: Change Dockerfile

**Before (CPU only):**
```dockerfile
FROM python:3.10-slim
RUN pip install torch>=2.0.0
```

**After (GPU enabled):**
```dockerfile
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

RUN apt-get update && apt-get install -y \
    python3 python3-pip gcc \
    && rm -rf /var/lib/apt/lists/*

# KEY CHANGE: Install PyTorch with CUDA 11.8 support
RUN pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cu118

RUN pip3 install --no-cache-dir \
    transformers>=4.30.0 \
    accelerate>=0.20.0
```

## Step 3: Build GPU Image
```bash
docker build -t republic-llm-inference:latest .
```

## Step 4: Run with GPU
```bash
docker run --rm --gpus all \
  -v /var/lib/republic/jobs/JOB_ID:/output \
  republic-llm-inference:latest
```

## How it Works
inference.py automatically detects GPU:
```python
device = "cuda" if torch.cuda.is_available() else "cpu"
```
With CUDA base image → `torch.cuda.is_available()` returns `True` → GPU used automatically!

## Result
```json
{
  "device": "cuda",
  "inference_time_seconds": 8.15
}
```
