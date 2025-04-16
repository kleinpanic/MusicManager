#!/usr/bin/env bash
# Music Manager – advanced media management
# Version 2.6  (2025‑04‑15)

set -euo pipefail
VERSION="2.0"

###############################################################################
# Usage
###############################################################################
usage() {
cat <<EOF
Usage: mm [OPERATION] [OPTIONS] <path>

Operations:
  --compress <directory>
         Recursively compress supported media files (MP3, WAV, AAC, FLAC, OGG, OPUS, MP4, mov)
         [--package]                Package all compressed files into a single container.
         
  --uncompress <path>
         Recursively uncompress archives or, if given a package file, unpack it.
         
  --convert <file|directory>
         Convert media files to a target codec.
           [--to <codec>]           Target codec (default: opus)
           [--keep]                 Keep original files by converting into a separate directory.
           [--replace]              Replace the originals with converted files.
           [--quiet]                Suppress debug output.
           [--metadata <mode>]      Metadata handling: 'keep' (default), 'drop', or 'drop:tag,tag...'
         (Note: the --from flag has been removed.)
         
  --scan <file|directory>
         Recursively scan media files for anomalies. For each file, ffprobe is used to extract:
            - Container format
            - Codec name
            - Sample rate
            - Bitrate and Duration
            - Actual filesize versus an expected threshold
         Files are classified as "normal" (green), "weird" (yellow) or "corrupted" (red). 
         Results are displayed and logged.
         
  --metadata-manage <path>
         Manage metadata for media files.
           [--add "key=value,key2=value2,..."]    Add or update metadata tags.
           [--remove "tag,tag,..."]                 Remove specified metadata tags.

Other Options:
  --install         Install the program (copy script, manpage, and bash completion)
  --uninstall       Uninstall the program
  --help            Show this help text
  --version         Show version
EOF
}

###############################################################################
# Dependency check
###############################################################################
check_dependencies() {
    local deps=(7z ffmpeg ffprobe find realpath mktemp metaflac)
    for d in "${deps[@]}"; do
        command -v "$d" >/dev/null 2>&1 || {
            echo "Error: '$d' is required but not installed." >&2
            exit 1
        }
    done
}

###############################################################################
# Determine compression settings based on file extension.
###############################################################################
get_compression_settings() {
    local ext="$1"
    local settings="-mx=9"  # default: high compression
    case "$ext" in
        flac)   settings="-mx=9" ;;
        mp3)    settings="-mx=5" ;;
        wav)    settings="-mx=9" ;;
        aac)    settings="-mx=6" ;;
        ogg|opus) settings="-mx=7" ;;
        mp4|mov)  settings="-mx=4" ;;
        *)      settings="-mx=9" ;;
    esac
    echo "$settings"
}

###############################################################################
# --compress: Recursively compress supported media files.
###############################################################################
compress_media() {
    local input_dir
    input_dir=$(realpath "$1")
    local target_dir="$input_dir/compressed"
    mkdir -p "$target_dir"
    echo "Compressing media files in '$input_dir' …"
    
    find "$input_dir" \( -iname "compressed" -o -iname "uncompressed" \) -prune -o \
         -type f \( -iname "*.flac" -o -iname "*.mp3" -o -iname "*.wav" -o \
                    -iname "*.aac" -o -iname "*.ogg" -o -iname "*.opus" -o \
                    -iname "*.mp4" -o -iname "*.mov" \) -print0 |
    while IFS= read -r -d '' file; do
        local rel ext out_file out_dir compression_settings tmp
        rel=$(realpath --relative-to="$input_dir" -- "$file")
        ext="${file##*.}"
        ext="${ext,,}"
        compression_settings=$(get_compression_settings "$ext")
        out_file="$target_dir/${rel%.*}.7z"
        out_dir=$(dirname "$out_file")
        mkdir -p "$out_dir"
        printf ' • %s  →  %s\n' "$rel" "${out_file#$input_dir/}"
        
        tmp=$(mktemp -t mmXXXXXX."$ext")
        cp "$file" "$tmp"
        if [[ "$ext" == "flac" ]]; then
            metaflac --remove --block-type=PICTURE "$tmp" 2>/dev/null || true
        fi
        7z a $compression_settings -mmt=on "$out_file" "$tmp" >/dev/null
        rm -f "$tmp"
    done
    echo "Done. Compressed files are in '$target_dir'."
}

###############################################################################
# Package compressed files into one container archive.
###############################################################################
package_compressed() {
    local input_dir
    input_dir=$(realpath "$1")
    local target_dir="$input_dir/compressed"
    local package_file="$target_dir/package.7z"
    echo "Packaging compressed files in '$target_dir' into '$package_file' …"
    (cd "$target_dir" && 7z a -mx=9 "package.7z" $(find . -type f -name "*.7z" ! -name "package.7z"))
    echo "Done. Package created at '$package_file'."
}

###############################################################################
# --uncompress: Uncompress archives or unpack a package file.
###############################################################################
uncompress_media() {
    local input_path
    input_path=$(realpath "$1")
    if [ -f "$input_path" ]; then
        echo "Unpacking package file '$input_path' …"
        local pkg_temp
        pkg_temp=$(mktemp -d -t mm_unpkg_XXXX)
        7z x "$input_path" -o"$pkg_temp" >/dev/null
        echo "Extracted package to temporary directory '$pkg_temp'."
        uncompress_archives "$pkg_temp"
        rm -rf "$pkg_temp"
    elif [ -d "$input_path" ]; then
        uncompress_archives "$input_path"
    else
        echo "Error: '$input_path' is not a valid file or directory." >&2
        exit 1
    fi
}

uncompress_archives() {
    local dir="$1"
    local parent target_dir
    parent=$(dirname "$dir")
    target_dir="$parent/uncompressed"
    mkdir -p "$target_dir"
    echo "Uncompressing archives in '$dir' …"
    find "$dir" -type f -iname '*.7z' -print0 |
    while IFS= read -r -d '' archive; do
        local rel rel_dir out_dir
        rel=$(realpath --relative-to="$dir" -- "$archive")
        rel_dir=$(dirname "${rel%.7z}")
        out_dir="$target_dir/$rel_dir"
        mkdir -p "$out_dir"
        printf ' • %s  →  %s/\n' "$rel" "${out_dir#$parent/}"
        7z x "$archive" -o"$out_dir" >/dev/null
    done
    echo "Done. Files restored to '$target_dir'."
}

###############################################################################
# --convert: Convert media files (file or directory) with detailed debug.
# Excludes any files in paths with /converted_* or /converted/.
###############################################################################
convert_media() {
    local input_path
    input_path=$(realpath "$1")
    local target_codec="${TARGET_CODEC:-opus}"
    local metadata_mode="${METADATA_MODE:-keep}"
    local keep_original="${KEEP_ORIGINAL:-true}"   # true: keep originals; false: in-place replacement
    local debug="${DEBUG:-true}"
    
    if [ -d "$input_path" ]; then
        local base_dir="$input_path"
        if [ "$keep_original" = "true" ]; then
            target_dir="$base_dir/converted_${target_codec,,}"
        else
            target_dir="$base_dir"
        fi
        mkdir -p "$target_dir"
        if [ "$debug" = "true" ]; then
            echo "[DEBUG] Conversion Options:"
            echo "  Target codec: ${target_codec}"
            echo "  Metadata mode: ${metadata_mode}"
            echo "  Keep original files: ${keep_original}"
            echo "  Base directory: $base_dir"
            echo "  Target directory: $target_dir"
        fi
        echo "Converting audio in directory '$base_dir' → *.$(echo "$target_codec" | tr '[:upper:]' '[:lower:]') …"
        # Look for eligible files (excluding any in converted directories)
        mapfile -d '' files < <(find "$base_dir" -type f \( -iname "*.mp3" -o -iname "*.aac" -o -iname "*.ogg" \
                        -o -iname "*.opus" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.m4a" \
                        -o -iname "*.mp4" -o -iname "*.mov" \) ! -path "*/converted_*/*" ! -path "*/converted/*" -print0)
        if [ "${#files[@]}" -eq 0 ]; then
            echo "[DEBUG] No files found for conversion in '$base_dir'."
        else
            echo "[DEBUG] Found ${#files[@]} files for conversion in '$base_dir':"
            if [ "$debug" = "true" ]; then
                for file in "${files[@]}"; do
                    echo "  [DEBUG] File: $file"
                done
            fi
        fi
        for file in "${files[@]}"; do
            process_conversion "$file" "$base_dir" "$target_dir" "$target_codec" "$metadata_mode" "$keep_original" "$debug"
        done
    elif [ -f "$input_path" ]; then
        echo "Converting single file '$input_path' → *.$(echo "$target_codec" | tr '[:upper:]' '[:lower:]') …"
        base_dir=$(dirname "$input_path")
        if [ "$keep_original" = "true" ]; then
            target_dir="$base_dir/converted_${target_codec,,}"
            mkdir -p "$target_dir"
        else
            target_dir="$base_dir"
        fi
        process_conversion "$input_path" "$base_dir" "$target_dir" "$target_codec" "$metadata_mode" "$keep_original" "$debug"
    else
        echo "Error: '$input_path' is not a valid file or directory." >&2
        exit 1
    fi
    echo "Conversion completed. Output in '$target_dir'."
}

###############################################################################
# Helper: Process conversion of an individual file with robust validation.
###############################################################################
process_conversion() {
    local file="$1" base_dir="$2" target_dir="$3"
    local target_codec="$4" metadata_mode="$5"
    local keep_original="$6" debug="$7"
    local rel out_file ext

    rel=$(realpath --relative-to="$base_dir" -- "$file")
    ext="${file##*.}"
    ext="${ext,,}"

    [ "$debug" = "true" ] && echo "[DEBUG] Processing file '$file' (relative: '$rel')"

    # Validate file using ffprobe.
    if ! info=$(ffprobe -v error -show_format -show_streams -of default=noprint_wrappers=1 "file://$file" 2>&1); then
        echo "[ERROR] Validation failed: '$file' is not recognized as a valid media file. Skipping." >&2
        return 1
    fi

    # Warn if file is already in target format.
    if [ "$ext" = "${target_codec,,}" ]; then
        echo "Warning: File '$rel' is already in ${target_codec^^} format. Skip or continue? (s to skip, c to continue)"
        read -r answer
        if [[ "$answer" =~ ^[Ss] ]]; then
            echo "Skipping '$rel'."
            return 0
        fi
    fi

    if [ "$keep_original" = "true" ]; then
        out_file="$target_dir/${rel%.*}.${target_codec,,}"
    else
        out_file="$file.tmp_conv.${target_codec,,}"
    fi
    mkdir -p "$(dirname "$out_file")"
    [ "$debug" = "true" ] && echo "[DEBUG] Converting '$file' → '$out_file'"

    # Metadata handling.
    local meta_args=()
    case "$metadata_mode" in
        keep)   meta_args=(-map_metadata 0) ;;
        drop)   meta_args=(-map_metadata -1) ;;
        drop:*) meta_args=(-map_metadata 0)
                IFS=',' read -ra tags <<< "${metadata_mode#drop:}"
                for t in "${tags[@]}"; do meta_args+=(-metadata "$t="); done
                ;;
        *)      echo "Invalid --metadata value '$metadata_mode'" >&2; return 1 ;;
    esac

    # Codec parameters.
    local codec_args=()
    case "$target_codec" in
        opus)        codec_args=(-c:a libopus    -b:a 192k) ;;
        flac)        codec_args=(-c:a flac       -compression_level 12) ;;
        mp3)         codec_args=(-c:a libmp3lame -qscale:a 0) ;;
        wav)         codec_args=(-c:a pcm_s16le) ;;
        ogg)         codec_args=(-c:a libvorbis  -qscale:a 5) ;;
        aac)         codec_args=(-c:a aac        -b:a 192k) ;;
        m4a|mp4)     codec_args=(-c:a aac        -b:a 192k) ;;
        *)           echo "Unsupported target codec '$target_codec'" >&2; return 1 ;;
    esac

    if [ "$debug" = "true" ]; then
        echo "[DEBUG] ffmpeg command: ffmpeg -hide_banner -loglevel error -i \"file://$file\" ${meta_args[*]} ${codec_args[*]} -y \"$out_file\""
    fi

    if ! ffmpeg -hide_banner -loglevel error -i "file://$file" \
           "${meta_args[@]}" "${codec_args[@]}" -y "$out_file"; then
        echo "[ERROR] Conversion failed for '$file'. Skipping." >&2
        return 1
    fi

    if [ "$keep_original" != "true" ]; then
        if [ -f "$out_file" ]; then
            mv "$out_file" "$file"
        else
            echo "[ERROR] Post-conversion file not found for '$file'. Skipping move operation." >&2
            return 1
        fi
    fi
    [ "$debug" = "true" ] && echo "[DEBUG] Finished converting '$file'."
}

###############################################################################
# --convert branch: Process conversion arguments in any order.
###############################################################################
convert_branch() {
    TARGET_CODEC="opus"
    METADATA_MODE="keep"
    KEEP_ORIGINAL="true"
    DEBUG="true"
    pos_arg=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --to)
                if [ "$#" -lt 2 ]; then
                    echo "Error: --to requires a codec argument." >&2
                    usage
                    exit 1
                fi
                TARGET_CODEC="${2,,}"
                shift 2
                ;;
            --metadata)
                if [ "$#" -lt 2 ]; then
                    echo "Error: --metadata requires a mode argument." >&2
                    usage
                    exit 1
                fi
                METADATA_MODE="${2,,}"
                shift 2
                ;;
            --keep)
                KEEP_ORIGINAL="true"
                shift
                ;;
            --replace)
                KEEP_ORIGINAL="false"
                shift
                ;;
            --quiet)
                DEBUG="false"
                shift
                ;;
            --*)
                echo "Unknown --convert option '$1'" >&2
                usage
                exit 1
                ;;
            *)
                if [ -z "$pos_arg" ]; then
                    pos_arg="$1"
                else
                    echo "Error: Multiple file/directory arguments provided to --convert." >&2
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$pos_arg" ]; then
        echo "Error: --convert requires a file or directory argument." >&2
        usage
        exit 1
    fi

    convert_media "$pos_arg"
}

###############################################################################
# --scan: Recursively scan media files and provide detailed analysis.
# For each file, ffprobe is run to extract: container, codec, sample rate,
# bitrate, duration and filesize. An expected filesize is computed and compared
# to the actual filesize. The result is classified and color coded:
#    Normal (green), Weird (yellow/orange), or Corrupted (red).
###############################################################################
scan_media() {
    local input_path
    input_path=$(realpath "$1")
    local report_file="scan_report_$(date +%Y%m%d%H%M%S).txt"
    echo "Scanning media files in '$input_path' …"
    echo "Scan Report - $(date)" > "$report_file"

    # Set up ANSI color codes (if STDOUT is a terminal)
    if [ -t 1 ]; then
        COLOR_GREEN="\033[0;32m"
        COLOR_YELLOW="\033[0;33m"
        COLOR_RED="\033[0;31m"
        COLOR_RESET="\033[0m"
    else
        COLOR_GREEN=""
        COLOR_YELLOW=""
        COLOR_RED=""
        COLOR_RESET=""
    fi

    scan_file() {
        local file="$1"
        echo "Scanning '$file'" >> "$report_file"
        # Run ffprobe to extract detailed metadata.
        if ! info=$(ffprobe -v error -show_format -show_streams -of default=noprint_wrappers=1 "file://$file" 2>&1); then
            echo -e "${COLOR_RED}File '$file' is corrupted or unreadable.${COLOR_RESET}"
            echo "File '$file' is corrupted or unreadable." >> "$report_file"
            return 1
        fi
        echo "$info" >> "$report_file"
        local container codec sample_rate bitrate duration filesize expected_val threshold cmp_result details

        container=$(echo "$info" | grep "^format_name=" | cut -d'=' -f2)
        codec=$(echo "$info" | grep "^codec_name=" | head -n 1 | cut -d'=' -f2)
        sample_rate=$(echo "$info" | grep "^sample_rate=" | head -n 1 | cut -d'=' -f2)
        bitrate=$(echo "$info" | grep "^bit_rate=" | head -n 1 | cut -d'=' -f2)
        duration=$(echo "$info" | grep "^duration=" | head -n 1 | cut -d'=' -f2)
        filesize=$(stat -c%s "$file")
        expected_val=$(echo "scale=2; ($duration * $bitrate) / 8" | bc -l)
        threshold=$(echo "scale=2; $expected_val * 1.5" | bc -l)
        cmp_result=$(echo "$filesize > $threshold" | bc -l)
        details="Container: $container, Codec: $codec, Sample Rate: ${sample_rate}Hz, Bitrate: ${bitrate}bps, Duration: ${duration}s, Filesize: ${filesize} bytes, Expected Threshold: ${threshold} bytes."
        
        if [ "$cmp_result" -eq 1 ]; then
            echo -e "${COLOR_YELLOW}File '$file' appears weird. $details${COLOR_RESET}"
            echo "File '$file' appears weird. $details" >> "$report_file"
        else
            echo -e "${COLOR_GREEN}File '$file' appears normal. $details${COLOR_RESET}"
            echo "File '$file' appears normal. $details" >> "$report_file"
        fi
    }

    if [ -d "$input_path" ]; then
        while IFS= read -r -d '' file; do
            scan_file "$file"
        done < <(find "$input_path" -type f \( -iname "*.mp3" -o -iname "*.aac" -o -iname "*.ogg" -o \
                        -iname "*.opus" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.m4a" -o \
                        -iname "*.mp4" -o -iname "*.mov" \) -print0)
    elif [ -f "$input_path" ]; then
        scan_file "$input_path"
    else
        echo "Error: '$input_path' is not a valid file or directory." >&2
        exit 1
    fi
    echo "Interactive scan completed. Detailed report saved to '$report_file'."
}

###############################################################################
# --metadata-manage: Add or remove metadata for media files.
###############################################################################
metadata_manage() {
    local input_path
    input_path=$(realpath "$1")
    shift
    local add_tags="" remove_tags=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --add)
                add_tags="$2"
                shift 2
                ;;
            --remove)
                remove_tags="$2"
                shift 2
                ;;
            *)
                echo "Unknown metadata management option '$1'"
                usage
                exit 1
                ;;
        esac
    done
    echo "Managing metadata for '$input_path' …"
    
    process_metadata() {
        local file="$1"
        local ext="${file##*.}"
        ext="${ext,,}"
        if [[ "$ext" == "flac" ]]; then
            if [ -n "$remove_tags" ]; then
                IFS=',' read -ra tags <<< "$remove_tags"
                for t in "${tags[@]}"; do
                    metaflac --remove-tag="$t" "$file"
                done
            fi
            if [ -n "$add_tags" ]; then
                IFS=',' read -ra pairs <<< "$add_tags"
                for pair in "${pairs[@]}"; do
                    key=${pair%%=*}
                    value=${pair#*=}
                    metaflac --set-tag="$key=$value" "$file"
                done
            fi
        else
            local tmp
            tmp=$(mktemp -t mmmetaXXXXXX."$ext")
            ffmpeg -hide_banner -loglevel error -i "file://$file" \
                   $( [ -n "$remove_tags" ] && { IFS=','; for t in $remove_tags; do echo -n "-metadata $t="; done; } ) \
                   $( [ -n "$add_tags" ] && { IFS=','; for pair in $add_tags; do echo -n "-metadata ${pair} "; done; } ) \
                   -c copy -y "$tmp"
            mv "$tmp" "$file"
        fi
        echo "Processed metadata for '$file'."
    }
    
    if [ -d "$input_path" ]; then
        find "$input_path" -type f \( -iname "*.mp3" -o -iname "*.aac" -o -iname "*.ogg" -o \
                    -iname "*.opus" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.m4a" -o \
                    -iname "*.mp4" -o -iname "*.mov" \) -print0 |
        while IFS= read -r -d '' file; do
            process_metadata "$file"
        done
    elif [ -f "$input_path" ]; then
        process_metadata "$input_path"
    else
        echo "Error: '$input_path' is not a valid file or directory." >&2
        exit 1
    fi
    echo "Metadata management completed."
}

###############################################################################
# Install / uninstall helpers
###############################################################################
install_program() {
    local BIN MAN COMP
    if (( EUID == 0 )); then
        BIN="/usr/local/bin"; MAN="/usr/local/share/man/man1"; COMP="/etc/bash_completion.d"
    else
        BIN="$HOME/.local/bin"; MAN="$HOME/.local/share/man/man1"; COMP="$HOME/.local/etc/bash_completion.d"
    fi
    mkdir -p "$BIN" "$MAN" "$COMP"
    cp "$(realpath "$0")" "$BIN/mm" && chmod +x "$BIN/mm"
    [[ -f ./mm.1 ]]               && cp ./mm.1               "$MAN/"
    [[ -f ./mm.bash_completion ]] && cp ./mm.bash_completion "$COMP/"
    echo "Installed to $BIN (man → $MAN, completion → $COMP)"
}

uninstall_program() {
    local BIN MAN COMP
    if (( EUID == 0 )); then
        BIN="/usr/local/bin"; MAN="/usr/local/share/man/man1"; COMP="/etc/bash_completion.d"
    else
        BIN="$HOME/.local/bin"; MAN="$HOME/.local/share/man/man1"; COMP="$HOME/.local/etc/bash_completion.d"
    fi
    rm -f "$BIN/mm" "$MAN/mm.1" "$COMP/mm.bash_completion"
    echo "Removed mm from $BIN"
}

###############################################################################
# Main argument parser
###############################################################################
if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

check_dependencies

case "$1" in
    --help)
        usage
        exit 0
        ;;
    --version)
        echo "mm $VERSION"
        exit 0
        ;;
    --install)
        install_program
        exit 0
        ;;
    --uninstall)
        uninstall_program
        exit 0
        ;;
    --compress)
        shift
        package_flag="false"
        if [ "$#" -ge 2 ] && [ "$1" = "--package" ]; then
            package_flag="true"
            shift
        fi
        if [ "$#" -ne 1 ]; then
            echo "Error: --compress requires exactly one directory argument." >&2
            usage
            exit 1
        fi
        compress_media "$1"
        if [ "$package_flag" = "true" ]; then
            package_compressed "$1"
        fi
        exit 0
        ;;
    --uncompress)
        if [ "$#" -ne 2 ]; then
            echo "Error: --uncompress requires a file or directory argument." >&2
            usage
            exit 1
        fi
        uncompress_media "$2"
        exit 0
        ;;
    --convert)
        shift
        convert_branch "$@"
        exit 0
        ;;
    --scan)
        if [ "$#" -ne 2 ]; then
            echo "Error: --scan requires a file or directory argument." >&2
            usage
            exit 1
        fi
        scan_media "$2"
        exit 0
        ;;
    --metadata-manage)
        if [ "$#" -lt 2 ]; then
            echo "Error: --metadata-manage requires a file or directory argument." >&2
            usage
            exit 1
        fi
        metadata_manage "$2" "${@:3}"
        exit 0
        ;;
    *)
        echo "Unknown option '$1'" >&2
        usage
        exit 1
        ;;
esac

