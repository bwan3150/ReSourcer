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

## Install

Linux / NAS — one line, sets up a systemd service:

```bash
curl -sSL https://raw.githubusercontent.com/bwan3150/ReSourcer/main/ops/setup.sh | sudo bash
```

Or grab `re-sourcer-linux-x86_64` from the latest `server-v*` [release](../../releases)
and run it directly. See [docs/deployment.md](docs/deployment.md) for the data directory
layout, updates and configuration.

The server also hosts the web UI — no separate container needed. Open
`http://<host>:1234` from any device on the same network.

## Updating

| | How |
|---|---|
| Server | Settings → About → Server version → download, or re-run the install script |
| Web UI | Settings → About → Web version → download (no restart) |
| iOS | TestFlight |

## Development

```bash
./dev.sh web     # server + vite dev server
./dev.sh         # server only
./ci.sh          # bump versions and push release tags
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
