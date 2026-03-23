import numpy as np
import sys

def visualize_uv_landscape(pcb_path, obj_path):
    # PCB format: u, v, z_zero, sdf, r, g, b, roughness, metallic
    data = np.fromfile(pcb_path, dtype=np.float32).reshape(-1, 9)
    
    with open(obj_path, 'w') as f:
        f.write("# Moontide UV Landscape Visualization\n")
        f.write("# Position = (U, V, Displacement Magnitude)\n")
        
        for row in data:
            u, v = row[0], row[1]
            mag = row[3] # sdf (displacement magnitude)
            # We scale U and V to make it easier to see
            f.write(f"v {u*2:.6f} {v*2:.6f} {mag:.6f}\n")

    print(f"Visualized {len(data)} points to {obj_path}")

if __name__ == "__main__":
    visualize_uv_landscape(sys.argv[1], sys.argv[2])
