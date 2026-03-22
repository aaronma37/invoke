using UnityEngine;
using UnityEditor;
using System.IO;
using System.Text;
using System.Collections.Generic;
using UniVRM10; // UniVRM 1.0 (VRM 1.x)

public class DatasetGenerator : EditorWindow
{
    [MenuItem("Moontide/Generate Dataset")]
    public static void Generate()
    {
        // --- CONFIGURATION ---
        string masterPath = "Assets/MasterModel.prefab"; 
        string outputFolder = "Dataset_Output/";
        int count = 500; 
        // ---------------------

        if (!Directory.Exists(outputFolder)) Directory.CreateDirectory(outputFolder);

        // Load the Model Prefab
        GameObject master = AssetDatabase.LoadAssetAtPath<GameObject>(masterPath);
        if (master == null) {
            Debug.LogError($"Master Model not found at {masterPath}! Make sure to drag your .vrm into Unity and rename the resulting Prefab to MasterModel.");
            return;
        }

        GameObject instance = Instantiate(master);
        Vrm10Instance vrmInstance = instance.GetComponent<Vrm10Instance>();
        Animator anim = instance.GetComponent<Animator>();

        Debug.Log("--- Starting Dataset Generation ---");

        for (int i = 0; i < count; i++)
        {
            // 1. Randomize Proportions (Bones)
            RandomizeBone(anim, HumanBodyBones.UpperChest, 0.85f, 1.15f);
            RandomizeBone(anim, HumanBodyBones.Hips, 0.9f, 1.1f);
            RandomizeBone(anim, HumanBodyBones.Head, 0.8f, 1.2f);
            RandomizeBone(anim, HumanBodyBones.LeftUpperArm, 0.75f, 1.25f);
            RandomizeBone(anim, HumanBodyBones.RightUpperArm, 0.75f, 1.25f);
            RandomizeBone(anim, HumanBodyBones.LeftUpperLeg, 0.75f, 1.25f);
            RandomizeBone(anim, HumanBodyBones.RightUpperLeg, 0.75f, 1.25f);

            // 2. Randomize Face Morphs (UniVRM 1.0 API)
            if (vrmInstance != null) {
                var runtimeExpression = vrmInstance.Runtime.Expression;
                // Correct way to iterate in UniVRM 1.0:
                foreach (var key in runtimeExpression.ExpressionKeys)
                {
                    // Randomize weights (0 to 0.7 to avoid extreme clipping)
                    float weight = Random.Range(0f, 0.7f); 
                    runtimeExpression.SetWeight(key, weight);
                }
                vrmInstance.Runtime.Process(); // Apply changes
            }

            // 3. Export to OBJ
            string filename = outputFolder + "vroid_" + i.ToString("D4") + ".obj";
            ExportToOBJ(instance, filename);
            
            if (i % 25 == 0) Debug.Log($"Progress: {i}/{count} models exported.");
        }

        DestroyImmediate(instance);
        Debug.Log($"Dataset Generation Complete! Check the '{outputFolder}' folder.");
    }

    static void RandomizeBone(Animator anim, HumanBodyBones bone, float min, float max)
    {
        Transform t = anim.GetBoneTransform(bone);
        if (t != null) {
            float s = Random.Range(min, max);
            t.localScale = new Vector3(s, s, s);
        }
    }

    static void ExportToOBJ(GameObject root, string path)
    {
        StringBuilder sb = new StringBuilder();
        sb.AppendLine("# Moontide VAE-KAN Dataset Export");

        SkinnedMeshRenderer[] smrs = root.GetComponentsInChildren<SkinnedMeshRenderer>();
        int vertexOffset = 1;

        foreach (var smr in smrs)
        {
            Mesh mesh = new Mesh();
            smr.BakeMesh(mesh); // Captures current deformation/scaling

            Vector3[] vertices = mesh.vertices;
            for (int i = 0; i < vertices.Length; i++) {
                Vector3 worldV = smr.transform.TransformPoint(vertices[i]);
                sb.AppendLine($"v {worldV.x:F6} {worldV.y:F6} {worldV.z:F6}");
            }

            Vector3[] normals = mesh.normals;
            for (int i = 0; i < normals.Length; i++) {
                Vector3 worldN = smr.transform.TransformDirection(normals[i]);
                sb.AppendLine($"vn {worldN.x:F6} {worldN.y:F6} {worldN.z:F6}");
            }

            Vector2[] uvs = mesh.uv;
            for (int i = 0; i < uvs.Length; i++) {
                sb.AppendLine($"vt {uvs[i].x:F6} {uvs[i].y:F6}");
            }

            for (int submesh = 0; submesh < mesh.subMeshCount; submesh++)
            {
                int[] tris = mesh.GetTriangles(submesh);
                for (int i = 0; i < tris.Length; i += 3)
                {
                    int v1 = tris[i] + vertexOffset;
                    int v2 = tris[i + 1] + vertexOffset;
                    int v3 = tris[i + 2] + vertexOffset;
                    sb.AppendLine($"f {v1}/{v1}/{v1} {v2}/{v2}/{v2} {v3}/{v3}/{v3}");
                }
            }
            vertexOffset += mesh.vertexCount;
            DestroyImmediate(mesh);
        }

        File.WriteAllText(path, sb.ToString());
    }
}
