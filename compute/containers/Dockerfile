# GPU-enabled Dockerfile for Republic AI compute jobs
# Changed from python:3.10-slim (CPU only) to nvidia/cuda (GPU enabled)

FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

WORKDIR /app

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install PyTorch with CUDA 11.8 support (KEY CHANGE: added --index-url)
RUN pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cu118

RUN pip3 install --no-cache-dir \
    transformers>=4.30.0 \
    accelerate>=0.20.0

COPY inference.py .

ENV MODEL_ID="gpt2"
ENV PROMPT="What is the future of decentralized AI?"
ENV MAX_NEW_TOKENS=256
ENV TEMPERATURE=0.7
ENV TOP_P=0.9

CMD ["python3", "inference.py"]
