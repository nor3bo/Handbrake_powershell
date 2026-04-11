#!/bin/bash

#run:  nohup ./convert.sh /my/videos preset &
# Capture the first argument as the input directory
INPUT_DIR="$1"
PRESET="$2"
SKIP="$3"
OPTIONS="$4"
PRESET_FILE="./presets.json"
LOG_FILE="converter.log"
ERROR_LOG="error.log"
SKIPPED_FILE="skipped.log"

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
    echo "Usage: $0 /path/to/input_directory preset extra_options" 
    exit 1
fi

case "$PRESET" in
    "_full_1080p_AV1"|"_1080p_AV1"|"_38_1080p_AV1"|"_720p_AV1"|"_42_720p_AV1")
        echo "preset valid: $PRESET"
        ;;
    *)   
        echo "Error: Preset required (e.g. _full_1080p_AV1,_1080p_AV1, _38_1080p_AV1, _720p_AV1, _42_720p_AV1)"
        exit 1
        ;;
esac

if [[ -z "$OPTIONS" ]]; then
    OPTIONS="n"
fi

case "$OPTIONS" in
    "n")
        OPTIONS=""
        ;;
    2)
        OPTIONS="lp=2"
        ;;
    3)
        OPTIONS="lp=3"
        ;;
    4)
        OPTIONS="lp=4"
        ;;
    *)
        echo "Input '$options' invalid or null. Defaulting to 4 logical processors."
        OPTIONS="lp=4"
        ;;
esac


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
echo "$(timestamp) ***************************************************************" >> "$LOG_FILE"
echo "$(timestamp) ***************************************************************" >> "$LOG_FILE"
echo "$(timestamp) Starting New Video File Conversion Run" >> "$LOG_FILE"
echo "$(timestamp) Process Directory: $INPUT_DIR" >> "$LOG_FILE"
echo "$(timestamp) Preset: $PRESET" >> "$LOG_FILE"
echo "$(timestamp) Options: $OPTIONS" >> "$LOG_FILE"
echo "$(timestamp) Skip AV1:$SKIP" >> "$LOG_FILE"
echo "$(timestamp) Use STOP TRIGGER to end run: \"stop.y\" " >> "$LOG_FILE"
echo "$(timestamp) ***************************************************************" >> "$LOG_FILE"


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
    last_seven="${filename: -7}"

    #Skip logic
    if [[ -f "$outfile" ]]; then
        echo "$(timestamp) Skipping: $filename (Target Exists)" >> "$SKIPPED_FILE"
        ((count_skipped++))
        continue
    fi

    if [[ "$filename"  == *"AV1.mp4" ]]; then
        echo "$(timestamp) Skipping: $filename (Already Processed)" >> "$SKIPPED_FILE"
        ((count_skipped++))
        continue
    fi
    
    if [[ "$last_seven" == "AV1.mp4" && "$SKIP" == "y" ]]; then
        echo "$(timestamp) Skipping: $filename (Already Processed and SKIP)" >> "$SKIPPED_FILE"
        ((count_skipped++))
        continue
    fi
    > nohup.out
    echo "$(timestamp) ***************************************************************" >> "$LOG_FILE"
    echo "$(timestamp) Processing Loop $count_loop: $filename" >> "$LOG_FILE"
    echo "$(timestamp) ***************************************************************" >> "$LOG_FILE"
    echo "$(timestamp) file:     $file" >> "$LOG_FILE"
    echo "$(timestamp) outfile:  $outfile" >> "$LOG_FILE"

    # Run HandBrakeCLI
    HandBrakeCLI -i "$file" -o "$outfile" --preset-import-file "$PRESET_FILE"  -Z "$PRESET" -x "$OPTIONS" < /dev/null

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
            if ((new_size > old_size/4)); then
                echo "$(timestamp) SUCCESS: Deleting source." >> "$LOG_FILE"
                rm "$file"
            else
                echo "$(timestamp) WARNING: New file is smaller than 25% of original." >> "$LOG_FILE"
                echo "$(timestamp) WARNING: Moving original to root folder" >> "$LOG_FILE"
                echo "$(timestamp) *****************************************************" >> "$ERROR_LOG"
                echo "$(timestamp) WARNING: file: $filename" >> "$ERROR_LOG"
                echo "$(timestamp) WARNING: New file is smaller than 25% of original." >> "$ERROR_LOG"
                echo "$(timestamp) WARNING: Moving original to root folder" >> "$ERROR_LOG"
                mv "$file" "./$filename"
            fi
            ((count_success++))
        else
            echo "$(timestamp) WARNING: New file is LARGER ($new_size vs $old_size)." >> "$LOG_FILE"
            echo "$(timestamp) WARNING: Moving new file to root folder" >> "$LOG_FILE"
                echo "$(timestamp) *****************************************************" >> "$ERROR_LOG"
                echo "$(timestamp) WARNING: file: $filename" >> "$ERROR_LOG"
            echo "$(timestamp) WARNING: New file is LARGER ($new_size vs $old_size)." >> "$ERROR_LOG"
            echo "$(timestamp) WARNING: Moving new file to root folder" >> "$ERROR_LOG"
            mv "$outfile" "./$outname"
            ((count_success++))
        fi
    else
        echo "$(timestamp) ERROR: Encoding failed for $filename. Keeping source file." >> "$LOG_FILE"
        echo "$(timestamp) ERROR: Encoding failed for $filename. Keeping source file." >> "$ERROR_LOG"
        ((count_failed++))
    fi

done < <(find "$INPUT_DIR" -type f \( -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mp4" -o -iname "*.ogm" -o -iname "*.wmv" \))

echo "$(timestamp) Batch processing complete." >> "$LOG_FILE"
echo "$(timestamp)***************************************************************" >> "$LOG_FILE"
echo "$(timestamp) BATCH COMPLETE" >> "$LOG_FILE"
echo "$(timestamp) Success: $count_success" >> "$LOG_FILE"
echo "$(timestamp) Skipped: $count_skipped" >> "$LOG_FILE"
echo "$(timestamp) Failed:  $count_failed" >> "$LOG_FILE"
echo "$(timestamp) ***************************************************************" >> "$LOG_FILE"
