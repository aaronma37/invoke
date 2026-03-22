import subprocess
import argparse
import os
import sys

def run_command(cmd, env=None):
    print(f"Executing: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=False, text=True, env=env)
    if result.returncode != 0:
        print(f"Error executing command: {' '.join(cmd)}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Moontide UV Distillation Orchestrator")
    parser.add_argument("--target", required=True, help="Path to high-poly target .obj")
    parser.add_argument("--base", help="Path to base .obj (if not provided, will be generated/unwrapped)")
    parser.add_argument("--name", default="unnamed", help="Project name for artifacts")
    parser.add_argument("--epochs", default="1000", help="Number of training epochs")
    parser.add_argument("--gpu", action="store_true", help="Use GPU-accelerated UV sampler")
    
    args = parser.parse_args()
    
    # Define paths
    raw_dir = "artifacts/raw"
    dataset_dir = "artifacts/datasets"
    model_dir = "artifacts/models"
    eval_dir = "artifacts/eval"
    
    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(dataset_dir, exist_ok=True)
    os.makedirs(model_dir, exist_ok=True)
    os.makedirs(eval_dir, exist_ok=True)
    
    unwrapped_base = os.path.join(raw_dir, f"{args.name}_base_unwrapped.obj")
    pcb_path = os.path.join(dataset_dir, f"{args.name}.pcb")
    model_path = os.path.join(model_dir, f"{args.name}.kan")
    output_obj = os.path.join(eval_dir, f"{args.name}_displaced.obj")
    
    # 1. Unwrap (if needed)
    if not args.base:
        print("--- Phase 1: Unwrapping ---")
        run_command([sys.executable, "pipelines/uv_distillation/unwrap.py", args.target, unwrapped_base])
        base_obj = unwrapped_base
    else:
        base_obj = args.base

    # 2. Sample
    print("--- Phase 2: Sampling ---")
    if args.gpu:
        env = os.environ.copy()
        env["SDL_VIDEODRIVER"] = "offscreen"
        run_command(["./extensions/mooncrust/build/mooncrust", "projects/uv_sampler_gpu", args.target, pcb_path, base_obj], env=env)
    else:
        run_command(["./zig-out/bin/uv-sampler", args.target, pcb_path, base_obj])
    
    # 3. Train
    print("--- Phase 3: Training ---")
    run_command(["./zig-out/bin/kan-train", pcb_path, args.epochs, "10000", "0.001", "displacement", "--output", model_path])
    
    # 4. Reconstruct
    print("--- Phase 4: Reconstruction ---")
    run_command(["./zig-out/bin/reconstruct-displaced", base_obj, model_path, output_obj])
    
    print(f"\nPipeline Complete!")
    print(f"Final displaced mesh: {output_obj}")

if __name__ == "__main__":
    main()
