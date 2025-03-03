# Music Manager (mm)

This is a Bash script that manages your music files. It supports:

- **--compress \<directory\>**: Recursively compresses all FLAC files found in the specified directory using 7z, preserving the original directory structure. Compressed files are stored in a `compressed` folder.
- **--uncompress \<directory\>**: Recursively uncompresses all `.7z` files from a given compressed directory into an `uncompressed` folder.
- **--convert \<directory\>**: Recursively converts non-FLAC music files (e.g., MP3, AAC, OGG, WAV) to FLAC using ffmpeg with maximum compression. Converted files are stored in a `converted` folder.
- **--install**: Installs the `mm` script into your local bin path along with its manpage and bash completion script.
- **--uninstall**: Uninstalls the `mm` script and removes its manpage and bash completion file.
- **--help**: Displays this help message.
- **--version**: Displays version information.

## Requirements

- Bash
- 7z (p7zip)
- ffmpeg
- find
- realpath

## Installation

To install the program, run:

```bash
./mm --install
```

This will copy the script to your bin directory, install the manpage, and set up bash completion. If you are not running as root, the files will be installed in your local directories (e.g. ~/.local/bin).
Uninstallation

To uninstall the program, run:
```bash
./mm --uninstall
```

Usage

Display the help message:
```bash
mm --help
```

Enjoy managing your music
