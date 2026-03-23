import os
import subprocess
import sys
import glob
import concurrent.futures

def process_single(target, base_obj_path, output_dir, idx, total):
    name = os.path.basename(target).replace(".obj", ".pcb")
    pcb_out = os.path.join(output_dir, name)
    
    cmd = [
        "./extensions/mooncrust/build/mooncrust", 
        "projects/uv_sampler_gpu", 
        target, 
        pcb_out, 
        base_obj_path
    ]
    
    env = os.environ.copy()
    env["SDL_VIDEODRIVER"] = "offscreen"
    
    print(f"[{idx}/{total}] Sampling {os.path.basename(target)}...")
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        
    if result.returncode != 0:
        print(f"Error sampling {target}:\n{result.stdout}\n{result.stderr}")
        return False
    return True

def batch_sample(dataset_dir, base_obj_path, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    
    files = sorted(glob.glob(os.path.join(dataset_dir, "vroid_*.obj")))
    files = [f for f in files if "_aligned" not in f]
    
    total = len(files)
    print(f"Batch Sampler: Found {total} models. Starting parallel sampling...")

    max_workers = 10
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = []
        for i, target in enumerate(files):
            futures.append(executor.submit(process_single, target, base_obj_path, output_dir, i+1, total))
            
        for future in concurrent.futures.as_completed(futures):
            success = future.result()
            if not success:
                print("A sampling task failed. Aborting.")
                sys.exit(1)

    print(f"\nBatch Sampling Complete! {total} .pcb files in {output_dir}")

if __name__ == "__main__":
    batch_sample(sys.argv[1], sys.argv[2], sys.argv[3])
