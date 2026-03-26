#!/usr/bin/env python3
"""
LLM Inference Container for Republic Protocol Compute Jobs
Executes language model inference using Hugging Face transformers.
Configured via environment variables.
"""

import os
import sys
import json
import time
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, pipeline


def main():
    """Main entry point for LLM inference execution"""
    
    # Configuration from environment variables
    model_id = os.getenv("MODEL_ID", "gpt2")
    prompt = os.getenv("PROMPT", "What is the future of decentralized AI?")
    max_new_tokens = int(os.getenv("MAX_NEW_TOKENS", "256"))
    temperature = float(os.getenv("TEMPERATURE", "0.7"))
    top_p = float(os.getenv("TOP_P", "0.9"))
    use_4bit = os.getenv("USE_4BIT", "false").lower() == "true"
    
    print("=" * 60)
    print("Republic Protocol - LLM Inference Job")
    print("=" * 60)
    print(f"Model ID: {model_id}")
    print(f"Prompt: {prompt}")
    print(f"Max new tokens: {max_new_tokens}")
    print(f"Temperature: {temperature}")
    print(f"Top-p: {top_p}")
    print(f"Using 4-bit quantization: {use_4bit}")
    print("=" * 60)
    
    result = {}
    start_time = time.time()
    
    try:
        # Device configuration
        device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"\n[1/4] Device: {device}")
        
        if device == "cuda":
            print(f"       GPU: {torch.cuda.get_device_name(0)}")
            print(f"       Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")
        
        # Load tokenizer
        print(f"\n[2/4] Loading tokenizer...")
        tokenizer = AutoTokenizer.from_pretrained(
            model_id,
            trust_remote_code=True,
            padding_side="left"
        )
        
        # Set pad token if not set
        if tokenizer.pad_token is None:
            tokenizer.pad_token = tokenizer.eos_token
        
        # Load model
        print(f"\n[3/4] Loading model...")
        
        # Model loading configuration
        model_kwargs = {
            "trust_remote_code": True,
        }
        
        if device == "cuda":
            if use_4bit:
                # Use 4-bit quantization for memory efficiency
                from transformers import BitsAndBytesConfig
                
                quantization_config = BitsAndBytesConfig(
                    load_in_4bit=True,
                    bnb_4bit_compute_dtype=torch.float16,
                    bnb_4bit_use_double_quant=True,
                    bnb_4bit_quant_type="nf4"
                )
                model_kwargs["quantization_config"] = quantization_config
                model_kwargs["device_map"] = "auto"
            else:
                model_kwargs["torch_dtype"] = torch.float16
                model_kwargs["device_map"] = "auto"
        else:
            model_kwargs["torch_dtype"] = torch.float32
        
        model = AutoModelForCausalLM.from_pretrained(model_id, **model_kwargs)
        
        print(f"       Model loaded successfully!")
        
        # Format prompt for chat models
        print(f"\n[4/4] Running inference...")
        
        # Check if this is a chat model
        if "chat" in model_id.lower() or "instruct" in model_id.lower():
            # Use chat template if available
            if hasattr(tokenizer, "apply_chat_template"):
                messages = [
                    {"role": "system", "content": "You are a helpful AI assistant."},
                    {"role": "user", "content": prompt},
                ]
                formatted_prompt = tokenizer.apply_chat_template(
                    messages, 
                    tokenize=False, 
                    add_generation_prompt=True
                )
            else:
                # Fallback for Llama-2 chat format
                formatted_prompt = f"<s>[INST] {prompt} [/INST]"
        else:
            formatted_prompt = prompt
        
        # Create pipeline
        pipe = pipeline(
            "text-generation",
            model=model,
            tokenizer=tokenizer,
            max_new_tokens=max_new_tokens,
            do_sample=True,
            temperature=temperature,
            top_p=top_p,
            repetition_penalty=1.1,
        )
        
        # Generate
        outputs = pipe(formatted_prompt)
        generated_text = outputs[0]["generated_text"]
        
        # Extract only the response (remove the prompt)
        if formatted_prompt in generated_text:
            response = generated_text[len(formatted_prompt):].strip()
        else:
            response = generated_text.strip()
        
        inference_time = time.time() - start_time
        
        # Build result
        result = {
            "status": "success",
            "model_id": model_id,
            "prompt": prompt,
            "response": response,
            "device": device,
            "inference_time_seconds": round(inference_time, 2),
            "max_new_tokens": max_new_tokens,
            "temperature": temperature,
            "top_p": top_p,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        }
        
        print(f"\n✓ Inference completed in {inference_time:.2f}s")
        print(f"\n{'─' * 60}")
        print("RESPONSE:")
        print(f"{'─' * 60}")
        print(response)
        print(f"{'─' * 60}")
        
    except Exception as e:
        inference_time = time.time() - start_time
        error_msg = str(e)
        
        result = {
            "status": "error",
            "model_id": model_id,
            "prompt": prompt,
            "error": error_msg,
            "error_type": type(e).__name__,
            "inference_time_seconds": round(inference_time, 2),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        }
        
        print(f"\n✗ Error during inference: {error_msg}", file=sys.stderr)
        import traceback
        traceback.print_exc()
    
    # Output final result as JSON for the protocol
    result_json = json.dumps(result, indent=2)
    
    print(f"\n{'=' * 60}")
    print("FINAL RESULT (JSON):")
    print(f"{'=' * 60}")
    print(result_json)
    
    # Write to /output/result.bin (for sidecar compatibility)
    output_path = os.getenv("OUTPUT_PATH", "/output/result.bin")
    try:
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "w") as f:
            f.write(result_json)
        print(f"\n✓ Result written to {output_path}")
    except Exception as e:
        print(f"\n⚠ Could not write to {output_path}: {e}", file=sys.stderr)
    
    # Return appropriate exit code
    sys.exit(0 if result["status"] == "success" else 1)


if __name__ == "__main__":
    main()
