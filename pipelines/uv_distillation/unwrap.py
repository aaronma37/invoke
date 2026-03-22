import sys
import os
import argparse
import trimesh
import xatlas
import numpy as np

def generate_base_mesh(image_path):
    print(f"Generating base mesh from {image_path}...")
    if image_path.endswith('.obj'):
        mesh = trimesh.load(image_path, force='mesh')
    else:
        # Fallback to a sphere primitive
        mesh = trimesh.creation.icosphere(subdivisions=2, radius=1.0)
    
    print(f"Base mesh loaded: {len(mesh.vertices)} vertices, {len(mesh.faces)} faces.")
    return mesh

def unwrap_mesh(mesh, output_path):
    print("Unwrapping mesh with xatlas to generate UVs...")
    
    # 1. Parameterize the mesh using xatlas
    vmapping, indices, uvs = xatlas.parametrize(mesh.vertices, mesh.faces)
    
    # 2. Rebuild the mesh with the new split vertices
    new_vertices = mesh.vertices[vmapping]
    
    # 3. Save the unwrapped OBJ
    with open(output_path, 'w') as f:
        for v in new_vertices:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        for uv in uvs:
            f.write(f"vt {uv[0]:.6f} {uv[1]:.6f}\n")
        for face in indices:
            f.write(f"f {face[0]+1}/{face[0]+1} {face[1]+1}/{face[1]+1} {face[2]+1}/{face[2]+1}\n")
            
    print(f"Successfully saved unwrapped base mesh to {output_path}")
    return new_vertices, indices, uvs

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Unwrap a mesh to generate UVs")
    parser.add_argument("input", help="Path to input .obj or image")
    parser.add_argument("output", help="Path to save the unwrapped .obj")
    
    args = parser.parse_args()
    
    base_mesh = generate_base_mesh(args.input)
    unwrap_mesh(base_mesh, args.output)
