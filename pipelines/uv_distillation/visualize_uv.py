import trimesh
import numpy as np
import sys

def visualize_uv_layout(obj_path, output_path):
    mesh = trimesh.load(obj_path, force='mesh')
    
    # Create a new mesh where vertex positions are the UV coordinates
    # We'll map (u, v) -> (x, y) and set z to 0
    uvs = mesh.visual.uv
    new_vertices = np.zeros((len(uvs), 3))
    new_vertices[:, 0] = uvs[:, 0]
    new_vertices[:, 1] = uvs[:, 1]
    
    # Create the mesh
    uv_mesh = trimesh.Trimesh(vertices=new_vertices, faces=mesh.faces)
    uv_mesh.export(output_path)
    print(f"Exported UV layout visualization to {output_path}")

if __name__ == "__main__":
    visualize_uv_layout(sys.argv[1], sys.argv[2])
