#!/bin/bash

#run:  nohup ./convert.sh /my/videos preset &
# Capture the first argument as the input directory
INPUT_DIR="$1"
LOG_FILE="found-files.log"

# Argument & Directory Validation
if [[ -z "$INPUT_DIR" ]]; then
    echo "Usage: $0 /path/to/input_directory"
    exit 1
fi

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Directory '$INPUT_DIR' not found."
    exit 1
fi

# Counters for summary
count_success=0
count_skipped=0
count_loop=0

# Function to generate current timestamp
timestamp() {
    date "+[%Y-%m-%d %H:%M:%S]"
}

# Log Start Header
echo "**************************************************************************************" >> "$LOG_FILE"
echo "$(timestamp) Starting new Conversion Count" >> "$LOG_FILE"
echo "$(timestamp) Input Directory: $INPUT_DIR" >> "$LOG_FILE"
echo "**************************************************************************************" >> "$LOG_FILE"


# Process files recursively all mkv, avi, mp4 files
# - select all mkv, avi, mp4,ogm, wmv, mov files
# - skip all AV1.mp4 files  
while IFS= read -r file; do

    ((count_loop++))
    filename=$(basename "$file")

	if [[ "$filename"  == *"AV1.mp4" ]]; then
		echo "$(timestamp) Skipping:   $filename" >> "$LOG_FILE"
		((count_skipped++))
	else
		echo "$(timestamp) Processing: $filename" >> "$LOG_FILE"
		((count_success++))
	fi

done < <(find "$INPUT_DIR" -type f \( -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp4" -o -iname "*.ogm" -o -iname "*.wmv" -o -iname "*.mov" \))

echo "$(timestamp) Batch processing complete." >> "$LOG_FILE"
echo "$(timestamp)***************************************************************" >> "$LOG_FILE"
echo "$(timestamp) BATCH COMPLETE" >> "$LOG_FILE"
echo "$(timestamp) Process: $count_success" >> "$LOG_FILE"
echo "$(timestamp) Skipped: $count_skipped" >> "$LOG_FILE"
echo "$(timestamp) Total:   $count_loop" >> "$LOG_FILE"
echo "**************************************************************************************" >> "$LOG_FILE"

