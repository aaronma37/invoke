import sys
import os

def crop_obj(input_path, output_path):
    if not os.path.exists(input_path):
        print(f"Error: {input_path} not found.")
        return

    with open(input_path, 'r') as f:
        lines = f.readlines()

    vertices = []
    normals = []
    uvs = []
    faces = []
    
    # Clipping bounds (adjust based on VRoid scale)
    HEAD_Y = 1.42
    FOOT_Y = 0.15
    HAND_X = 0.65
    ARM_Y_THRESHOLD = 0.8 # Only clip X if above this height (to avoid clipping hips)

    valid_v_indices = []
    new_vertices = []
    new_normals = []
    new_uvs = []
    
    v_idx = 1
    for line in lines:
        if line.startswith('v '):
            parts = line.split()
            x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
            
            is_valid = True
            if y > HEAD_Y: is_valid = False
            if y < FOOT_Y: is_valid = False
            if abs(x) > HAND_X and y > ARM_Y_THRESHOLD: is_valid = False
            
            if is_valid:
                valid_v_indices.append(v_idx)
                new_vertices.append((x, y, z))
            v_idx += 1
        elif line.startswith('vn '):
            normals.append(line)
        elif line.startswith('vt '):
            uvs.append(line)
        elif line.startswith('f '):
            faces.append(line)

    # Map old indices to new indices
    idx_map = {}
    for i, old_idx in enumerate(valid_v_indices):
        idx_map[old_idx] = i + 1

    # Reconstruct the OBJ
    with open(output_path, 'w') as f:
        f.write("# Moontide Cropped Torso\n")
        for v in new_vertices:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        
        # Note: This simple script assumes 1:1 V/VN/VT for simplicity, 
        # which is true for our Unity unified export.
        for i, old_idx in enumerate(valid_v_indices):
            # Try to find corresponding normal/uv if they exist in order
            if old_idx <= len(normals): f.write(normals[old_idx-1])
            if old_idx <= len(uvs): f.write(uvs[old_idx-1])

        for face_line in faces:
            parts = face_line.split()
            new_face_parts = ["f"]
            valid_face = True
            for p in parts[1:]:
                v_parts = p.split('/')
                old_v_idx = int(v_parts[0])
                if old_v_idx not in idx_map:
                    valid_face = False
                    break
                
                new_v_idx = idx_map[old_v_idx]
                # Re-index VN and VT as well (assuming 1:1)
                new_face_parts.append(f"{new_v_idx}/{new_v_idx}/{new_v_idx}")
            
            if valid_face:
                f.write(" ".join(new_face_parts) + "\n")

    print(f"Cropped {input_path} -> {output_path} (Vertices: {len(new_vertices)})")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python crop_mesh.py <input.obj> <output.obj>")
    else:
        crop_obj(sys.argv[1], sys.argv[2])
