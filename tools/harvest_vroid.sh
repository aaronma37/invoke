#!/bin/bash

# Define your Unity project path
UNITY_PROJECT_DIR="/home/aaron-ma/VRoidDatasetGen"

# Find the Unity Editor executable (installed via Unity Hub on Linux)
UNITY_EXE=$(find ~/Unity/Hub/Editor -name "Unity" -type f -executable | grep "2022.3" | head -n 1)

if [ -z "$UNITY_EXE" ]; then
    echo "Could not find Unity 2022.3 Editor in ~/Unity/Hub/Editor/"
    echo "Please set the path manually in this script."
    exit 1
fi

echo "Found Unity Editor: $UNITY_EXE"
echo "Syncing Randomization Script from workspace..."
cp UnityDatasetGenerator.cs "$UNITY_PROJECT_DIR/Assets/Scripts/UnityDatasetGenerator.cs"

echo "Starting Headless Harvest..."

# Run Unity in headless batch mode, execute our C# method, and quit
$UNITY_EXE -batchmode -nographics \
    -projectPath "$UNITY_PROJECT_DIR" \
    -executeMethod DatasetGenerator.Generate \
    -quit \
    -logFile /dev/stdout

echo ""
echo "Harvest Complete! Check $UNITY_PROJECT_DIR/Dataset_Output/"

echo "--- Starting Post-Processing (Clipping & Cleaning) ---"
OUTPUT_DIR="artifacts/raw/vroid_batch"
mkdir -p "$OUTPUT_DIR"

for f in "$UNITY_PROJECT_DIR/Dataset_Output/"vroid_*.obj; do
    base=$(basename "$f")
    python3 tools/crop_mesh.py "$f" "$OUTPUT_DIR/$base"
done

echo "Copying Metadata..."
cp "$UNITY_PROJECT_DIR/Dataset_Output/vroid_metadata.json" "artifacts/datasets/vroid_latents_manual.json"

echo "Post-Processing Complete! Cleaned models are in $OUTPUT_DIR"
