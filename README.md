# Music Manager (mm)

Music Manager (mm) is a Bash script for advanced media management with minimal dependencies. It is designed to help you efficiently manage your music and other media files by supporting tasks such as compressing, uncompressing, converting, scanning for anomalies, and managing metadata—all while preserving your directory structure.

## Features

- **--compress \<directory\>**  
  Recursively compresses all supported media files (MP3, WAV, AAC, FLAC, OGG, OPUS, MP4, mov) in the specified directory.  
  - Converted files are stored in a `compressed` folder, preserving the original directory hierarchy.
  - **--package**: An optional flag to collect all compressed files into a single container archive.

- **--uncompress \<path\>**  
  Recursively uncompresses all `.7z` archives (or unpacks a package file) into an `uncompressed` folder, preserving the directory structure.

- **--convert \<file|directory\>**  
  Converts media files to a target codec (default: opus) and offers detailed debug output along with robust error handling.
  - **Options:**
    - **--to \<codec\>**: Specify the target codec.
    - **--keep**: Store converted files in a new folder (e.g., `converted_opus`) while preserving the original nested structure.
    - **--replace**: Replace original files with converted files (if no data loss risk exists).
    - **--quiet**: Suppress detailed debug output.
    - **--metadata \<mode\>**: Control metadata handling during conversion:
      - `keep` (default): Copy all tags.
      - `drop`: Remove all metadata.
      - `drop:tag,tag...`: Remove only specified tags.
  - (Note: The older `--from` flag has been removed.)

- **--scan \<file|directory\>**  
  Recursively scans all supported media files and provides a detailed analysis using ffprobe. For each file, the script:
  - Extracts metadata including container format, codec, sample rate, bitrate, and duration.
  - Computes an expected filesize based on the duration and bitrate and compares it to the actual filesize.
  - Classifies files as:
    - **Normal** (displayed in green)
    - **Weird** (if the filesize exceeds a 1.5× heuristic threshold, displayed in yellow/orange)
    - **Corrupted** (if ffprobe fails, displayed in red)
  - Displays results on screen (with ANSI colors if supported) and logs them to a timestamped report file (e.g., `scan_report_YYYYMMDDHHMMSS.txt`).

- **--metadata-manage \<path\>**  
  Provides functionality to add or remove metadata tags from media files.
  - **Options:**
    - **--add "key=value,key2=value2,..."**: Add or update specific metadata tags.
    - **--remove "tag,tag,..."**: Remove specified metadata tags.

- **--install / --uninstall**  
  Installs or uninstalls the script, its manpage, and its bash completion file. When not run as root, installation will default to local directories (e.g., `~/.local/bin`).

- **--help / --version**  
  Displays the help message or version information.

## Requirements

- Bash
- 7z (p7zip)
- ffmpeg (includes ffprobe)
- find
- realpath
- mktemp
- metaflac

## Installation

To install Music Manager, run:

```bash
./mm.sh --install
```

This command copies the script to your local bin directory, installs the manpage (`mm.1`), and sets up bash completions (`mm.bash_completion`). (If you are not running as root, the files will be installed in your local directories such as `~/.local/bin`.)

## Uninstallation

To uninstall Music Manager, run:

```bash
./mm.sh --uninstall
```

This removes the installed script, manpage, and bash completion file.

## Usage Examples

### Compress Files

Recursively compress media files in the directory `~/Music`:

```bash
./mm.sh --compress ~/Music
```

Package the compressed files into a single archive:

```bash
./mm.sh --compress --package ~/Music
```

### Uncompress Files

Extract archives from a directory:

```bash
./mm.sh --uncompress ~/Music
```

### Convert Files

Convert all media files under `~/Music` to opus while keeping the originals (converted files are placed in `converted_opus`):

```bash
./mm.sh --convert ~/Music --to opus --keep
```

Replace original files with the converted ones:

```bash
./mm.sh --convert ~/Music --to opus --replace
```

### Scan Files

Recursively scan your media files for anomalies:

```bash
./mm.sh --scan ~/Music
```

This will display a color-coded analysis (green for normal, yellow for weird, red for corrupted) and log the detailed report in a file named with a timestamp (e.g., `scan_report_20250415123456.txt`).

### Manage Metadata

Remove specific metadata tags:

```bash
./mm.sh --metadata-manage ~/Music --remove tag1,tag2
```

Add or update metadata tags:

```bash
./mm.sh --metadata-manage ~/Music --add "artist=Unknown,title=Untitled"
```

### Display Help or Version

Show the help message:

```bash
./mm.sh --help
```

Show version information:

```bash
./mm.sh --version
```

## Command-line Completion

When installed, Music Manager provides bash completions for all commands and options. Ensure your shell sources the completion script (this is typically set up automatically during installation).

## Troubleshooting

- Verify that all dependencies are installed.
- Use the `--quiet` flag during conversion to reduce debug output.
- Consult the generated scan report for detailed information on file anomalies.
- Ensure your media files are not corrupted and are in supported formats.

