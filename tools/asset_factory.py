#!/usr/bin/env python3
import os
import sys
import subprocess
import argparse

# Default high-quality models
MODELS = {
    "bunny": "https://raw.githubusercontent.com/alecjacobson/common-3d-test-models/master/data/stanford-bunny.obj",
    "armadillo": "https://raw.githubusercontent.com/alecjacobson/common-3d-test-models/master/data/armadillo.obj",
    "dragon": "https://raw.githubusercontent.com/alecjacobson/common-3d-test-models/master/data/dragon.obj",
}

def run_cmd(cmd, description, env=None):
    print(f"\n>>> {description}...")
    print(f"Command: {' '.join(cmd)}")
    result = subprocess.run(cmd, env=env)
    if result.returncode != 0:
        print(f"Error during {description}. Exiting.")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Moontide Asset Factory: Download, Sample, and Train KAN models.")
    parser.add_argument("model", help="Model name (bunny, armadillo, dragon) or direct URL to .obj file")
    parser.add_argument("--epochs", type=int, default=2000, help="Number of training epochs")
    parser.add_argument("--batch-size", type=int, default=10000, help="Training batch size")
    parser.add_argument("--lr", type=float, default=0.001, help="Learning rate")
    parser.add_argument("--no-eikonal", action="store_true", help="Disable Eikonal loss for 4x faster training")
    
    args = parser.parse_args()

    # 1. Download
    url = MODELS.get(args.model, args.model)
    obj_path = "current_model.obj"
    if url.startswith("http"):
        run_cmd(["wget", "-O", obj_path, url], f"Downloading {args.model}")
    else:
        obj_path = url # Assume local path

    # 2. Sample (using Mooncrust)
    pcb_path = "current_dataset.pcb"
    mc_bin = "./extensions/mooncrust/build/mooncrust"
    if not os.path.exists(mc_bin):
        print(f"Error: Mooncrust binary not found at {mc_bin}. Please build it first.")
        sys.exit(1)
    
    env = os.environ.copy()
    env["SDL_VIDEODRIVER"] = "offscreen"
    run_cmd([mc_bin, "projects/objaverse_sampler", obj_path, pcb_path], "Sampling mesh to SDF Point Cloud (GPU)", env=env)

    # 3. Train (using Moontide Zig Trainer)
    cmd = ["zig", "build", "train", "-Doptimize=ReleaseFast", "--", pcb_path, str(args.epochs), str(args.batch_size), str(args.lr)]
    if args.no_eikonal:
        cmd.append("--no-eikonal")
    
    run_cmd(cmd, "Training KAN model (CPU AVX-512 ReleaseFast)")

    print("\n" + "="*40)
    print("ASSET FACTORY COMPLETE")
    print(f"Final Model: model.kan")
    print("Run './extensions/mooncrust/build/mooncrust projects/kan_viewer' to view the results.")
    print("="*40)

if __name__ == "__main__":
    main()
