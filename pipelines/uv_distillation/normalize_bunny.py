import trimesh
import numpy as np
import sys

def normalize(input_obj, output_obj):
    mesh = trimesh.load(input_obj, force='mesh')
    
    # 1. Center at origin
    center = mesh.bounds.mean(axis=0)
    mesh.vertices -= center
    
    # 2. Scale to fit in a -0.3 to 0.3 box (so it's inside our 0.5 sphere)
    max_dist = np.max(np.linalg.norm(mesh.vertices, axis=1))
    mesh.vertices *= (0.3 / max_dist)
    
    mesh.export(output_obj)
    print(f"Normalized {input_obj} -> {output_obj}")
    print(f"New Bounds: {mesh.bounds}")

if __name__ == "__main__":
    normalize(sys.argv[1], sys.argv[2])
