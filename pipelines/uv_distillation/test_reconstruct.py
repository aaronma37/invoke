import json
import sys
import subprocess

def test_reconstruction(model_name):
    with open("artifacts/datasets/vroid_latents.json", "r") as f:
        latents = json.load(f)
    
    if model_name not in latents:
        print(f"Model {model_name} not found in latents.json")
        return
        
    z = latents[model_name]
    print(f"Latent vector for {model_name}: {z}")
    
    cmd = [
        "./zig-out/bin/reconstruct-vae",
        "/home/aaron-ma/VRoidDatasetGen/Dataset_Output/vroid_0000.obj",
        "artifacts/models/vroid_vae_kan.kan",
        f"artifacts/eval/{model_name}_reconstructed.obj"
    ] + [str(val) for val in z]
    
    subprocess.run(cmd)

if __name__ == "__main__":
    test_reconstruction(sys.argv[1])
