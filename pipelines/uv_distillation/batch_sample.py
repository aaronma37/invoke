import os
import subprocess
import sys
import glob

def batch_sample(dataset_dir, base_obj, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    
    # Sort files to ensure order consistency
    files = sorted(glob.glob(os.path.join(dataset_dir, "vroid_*.obj")))
    print(f"Batch Sampler: Found {len(files)} models.")

    for i, target in enumerate(files):
        name = os.path.basename(target).replace(".obj", ".pcb")
        pcb_out = os.path.join(output_dir, name)
        
        # Use GPU Sampler
        cmd = [
            "./extensions/mooncrust/build/mooncrust", 
            "projects/uv_sampler_gpu", 
            target, 
            pcb_out, 
            base_obj
        ]
        
        env = os.environ.copy()
        env["SDL_VIDEODRIVER"] = "offscreen"
        
        print(f"[{i+1}/{len(files)}] Sampling {target}...")
        result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error sampling {target}:")
            print(result.stdout)
            print(result.stderr)
            sys.exit(1)

    print(f"\nBatch Sampling Complete! 500 .pcb files in {output_dir}")

if __name__ == "__main__":
    batch_sample(sys.argv[1], sys.argv[2], sys.argv[3])
