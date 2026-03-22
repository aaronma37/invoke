import trimesh
import numpy as np
import sys

def normalize_mesh(input_path, output_path, target_radius=1.2):
    mesh = trimesh.load(input_path, force='mesh')
    
    # Center
    center = mesh.bounds.mean(axis=0)
    mesh.vertices -= center
    
    # Scale
    max_dist = np.linalg.norm(mesh.vertices, axis=1).max()
    scale = target_radius / max_dist
    mesh.vertices *= scale
    
    mesh.export(output_path)
    print(f"Normalized {input_path} to {output_path}")
    print(f"New bounds: {mesh.bounds}")

if __name__ == "__main__":
    normalize_mesh(sys.argv[1], sys.argv[2])
