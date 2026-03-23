import struct
import sys
import os

def pcb_to_obj_direct(pcb_path, base_obj_path, output_obj):
    # 1. Load base vertices
    base_verts = []
    with open(base_obj_path, 'r') as f:
        for line in f:
            if line.startswith('v '):
                base_verts.append([float(x) for x in line.split()[1:4]])
    
    # 2. Load face data to match sampler's vertex-per-corner ordering
    faces = []
    with open(base_obj_path, 'r') as f:
        for line in f:
            if line.startswith('f '):
                parts = line.split()[1:]
                face = [int(p.split('/')[0]) - 1 for p in parts]
                faces.append(face)

    # 3. Load PCB binary data
    if not os.path.exists(pcb_path):
        print(f"Error: {pcb_path} not found.")
        return
        
    with open(pcb_path, 'rb') as f:
        data = f.read()
    
    num_samples = len(data) // 36 # 9 floats * 4 bytes
    print(f"Loading {num_samples} samples from PCB...")

    with open(output_obj, 'w') as out:
        out.write("# Moontide Sampler Debug Output (Direct Displacement)\n")
        
        idx = 0
        for f in faces:
            for v_idx in f:
                if idx >= num_samples: break
                
                # struct { float u, v, z, sdf, r, g, b, rough, metal }
                # Displacement dx, dy, dz is in r, g, b (indices 4, 5, 6)
                sample = struct.unpack('fffffffff', data[idx*36:(idx+1)*36])
                dx, dy, dz = sample[4], sample[5], sample[6]
                
                base_pos = base_verts[v_idx]
                px = base_pos[0] + dx
                py = base_pos[1] + dy
                pz = base_pos[2] + dz
                
                # Write vertex with a diagnostic color (Red if large displacement)
                dist = (dx*dx + dy*dy + dz*dz)**0.5
                r = min(1.0, dist * 5.0)
                out.write(f"v {px:.6f} {py:.6f} {pz:.6f} {r:.2f} 0.5 0.5\n")
                idx += 1
            if idx >= num_samples: break
            
        # Write faces
        v_offset = 1
        for i in range(len(faces)):
            if v_offset + 2 > idx: break
            out.write(f"f {v_offset} {v_offset+1} {v_offset+2}\n")
            v_offset += 3

    print(f"Successfully exported sampler output to {output_obj}")

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 pcb_to_obj_debug.py <input.pcb> <base.obj> <output.obj>")
    else:
        pcb_to_obj_direct(sys.argv[1], sys.argv[2], sys.argv[3])
