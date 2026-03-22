import sys
import trimesh
import numpy as np

def extract_neutral_base(vrm_path, output_obj):
    print(f"Loading {vrm_path}...")
    # Load VRM as GLB
    mesh = trimesh.load(vrm_path, file_type='glb', force='mesh')
    
    if isinstance(mesh, trimesh.Scene):
        mesh = mesh.dump(concatenate=True)
    
    print(f"Neutral Base: {len(mesh.vertices)} vertices, {len(mesh.faces)} faces.")
    
    # Export to OBJ
    mesh.export(output_obj)
    print(f"Exported true neutral base to {output_obj}")

if __name__ == "__main__":
    extract_neutral_base(sys.argv[1], sys.argv[2])
