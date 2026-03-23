
import sys

def analyze_obj(path):
    vertices = []
    faces = []
    with open(path, 'r') as f:
        for line in f:
            if line.startswith('v '):
                vertices.append(list(map(float, line.split()[1:4])))
            elif line.startswith('f '):
                # f v1/vt1/vn1 v2/vt2/vn2 ...
                face = [int(p.split('/')[0]) - 1 for p in line.split()[1:]]
                faces.append(face)
    
    print(f"Total Vertices: {len(vertices)}")
    print(f"Total Faces: {len(faces)}")
    
    # Simple connectivity check
    adj = [set() for _ in range(len(vertices))]
    for face in faces:
        for i in range(len(face)):
            v1 = face[i]
            v2 = face[(i+1)%len(face)]
            adj[v1].add(v2)
            adj[v2].add(v1)
            
    # BFS to find connected components
    visited = [False] * len(vertices)
    components = 0
    for i in range(len(vertices)):
        if not visited[i]:
            components += 1
            stack = [i]
            visited[i] = True
            while stack:
                u = stack.pop()
                for v in adj[u]:
                    if not visited[v]:
                        visited[v] = True
                        stack.append(v)
    
    print(f"Connected Components: {components}")

if __name__ == "__main__":
    analyze_obj(sys.argv[1])
