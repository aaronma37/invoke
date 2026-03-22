import trimesh
import numpy as np
import sys

def sample_unwrapped(obj_path, output_pcb, num_points=100000):
    mesh = trimesh.load(obj_path, force='mesh')
    
    # Randomly sample points on the surface
    # samples: (N, 3) XYZ coordinates
    # face_index: (N,) indices of faces samples landed on
    samples, face_index = trimesh.sample.sample_surface(mesh, num_points)
    
    # Calculate UVs for these points using barycentric interpolation
    # 1. Get the vertices of the faces we hit
    faces = mesh.faces[face_index]
    v0 = mesh.vertices[faces[:, 0]]
    v1 = mesh.vertices[faces[:, 1]]
    v2 = mesh.vertices[faces[:, 2]]
    
    # 2. Compute barycentric coordinates for each sample
    # (Using trimesh built-in if available, or manual)
    bary = trimesh.triangles.points_to_barycentric(mesh.triangles[face_index], samples)
    
    # 3. Interpolate UVs
    uv_all = mesh.visual.uv
    uv0 = uv_all[faces[:, 0]]
    uv1 = uv_all[faces[:, 1]]
    uv2 = uv_all[faces[:, 2]]
    
    # u_sample = w0*u0 + w1*u1 + w2*u2
    sampled_uvs = (uv0 * bary[:, 0:1] + 
                   uv1 * bary[:, 1:2] + 
                   uv2 * bary[:, 2:3])

    print(f"Sampled {num_points} random points on surface.")
    
    # Create PCB data (PointSample struct: 9 floats)
    # [u, v, 0, x, y, z, 0.5, 0.5, 0.5]
    data = np.zeros((num_points, 9), dtype=np.float32)
    data[:, 0] = sampled_uvs[:, 0] # U
    data[:, 1] = sampled_uvs[:, 1] # V
    data[:, 3] = samples[:, 0] # X
    data[:, 4] = samples[:, 1] # Y
    data[:, 5] = samples[:, 2] # Z
    data[:, 6:] = 0.5 # Dummy color/roughness
    
    data.tofile(output_pcb)
    print(f"Saved {num_points} samples to {output_pcb}")

if __name__ == "__main__":
    sample_unwrapped(sys.argv[1], sys.argv[2])
