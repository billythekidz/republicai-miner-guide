# Republic AI Testnet Node Setup

## Node Info
- Chain ID: raitestnet_77701-1
- Binary: v0.3.0
- Cosmovisor: v1.7.1

## Network Endpoints
- RPC: https://rpc.republicai.io
- Explorer: https://explorer.republicai.io

## Setup
- Ubuntu 22.04
- Go 1.22.3
- patchelf (GLIBC 2.39 compatibility)

## Compute Setup
- GPU: NVIDIA RTX 3090 (24GB VRAM)
- Docker with CUDA 11.8
- First compute job on testnet (Job ID: 10)

## GPU vs CPU Performance
- CPU inference: ~77 seconds
- GPU inference: ~8 seconds (10x faster)
