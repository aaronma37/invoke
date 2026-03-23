import numpy as np
import sys
import os

def apply_pcb_to_base(base_obj, pcb_path, output_obj):
    # PCB format: u, v, z_zero, sdf, r, g, b, roughness, metallic (9 floats)
    # The GPU sampler saves samples in the EXACT order of the base mesh vertices
    data = np.fromfile(pcb_path, dtype=np.float32).reshape(-1, 9)
    
    with open(base_obj, 'r') as f:
        lines = f.readlines()

    new_lines = []
    v_idx = 0
    
    print(f"Applying {len(data)} samples to {base_obj}...")

    for line in lines:
        if line.startswith('v '):
            if v_idx < len(data):
                parts = line.split()
                # Original position
                ox, oy, oz = float(parts[1]), float(parts[2]), float(parts[3])
                # Displacement vector from (r, g, b) fields
                dx, dy, dz = data[v_idx][4], data[v_idx][5], data[v_idx][6]
                
                # new_pos = base_pos + displacement
                # (Note: The GPU sampler computes displacement = target - base, 
                # so hit_pos = origin + displacement)
                nx, ny, nz = ox + dx, oy + dy, oz + dz
                new_lines.append(f"v {nx:.6f} {ny:.6f} {nz:.6f}\n")
                v_idx += 1
            else:
                new_lines.append(line)
        else:
            new_lines.append(line)

    with open(output_obj, 'w') as f:
        f.writelines(new_lines)

    print(f"Saved displaced mesh to {output_obj}")

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python apply_pcb_to_base.py <base.obj> <samples.pcb> <output.obj>")
    else:
        apply_pcb_to_base(sys.argv[1], sys.argv[2], sys.argv[3])
