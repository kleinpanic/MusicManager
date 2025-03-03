#!/bin/bash
set -euo pipefail

VERSION="1.0"

# Determine the directory where this script resides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Print usage/help message
usage() {
    cat <<EOF
Usage: mm [OPTION] <directory>
Options:
  --compress <directory>    Compress all FLAC files recursively.
                            - Searches for .flac files in <directory>,
                              excluding directories named "compressed" or "uncompressed"
                              and files named ".gitinoge". For each file, a temporary copy is
                              created with embedded picture metadata removed, then compressed using 7z
                              at maximum compression with multi-threading enabled.
                              The output is stored in <directory>/compressed preserving the original structure.
  --uncompress <directory>  Uncompress all .7z files recursively.
                            - Searches for .7z files in <directory> (assumed to be a "compressed" folder),
                              extracts them into a sibling folder named "uncompressed" (../uncompressed)
                              while preserving structure.
  --convert <directory>     Convert all non-FLAC music files recursively to FLAC.
                            - Searches for files with extensions mp3, aac, ogg, wav,
                              converts them to FLAC using ffmpeg with maximum compression,
                              and outputs them to <directory>/converted preserving structure.
  --install                 Install mm to your local bin along with its manpage and bash completion.
  --uninstall               Uninstall mm and remove its manpage and bash completion.
  --help                    Display this help and exit.
  --version                 Display version information and exit.
EOF
}

# Check dependencies
check_dependencies() {
    local deps=(7z ffmpeg find realpath mktemp metaflac)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "Error: '$dep' is required but not installed." >&2
            exit 1
        fi
    done
}

# Compress FLAC files (improved)
compress_flac() {
    local input_dir
    input_dir=$(realpath "$1")
    local target_dir="${input_dir}/compressed"

    echo "Compressing FLAC files in '$input_dir'..."
    # Exclude directories "compressed" and "uncompressed" and files named ".gitinoge"
    find "$input_dir" \( -iname "compressed" -o -iname "uncompressed" \) -prune -o \
         -type f -iname '*.flac' -not -iname '.gitinoge' -print | while IFS= read -r file; do
        # Create relative path (strip input_dir from the file path)
        relative="${file#$input_dir/}"
        # Determine output path with .7z extension
        out_file="${target_dir}/${relative%.flac}.7z"
        out_dir=$(dirname "$out_file")
        mkdir -p "$out_dir"
        echo "Processing '$file'"
        # Create a temporary copy of the file
        tmp_flac=$(mktemp --suffix=.flac)
        cp "$file" "$tmp_flac"
        # Remove embedded pictures (visual data) if present
        metaflac --remove-tag=METADATA_BLOCK_PICTURE "$tmp_flac" 2>/dev/null || true
        # Compress with 7z at maximum compression and multi-threading enabled
        echo "Compressing to '$out_file'"
        7z a -mx=9 -mmt=on "$out_file" "$tmp_flac" >/dev/null
        rm -f "$tmp_flac"
    done
    echo "Compression complete. Files are in '$target_dir'."
}

# Uncompress .7z archives
uncompress_files() {
    local input_dir
    input_dir=$(realpath "$1")
    # Assume input_dir is the 'compressed' folder.
    local parent_dir
    parent_dir=$(dirname "$input_dir")
    local target_dir="${parent_dir}/uncompressed"

    echo "Uncompressing archives in '$input_dir'..."
    find "$input_dir" -type f -iname '*.7z' | while IFS= read -r archive; do
        relative="${archive#$input_dir/}"
        # Remove the .7z extension for directory structure
        relative_dir=$(dirname "${relative%.7z}")
        out_dir="${target_dir}/${relative_dir}"
        mkdir -p "$out_dir"
        echo "Extracting '$archive' -> '$out_dir'"
        7z x "$archive" -o"$out_dir" >/dev/null
    done
    echo "Uncompression complete. Files are in '$target_dir'."
}

# Convert non-FLAC files to FLAC
convert_to_flac() {
    local input_dir
    input_dir=$(realpath "$1")
    local target_dir="${input_dir}/converted"

    echo "Converting non-FLAC music files in '$input_dir' to FLAC..."
    # Define extensions to convert (adjust or add more if needed)
    find "$input_dir" -type f \( -iname '*.mp3' -o -iname '*.aac' -o -iname '*.ogg' -o -iname '*.wav' \) | while IFS= read -r file; do
        relative="${file#$input_dir/}"
        # Remove existing extension and add .flac
        out_file="${target_dir}/${relative%.*}.flac"
        out_dir=$(dirname "$out_file")
        mkdir -p "$out_dir"
        echo "Converting '$file' -> '$out_file'"
        # Convert with ffmpeg using maximum FLAC compression (-compression_level 12)
        ffmpeg -loglevel error -i "$file" -compression_level 12 "$out_file"
    done
    echo "Conversion complete. Files are in '$target_dir'."
}

# Install mm, its manpage, and bash completion
install_program() {
    echo "Installing mm..."

    # Determine install directories based on privileges
    if [[ $EUID -eq 0 ]]; then
        BIN_DIR="/usr/local/bin"
        MAN_DIR="/usr/local/share/man/man1"
        BASH_COMPLETION_DIR="/etc/bash_completion.d"
    else
        BIN_DIR="${HOME}/.local/bin"
        MAN_DIR="${HOME}/.local/share/man/man1"
        BASH_COMPLETION_DIR="${HOME}/.local/etc/bash_completion.d"
    fi

    echo "Using bin directory: $BIN_DIR"
    echo "Using man directory: $MAN_DIR"
    echo "Using bash completion directory: $BASH_COMPLETION_DIR"

    # Create directories if they don't exist
    mkdir -p "$BIN_DIR" "$MAN_DIR" "$BASH_COMPLETION_DIR"

    # Copy the main script to the bin directory
    cp "$SCRIPT_DIR/mm.sh" "$BIN_DIR/mm"
    chmod +x "$BIN_DIR/mm"
    echo "Installed mm script to $BIN_DIR/mm"

    # Install the manpage
    if [[ -f "$SCRIPT_DIR/mm.1" ]]; then
        cp "$SCRIPT_DIR/mm.1" "$MAN_DIR/mm.1"
        echo "Installed manpage to $MAN_DIR/mm.1"
    else
        echo "Warning: mm.1 (manpage) not found in $SCRIPT_DIR"
    fi

    # Install the bash completion script (copied with its original name)
    if [[ -f "$SCRIPT_DIR/mm.bash_completion" ]]; then
        cp "$SCRIPT_DIR/mm.bash_completion" "$BASH_COMPLETION_DIR/mm.bash_completion"
        echo "Installed bash completion to $BASH_COMPLETION_DIR/mm.bash_completion"
    else
        echo "Warning: mm.bash_completion not found in $SCRIPT_DIR"
    fi

    echo "Installation complete."
    echo "Make sure $BIN_DIR is in your PATH and reload your shell to use the new bash completion."
}

# Uninstall mm, its manpage, and bash completion
uninstall_program() {
    echo "Uninstalling mm..."

    if [[ $EUID -eq 0 ]]; then
        BIN_DIR="/usr/local/bin"
        MAN_DIR="/usr/local/share/man/man1"
        BASH_COMPLETION_DIR="/etc/bash_completion.d"
    else
        BIN_DIR="${HOME}/.local/bin"
        MAN_DIR="${HOME}/.local/share/man/man1"
        BASH_COMPLETION_DIR="${HOME}/.local/etc/bash_completion.d"
    fi

    if [[ -f "$BIN_DIR/mm" ]]; then
        rm -f "$BIN_DIR/mm"
        echo "Removed $BIN_DIR/mm"
    else
        echo "mm script not found in $BIN_DIR"
    fi

    if [[ -f "$MAN_DIR/mm.1" ]]; then
        rm -f "$MAN_DIR/mm.1"
        echo "Removed $MAN_DIR/mm.1"
    else
        echo "Manpage not found in $MAN_DIR"
    fi

    if [[ -f "$BASH_COMPLETION_DIR/mm.bash_completion" ]]; then
        rm -f "$BASH_COMPLETION_DIR/mm.bash_completion"
        echo "Removed $BASH_COMPLETION_DIR/mm.bash_completion"
    else
        echo "Bash completion script not found in $BASH_COMPLETION_DIR"
    fi

    echo "Uninstallation complete."
}

# Main argument parsing
if [[ $# -lt 1 ]]; then
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
        echo "mm version $VERSION"
        exit 0
        ;;
    --compress)
        if [[ $# -ne 2 ]]; then
            echo "Error: --compress requires exactly one argument (directory)." >&2
            usage
            exit 1
        fi
        compress_flac "$2"
        ;;
    --uncompress)
        if [[ $# -ne 2 ]]; then
            echo "Error: --uncompress requires exactly one argument (directory)." >&2
            usage
            exit 1
        fi
        uncompress_files "$2"
        ;;
    --convert)
        if [[ $# -ne 2 ]]; then
            echo "Error: --convert requires exactly one argument (directory)." >&2
            usage
            exit 1
        fi
        convert_to_flac "$2"
        ;;
    --install)
        install_program
        ;;
    --uninstall)
        uninstall_program
        ;;
    *)
        echo "Error: Unknown option '$1'" >&2
        usage
        exit 1
        ;;
esac

