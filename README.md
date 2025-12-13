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




- [ ] 从相册将图片视频等上传到服务器后, 出现那个删除本机上的图片视频的那个弹窗, 改为默认删除的checkbox, 而不是空着不勾选
- [ ] 进入App后, 如果发现当前选择的服务器连接不上就自动退回到服务器列表那个页面, 别保持在画廊页面显示个空画廊
- [ ] 可以在画廊中, 浏览图片视频和其他文件时候, 点击右上角的按钮, 除了查看文件信息外, 还要可以将该文件移动到其他分类文件夹下, 或者将文件进行改名

- [ ] 可以自动播放
- [ ] 可以下载到相册
- [ ] 分类器页面，快捷键显示，改为数量统计
- [ ] 可以换分类的排列顺序
