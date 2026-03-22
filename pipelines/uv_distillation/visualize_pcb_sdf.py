import numpy as np
import trimesh
import sys
import argparse

def visualize_pcb_sdf(pcb_path, base_obj_path, output_obj):
    # Load base mesh to get vertices and normals
    base_mesh = trimesh.load(base_obj_path, force='mesh')
    base_verts = base_mesh.vertices
    # Ensure we have enough vertices (the sampler samples every vertex of every face)
    # Actually, the sampler iterates through faces and then 3 vertices per face.
    # So we should reconstruct the points from the face loop.
    
    # PointSample: u, v, z, sdf, r, g, b, rough, metal (9 floats)
    data = np.fromfile(pcb_path, dtype=np.float32).reshape(-1, 9)
    sdf = data[:, 3]
    
    points = []
    
    # Replicate the logic in sampler_uv.zig / main.lua
    idx = 0
    for face in base_mesh.faces:
        for v_idx in face:
            orig = base_mesh.vertices[v_idx]
            # Normal calculation (simple vertex normal for visualization)
            norm = base_mesh.vertex_normals[v_idx]
            
            # Displace by SDF
            # The GPU sampler calculates SDF as (hit_t - offset)
            # where ray was (base_pos - dir*offset) -> (base_pos + dir*(hit_t - offset))
            # So displaced point = base_pos + dir * sdf
            displaced = orig + norm * sdf[idx]
            points.append(displaced)
            idx += 1
            if idx >= len(data): break
        if idx >= len(data): break

    print(f"Visualizing {len(points)} displaced points.")
    cloud = trimesh.points.PointCloud(points)
    cloud.export(output_obj)
    print(f"Saved displaced point cloud to {output_obj}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("pcb", help="Path to .pcb")
    parser.add_argument("base", help="Path to base .obj")
    parser.add_argument("output", help="Path to output .obj")
    args = parser.parse_args()
    visualize_pcb_sdf(args.pcb, args.base, args.output)
