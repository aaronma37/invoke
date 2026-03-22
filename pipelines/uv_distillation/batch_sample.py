import os
import subprocess
import sys
import glob
import trimesh
import numpy as np
import concurrent.futures

def align_to_base(target_path, base_mesh):
    target_mesh = trimesh.load(target_path, force='mesh')
    
    # 1. Center both to origin based on bounding box
    base_center = base_mesh.bounds.mean(axis=0)
    target_center = target_mesh.bounds.mean(axis=0)
    
    target_mesh.vertices -= target_center
    
    # 2. Scale target to match base's overall height (Y-axis)
    base_height = base_mesh.bounds[1][1] - base_mesh.bounds[0][1]
    target_height = target_mesh.bounds[1][1] - target_mesh.bounds[0][1]
    
    scale_factor = base_height / target_height if target_height > 0 else 1.0
    target_mesh.vertices *= scale_factor
    
    # 3. Move target back to base's original center
    target_mesh.vertices += base_center
    
    # Save aligned version temporarily (add PID to prevent conflicts in parallel)
    aligned_path = target_path.replace(".obj", f"_aligned_{os.getpid()}.obj")
    target_mesh.export(aligned_path)
    return aligned_path

def process_single(target, base_obj_path, base_mesh, output_dir, idx, total):
    name = os.path.basename(target).replace(".obj", ".pcb")
    pcb_out = os.path.join(output_dir, name)
    
    aligned_target = align_to_base(target, base_mesh)
    
    cmd = [
        "./extensions/mooncrust/build/mooncrust", 
        "projects/uv_sampler_gpu", 
        aligned_target, 
        pcb_out, 
        base_obj_path
    ]
    
    env = os.environ.copy()
    env["SDL_VIDEODRIVER"] = "offscreen"
    
    print(f"[{idx}/{total}] Sampling {os.path.basename(target)}...")
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    
    # Clean up temporary aligned file
    if os.path.exists(aligned_target):
        os.remove(aligned_target)
        
    if result.returncode != 0:
        print(f"Error sampling {target}:\n{result.stdout}\n{result.stderr}")
        return False
    return True

def batch_sample(dataset_dir, base_obj_path, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"Loading Base Mesh: {base_obj_path}")
    base_mesh = trimesh.load(base_obj_path, force='mesh')
    
    files = sorted(glob.glob(os.path.join(dataset_dir, "vroid_*.obj")))
    files = [f for f in files if "_aligned" not in f]
    
    total = len(files)
    print(f"Batch Sampler: Found {total} models. Starting parallel sampling...")

    # Use ThreadPool to dispatch GPU tasks. 
    # Capped at 4 to prevent Vulkan Out of Memory (OOM) errors on command submission.
    max_workers = min(4, max(1, (os.cpu_count() or 4) - 2)) 
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = []
        for i, target in enumerate(files):
            futures.append(executor.submit(process_single, target, base_obj_path, base_mesh, output_dir, i+1, total))
            
        # Wait for all to complete
        for future in concurrent.futures.as_completed(futures):
            success = future.result()
            if not success:
                print("A sampling task failed. Aborting.")
                sys.exit(1)

    print(f"\nBatch Sampling Complete! {total} .pcb files in {output_dir}")

if __name__ == "__main__":
    batch_sample(sys.argv[1], sys.argv[2], sys.argv[3])
