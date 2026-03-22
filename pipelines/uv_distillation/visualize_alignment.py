import trimesh
import numpy as np
import sys

def visualize_alignment(target_path, base_path, pcb_path, output_obj):
    target = trimesh.load(target_path, force='mesh')
    base = trimesh.load(base_path, force='mesh')
    
    # 1. Load PCB to see the deltas
    data = np.fromfile(pcb_path, dtype=np.float32).reshape(-1, 9)
    base_pts = data[:, 0:3]
    deltas = data[:, 3:6]
    hit_pts = base_pts + deltas
    
    # Create lines showing the displacements (as small cylinders or just merged points)
    # Merging multiple meshes into one for OBJ export
    
    # Give them distinct positions for side-by-side view if desired, 
    # but here we want to see the OVERLAP.
    
    # Add a small offset to base so it doesn't z-fight with target surface
    # base.vertices += 0.001 
    
    combined = trimesh.util.concatenate([target, base])
    combined.export(output_obj)
    print(f"Exported combined mesh to {output_obj}")
    print(f"Target Center: {target.bounds.mean(axis=0)}")
    print(f"Base Center:   {base.bounds.mean(axis=0)}")

if __name__ == "__main__":
    visualize_alignment(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
