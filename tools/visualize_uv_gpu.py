import numpy as np
import sys
import os

def visualize_gpu_pcb(pcb_path, obj_path):
    # PCB format: u, v, z_zero, sdf, r, g, b, roughness, metallic (9 floats)
    data = np.fromfile(pcb_path, dtype=np.float32).reshape(-1, 9)
    
    with open(obj_path, 'w') as f:
        f.write("# Moontide GPU Displacement Visualization\n")
        f.write("# V = (r, g, b) displacement vector\n")
        
        for i in range(len(data)):
            row = data[i]
            u, v = row[0], row[1]
            sdf = row[3]
            dx, dy, dz = row[4], row[5], row[6]
            
            # We visualize the displacement vectors as points in space
            # centered around (0,0,0) to see the "shape" of the deformation
            f.write(f"v {dx:.6f} {dy:.6f} {dz:.6f}\n")

    print(f"Visualized {len(data)} samples to {obj_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python visualize_uv_gpu.py <input.pcb> <output.obj>")
    else:
        visualize_gpu_pcb(sys.argv[1], sys.argv[2])
