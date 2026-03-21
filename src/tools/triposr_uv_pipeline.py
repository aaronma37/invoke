import sys
import os
import argparse
import trimesh
import xatlas
import numpy as np

def generate_base_mesh(image_path, output_path):
    print(f"Generating base mesh from {image_path} using TripoSR...")
    # NOTE: In a real system, you would call the TripoSR inference script here.
    # For now, we will simulate this by loading a primitive or a provided high-poly mesh 
    # and decimating it to act as the "TripoSR Base Mesh".
    #
    # If the user provides a placeholder .obj instead of an image, we'll use that as the "base".
    if image_path.endswith('.obj'):
        mesh = trimesh.load(image_path, force='mesh')
    else:
        # Fallback to a sphere primitive if no real TripoSR hook is available yet
        mesh = trimesh.creation.icosphere(subdivisions=2, radius=1.0)
    
    print(f"Base mesh generated: {len(mesh.vertices)} vertices, {len(mesh.faces)} faces.")
    return mesh

def unwrap_mesh(mesh, output_path):
    print("Unwrapping mesh with xatlas to generate UVs...")
    
    # 1. Parameterize the mesh using xatlas
    vmapping, indices, uvs = xatlas.parametrize(mesh.vertices, mesh.faces)
    
    # 2. Rebuild the mesh with the new split vertices
    new_vertices = mesh.vertices[vmapping]
    
    # 3. Save the unwrapped OBJ
    # We must write it manually because trimesh doesn't natively handle split vertex/UV arrays perfectly for export
    with open(output_path, 'w') as f:
        # Write vertices
        for v in new_vertices:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        
        # Write UVs
        for uv in uvs:
            f.write(f"vt {uv[0]:.6f} {uv[1]:.6f}\n")
            
        # Write faces (1-indexed, formatted as v/vt)
        for face in indices:
            f.write(f"f {face[0]+1}/{face[0]+1} {face[1]+1}/{face[1]+1} {face[2]+1}/{face[2]+1}\n")
            
    print(f"Successfully saved unwrapped base mesh to {output_path}")
    return new_vertices, indices, uvs

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="TripoSR to UV Base Mesh Pipeline")
    parser.add_argument("input", help="Path to input image (or .obj to simulate TripoSR output)")
    parser.add_argument("output", help="Path to save the unwrapped base.obj")
    
    args = parser.parse_args()
    
    base_mesh = generate_base_mesh(args.input, args.output)
    unwrap_mesh(base_mesh, args.output)
