#!/bin/bash

#run:  nohup ./convert.sh /my/videos preset &
# Capture the first argument as the input directory
INPUT_DIR="$1"
PRESET_FILE="./presets.json"
PRESET="$2"
LOG_FILE="converter.log"

# Cleanup function for unexpected exits
cleanup() {
    if [[ -f "$outfile" ]]; then
        echo "$(timestamp) INTERRUPT: Removing partial file $outfile" >> "$LOG_FILE"
        rm -f "$outfile"
    fi
    exit
}
# Trap SIGINT (Ctrl+C) and SIGTERM
trap cleanup SIGINT SIGTERM

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
    echo "Error: Preset required (e.g. _1080p_AV1, 38_1080p_AV1, _720p_AV1, _42_720p_AV1)"
    echo "Usage: $0 /path/to/input_directory preset"
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
echo "$(timestamp) Use STOP TRIGGER to end run: \"stop.y\" " >> "$LOG_FILE"
echo "**************************************************************************************" >> "$LOG_FILE"


# Process files recursively all mkv, avi, mp4 files
# - select all mkv, avi, mp4,ogm, wmv files
# - skip all AV1.mp4 files  
while IFS= read -r file; do

    # Check for manual stop trigger
    if [[ -f "./stop.y" ]]; then
        echo "$(timestamp) STOP TRIGGER DETECTED (stop.y). Ending batch early..." >> "$LOG_FILE"
        mv -f "./stop.y" "./stop.n"
        break
    fi

    ((count_loop++))
    filename=$(basename "$file")
    outname="${filename%.*}$PRESET.mp4"
    outfile="${file%.*}$PRESET.mp4"

    #Skip logic
    if [[ -f "$outfile" ]]; then
        echo "$(timestamp) Skipping: $filename (Taget Exists)" >> "$LOG_FILE"
        ((count_skipped++))
        continue
    fi

    if [[ "$filename"  == *"AV1.mp4" ]]; then
        echo "$(timestamp) Skipping: $filename (Already Processed)" >> "$LOG_FILE"
        ((count_skipped++))
        continue
    fi

    echo "$(timestamp) Processing Loop $count_loop: $filename" >> "$LOG_FILE"
    echo "$(timestamp) file:     $file" >> "$LOG_FILE"
    echo "$(timestamp) outfile:  $outfile" >> "$LOG_FILE"
    echo "$(timestamp) filename: $filename" >> "$LOG_FILE"
    echo "$(timestamp) outname:  $outname" >> "$LOG_FILE"

    # Run HandBrakeCLI
    echo "$(timestamp) Processing: $file" >> "$LOG_FILE"
    HandBrakeCLI -i "$file" -o "$outfile" --preset-import-file "$PRESET_FILE"  -Z "$PRESET" < /dev/null

    #Check Exit Status
    # $? captures the exit code of the last command (0 = success)
    if [[ $? -eq 0 ]]; then
        # Get sizes in bytes
        # 'stat -c%s' works on Linux
        old_size=$(stat -c%s "$file")
        new_size=$(stat -c%s "$outfile")
        echo "$(timestamp) Input file size  -> $old_size" >> "$LOG_FILE"
        echo "$(timestamp) Output file size -> $new_size" >> "$LOG_FILE"

        if ((new_size < old_size)); then
            echo "$(timestamp) SUCCESS: $filename" >> "$LOG_FILE"
            if ((new_size > old_size/4)); then
                echo "$(timestamp) SUCCESS: Deleting source." >> "$LOG_FILE"
                rm "$file"
            else
                echo "$(timestamp) WARNING: New file is smaller than 25% of original." >> "$LOG_FILE"
                echo "$(timestamp) WARNING: Moving original to root folder" >> "$LOG_FILE"
                mv "$file" "./$filename"
            fi
            ((count_success++))
        else
            echo "$(timestamp) WARNING: New file is LARGER ($new_size vs $old_size)." >> "$LOG_FILE"
            echo "$(timestamp) WARNING: Moving new file to root folder" >> "$LOG_FILE"
            mv "$outfile" "./$outname"
            ((count_success++))
        fi
    else
        echo "$(timestamp) ERROR: Encoding failed for $filename. Keeping source file." >> "$LOG_FILE"
        ((count_failed++))
    fi
    echo "$(timestamp) ***************************************************************" >> "$LOG_FILE"

done < <(find "$INPUT_DIR" -type f \( -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp4" -o -iname "*.ogm" -o -iname "*.wmv" \) -print0 | sort -rz)

echo "$(timestamp) Batch processing complete." >> "$LOG_FILE"
echo "$(timestamp)***************************************************************" >> "$LOG_FILE"
echo "$(timestamp) BATCH COMPLETE" >> "$LOG_FILE"
echo "$(timestamp) Success: $count_success" >> "$LOG_FILE"
echo "$(timestamp) Skipped: $count_skipped" >> "$LOG_FILE"
echo "$(timestamp) Failed:  $count_failed" >> "$LOG_FILE"
echo "**************************************************************************************" >> "$LOG_FILE"
