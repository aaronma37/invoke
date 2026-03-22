import numpy as np
import trimesh
import sys
import os

def verify_pcb(base_obj_path, pcb_path, output_obj_path):
    print(f"Verifying dataset: {pcb_path} using base {base_obj_path}")
    
    # 1. Load base mesh
    base_mesh = trimesh.load(base_obj_path, force='mesh')
    num_verts = len(base_mesh.vertices)
    
    # 2. Load PCB data
    # PointSample: x, y, z, sdf, r, g, b, roughness, metallic (all f32)
    # For UV displacement: x=u, y=v, z=unused, sdf=displacement
    data = np.fromfile(pcb_path, dtype=[
        ("u", "f4"), ("v", "f4"), ("z", "f4"), 
        ("sdf", "f4"), 
        ("r", "f4"), ("g", "f4"), ("b", "f4"), 
        ("roughness", "f4"), ("metallic", "f4")
    ])
    
    if len(data) != num_verts:
        print(f"Warning: PCB sample count ({len(data)}) does not match base vertex count ({num_verts})")
        # If it's 3x, it's likely sampled per face-corner
        if len(data) == len(base_mesh.faces) * 3:
            print("Detected face-corner sampling. Proceeding with face-split reconstruction.")
            new_verts = []
            for i in range(len(base_mesh.faces)):
                face = base_mesh.faces[i]
                for j in range(3):
                    v_idx = face[j]
                    p = base_mesh.vertices[v_idx]
                    # We need the normal. Trimesh vertex_normals are averaged.
                    # For a sphere, we can use normalized position.
                    n = p / np.linalg.norm(p)
                    d = data[i*3 + j]["sdf"]
                    new_verts.append(p + n * d)
            
            # Export as point cloud or mesh
            cloud = trimesh.points.PointCloud(new_verts)
            cloud.export(output_obj_path)
            print(f"Exported raw dataset visualization to {output_obj_path}")
            return

    # Assuming 1:1 mapping for simplicity if counts match
    displaced_verts = []
    for i in range(min(len(data), num_verts)):
        p = base_mesh.vertices[i]
        n = base_mesh.vertex_normals[i]
        d = data[i]["sdf"]
        displaced_verts.append(p + n * d)
        
    cloud = trimesh.points.PointCloud(displaced_verts)
    cloud.export(output_obj_path)
    print(f"Exported raw dataset visualization to {output_obj_path}")

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 verify_dataset.py <base.obj> <data.pcb> <output.obj>")
    else:
        verify_pcb(sys.argv[1], sys.argv[2], sys.argv[3])
