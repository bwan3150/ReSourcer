# ReSourcer

Download, categorize, and browse your creative resources. A local art management centre.

## Features

**Downloader**
- Support for YouTube, Twitter, Pixiv, and more
- Pixiv animated image (ugoira) support
- Real-time download progress tracking

**Classifier**
- Keyboard shortcuts for quick file classification
- Preset classification schemes
- Real-time preview

**Gallery**
- Grid-based media browsing
- Automatic thumbnail generation
- Batch upload support

## Download

Visit [Releases](../../releases) to download the version for your platform:
- macOS (Apple Silicon): `re-sourcer-macos-aarch64`
- Linux (x86_64): `re-sourcer-linux-x86_64`
- Windows (x86_64): `re-sourcer-windows-x86_64.exe`

## Usage

### macOS / Linux
```bash
chmod +x re-sourcer-macos-aarch64
./re-sourcer-macos-aarch64
```

### Windows
Double-click `re-sourcer-windows-x86_64.exe`

Then scan QR code or visit URL on the opened website using any devices under same LAN.

## Development

```bash
./dev.sh
```

## Acknowledgments

- [ffmpeg](https://github.com/FFmpeg/FFmpeg): Binary Included
- [yt-dlp](https://github.com/yt-dlp/yt-dlp): Binary Included
- [webextension-pixiv-toolkit](https://github.com/leoding86/webextension-pixiv-toolkit): Reference for Pixiv download logic

## License

MIT License



## To-do List
- [ ] Gallery File Preview with Auto Play
- [ ] Could download file from gallery to device photos album
