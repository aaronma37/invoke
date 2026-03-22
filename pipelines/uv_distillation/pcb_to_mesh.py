import numpy as np
import sys
import trimesh

def load_obj_flat(path):
    positions = []
    flat_verts = []
    with open(path, 'r') as f:
        for line in f:
            if line.startswith('v '):
                parts = line.split()
                positions.append([float(parts[1]), float(parts[2]), float(parts[3])])
            elif line.startswith('f '):
                parts = line.split()[1:]
                face_indices = [int(p.split('/')[0]) - 1 for p in parts]
                # Triangulate fan matching loader.lua
                for i in range(1, len(face_indices) - 1):
                    flat_verts.append(positions[face_indices[0]])
                    flat_verts.append(positions[face_indices[i]])
                    flat_verts.append(positions[face_indices[i+1]])
    return np.array(flat_verts)

def pcb_to_mesh(base_obj_path, pcb_path, output_obj_path):
    print(f"Loading base: {base_obj_path}")
    flat_vertices = load_obj_flat(base_obj_path)
    
    print(f"Loading PCB: {pcb_path}")
    data = np.fromfile(pcb_path, dtype=np.float32).reshape(-1, 9)
    
    dxs, dys, dzs = data[:, 3], data[:, 4], data[:, 5]
    deltas = np.stack([dxs, dys, dzs], axis=1)
    
    if len(flat_vertices) != len(deltas):
        print(f"Warning: PCB size ({len(deltas)}) != triangulated base ({len(flat_vertices)}).")
        length = min(len(flat_vertices), len(deltas))
        flat_vertices = flat_vertices[:length]
        deltas = deltas[:length]
    
    # 1. Reconstructed Mesh (Base + Delta)
    displaced_vertices = flat_vertices + deltas

    # Create faces for the new flat mesh
    new_faces = np.arange(len(displaced_vertices)).reshape(-1, 3)
    out_mesh = trimesh.Trimesh(vertices=displaced_vertices, faces=new_faces)
    out_mesh.export(output_obj_path)
    print(f"Exported mesh to: {output_obj_path}")

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python pcb_to_mesh.py <base.obj> <samples.pcb> <output.obj>")
    else:
        pcb_to_mesh(sys.argv[1], sys.argv[2], sys.argv[3])
