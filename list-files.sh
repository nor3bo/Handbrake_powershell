#!/bin/bash

#run:  nohup ./convert.sh /my/videos preset &
# Capture the first argument as the input directory
INPUT_DIR="$1"
PRESET_FILE="./presets.json"
PRESET="$2"
LOG_FILE="found-files.log"

# Dependency Check (New)
if ! command -v HandBrakeCLI &> /dev/null; then
    echo "$(date "+[%Y-%m-%d %H:%M:%S]") ERROR: HandBrakeCLI is not installed or not in PATH." | tee -a "$LOG_FILE"
    exit 1
fi

# Argument & Directory Validation
if [[ -z "$INPUT_DIR" ]]; then
    echo "Usage: $0 /path/to/input_directory"
    exit 1
fi

if [[ -z "$PRESET" ]]; then
    echo "Usage: $0 /path/to/input_directory preset (e.g. _1080p_AV1, 38_1080p_AV1, _720p_AV1, _42_720p_AV1)"
    exit 1
fi

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Directory '$INPUT_DIR' not found."
    exit 1
fi

# Counters for summary
count_success=0
count_skipped=0
count_failed=0
count_loop=0

# Function to generate current timestamp
timestamp() {
    date "+[%Y-%m-%d %H:%M:%S]"
}

# Log Start Header
echo "**************************************************************************************" >> "$LOG_FILE"
echo "$(timestamp) Starting new Conversion Run" >> "$LOG_FILE"
echo "$(timestamp) Input Directory: $INPUT_DIR" >> "$LOG_FILE"
echo "$(timestamp) Preset: $PRESET" >> "$LOG_FILE"
echo "**************************************************************************************" >> "$LOG_FILE"


# Process files recursively all mkv, avi, mp4 files
# - select all mkv, avi, mp4,ogm, wmv files
# - skip all AV1.mp4 files  
while IFS= read -r file; do

    ((count_loop++))
    filename=$(basename "$file")
	
	echo "$(timestamp) filename: $filename" >> "$LOG_FILE"
	if [[ "$filename"  == *"AV1.mp4" ]]; then
		echo "$(timestamp) Skipping:   $file" >> "$LOG_FILE"
	else
		echo "$(timestamp) Processing: $file" >> "$LOG_FILE"
	fi

done < <(find "$INPUT_DIR" -type f \( -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp4" -o -iname "*.ogm" -o -iname "*.wmv" \))

echo "$(timestamp) Batch processing complete." >> "$LOG_FILE"
echo "$(timestamp)***************************************************************" >> "$LOG_FILE"
echo "$(timestamp) BATCH COMPLETE" >> "$LOG_FILE"
echo "$(timestamp) Success: $count_success" >> "$LOG_FILE"
echo "$(timestamp) Skipped: $count_skipped" >> "$LOG_FILE"
echo "$(timestamp) Failed:  $count_failed" >> "$LOG_FILE"
echo "**************************************************************************************" >> "$LOG_FILE"

