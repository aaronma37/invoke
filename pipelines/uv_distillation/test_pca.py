import numpy as np
import trimesh
import sys
import os
import glob
from sklearn.decomposition import PCA

def test_pca_component(dataset_dir, base_obj_path, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    
    files = sorted(glob.glob(os.path.join(dataset_dir, "vroid_*.pcb")))
    
    print("Loading base mesh...")
    base_mesh = trimesh.load(base_obj_path, force='mesh')
    
    print("Loading displacements...")
    def load_disp(p):
        data = np.fromfile(p, dtype=np.float32).reshape(-1, 9)
        return data[:, 4:7].flatten()
    
    matrix = np.zeros((len(files), len(load_disp(files[0]))), dtype=np.float32)
    for i, f in enumerate(files):
        matrix[i] = load_disp(f)
        
    print("Running PCA...")
    pca = PCA(n_components=16)
    pca.fit(matrix)
    
    # Let's generate a mesh where Slider 0 is +3 standard deviations, and everything else is 0
    std_devs = np.sqrt(pca.explained_variance_)
    
    for slider_idx in range(3):
        # Create latent vector
        z = np.zeros(16)
        z[slider_idx] = std_devs[slider_idx] * 3.0 # +3 Std Devs
        
        # Inverse transform to get vertex displacements
        flat_disp = pca.inverse_transform(z.reshape(1, -1))[0]
        disp_vectors = flat_disp.reshape(-1, 3)
        
        # Apply to base mesh
        # Note: base_mesh.vertices might be smaller than disp_vectors if faces are duplicated.
        # We need to map it carefully.
        # But wait! Our sampler sampled the UNIQUE vertices of the base mesh?
        # Let's check projects/uv_sampler_gpu/main.lua:
        # local base_verts_raw = loader.load(base_path) ... local num_queries = #base_verts_raw
        # The loader returns unique vertices? No, loader.lua triangulates and duplicates.
        # So disp_vectors is aligned exactly with the duplicated vertices.
        # We can just write them out directly.
        
        out_path = os.path.join(output_dir, f"pca_slider_{slider_idx}.obj")
        with open(out_path, "w") as f:
            f.write("# PCA Debug Mesh\n")
            
            # Write displaced vertices
            idx = 0
            for face in base_mesh.faces:
                for v_idx in face:
                    base_pos = base_mesh.vertices[v_idx]
                    d = disp_vectors[idx]
                    f.write(f"v {base_pos[0]+d[0]:.6f} {base_pos[1]+d[1]:.6f} {base_pos[2]+d[2]:.6f}\n")
                    idx += 1
            
            # Write faces
            v_offset = 1
            for face in base_mesh.faces:
                f.write(f"f {v_offset} {v_offset+1} {v_offset+2}\n")
                v_offset += 3
        
        print(f"Exported PCA Slider {slider_idx} to {out_path}")

if __name__ == "__main__":
    test_pca_component(sys.argv[1], sys.argv[2], sys.argv[3])
