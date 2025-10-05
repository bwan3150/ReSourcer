# Pixiv Ugoira (动图) 下载实现方案

参考项目：[webextension-pixiv-toolkit](https://github.com/leoding86/webextension-pixiv-toolkit)

## 概述

Pixiv 的 Ugoira（うごイラ）是一种动态插画格式，本质上是一个包含多帧图片的 ZIP 文件，配合帧延迟信息来播放动画。

## 下载流程

### 1. 获取作品元数据

**API 端点：**
```
GET https://www.pixiv.net/ajax/illust/{id}/ugoira_meta
```

**响应示例：**
```json
{
  "error": false,
  "message": "",
  "body": {
    "src": "https://i.pximg.net/img-zip-ugoira/..._ugoira600x600.zip",
    "originalSrc": "https://i.pximg.net/img-zip-ugoira/..._ugoira1920x1080.zip",
    "mime_type": "image/jpeg",
    "frames": [
      {
        "file": "000000.jpg",
        "delay": 100
      },
      {
        "file": "000001.jpg",
        "delay": 100
      }
    ]
  }
}
```

**关键字段：**
- `originalSrc`: ZIP 文件的原画质下载链接
- `frames`: 帧序列信息，包含文件名和延迟时间（毫秒）
- `mime_type`: 帧图片的 MIME 类型

### 2. 下载 ZIP 文件

使用 `originalSrc` 下载完整的 ZIP 压缩包，包含所有原画质帧图片。

**请求头要求：**
```
Referer: https://www.pixiv.net/
```

### 3. 处理选项

下载 ZIP 后有以下几种处理方式：

#### 选项 A: 保存原始 ZIP

直接保存 ZIP 文件，可选择性地在 ZIP 中添加 `animation.json` 元数据文件。

**实现代码参考：**
```javascript
// UgoiraDownloadTask.js: 160-187
async onItemFinish({ blob, mimeType }) {
  this.zip = new JSZip();
  await this.zip.loadAsync(blob);

  // 可选：添加动画元数据
  if (packAnimationJsonType > 0) {
    this.zip.file('animation.json', JSON.stringify({
      ugokuIllustData: {
        src: context.illustSrc,
        originalSrc: context.illustOriginalSrc,
        mime_type: context.illustMimeType,
        frames: context.illustFrames
      }
    }));
  }

  let url = URL.createObjectURL(await this.zip.generateAsync({ type: 'blob' }));
  // 保存文件...
}
```

#### 选项 B: 转换为 GIF

使用 GIF.js 库将帧序列转换为 GIF 动画。

**实现步骤：**

1. **初始化 GIF 编码器：**
```javascript
// GifGenerator.js: 72-84
const gif = new GIF({
  workers: 4,           // Web Worker 数量
  quality: 10,          // 质量 (1-30, 越低越好)
  width: imageWidth,
  height: imageHeight,
  repeat: 0,           // 0 = 无限循环
  workerScript: workerScriptUrl
});
```

2. **逐帧添加图片：**
```javascript
// GifGenerator.js: 36-61
async function appendImageToGifFrame(index = 0) {
  if (index < frames.length) {
    // 从 ZIP 中提取帧
    const base64 = await zip.file(frames[index].file).async('base64');
    const imageBase64 = `data:image/jpeg;base64,${base64}`;

    const image = new Image();
    image.src = imageBase64;

    // 添加到 GIF
    gif.addFrame(image, {
      delay: frames[index].delay  // 延迟时间（毫秒）
    });

    return appendImageToGifFrame(index + 1);
  }
}
```

3. **渲染并保存：**
```javascript
// GifGenerator.js: 86-98
gif.on('progress', (progress) => {
  console.log('Encoding progress:', progress);
});

gif.on('finished', (blob) => {
  // blob 即为生成的 GIF 文件
  saveFile(blob, 'animation.gif');
});

gif.render();
```

#### 选项 C: 转换为 WebM/MP4

使用 FFmpeg.js 将帧序列转换为视频格式。

**实现步骤：**

1. **初始化 FFmpeg：**
```javascript
// UgoiraDownloadTask.js: 210-225
const { createFFmpeg } = FFmpeg;
const ffmpeg = createFFmpeg({
  log: true,
  corePath: 'path/to/ffmpeg-core.js',
});

ffmpeg.setProgress(progress => {
  console.log('Processing:', progress.ratio);
});

await ffmpeg.load();
```

2. **准备帧文件：**
```javascript
// UgoiraDownloadTask.js: 233-252
let framesContent = '';

for (let i = 0; i < frames.length; i++) {
  const frame = frames[i];
  const data = await zip.file(frame.file).async('uint8array');
  const filename = String(i).padStart(6, '0') + '.jpg';

  // 写入 FFmpeg 虚拟文件系统
  ffmpeg.FS('writeFile', filename, data);

  // 构建帧信息
  framesContent += `file '${frame.file}'\n`;
  framesContent += `duration ${frame.delay / 1000}\n`;
}

ffmpeg.FS('writeFile', 'input.txt', framesContent);
```

3. **转换为 GIF：**
```javascript
// UgoiraDownloadTask.js: 262-263
await ffmpeg.run('-f', 'concat', '-i', 'input.txt', '-plays', 0, 'out.gif');
const data = ffmpeg.FS('readFile', 'out.gif');
```

4. **转换为 WebM：**
```javascript
// 自定义命令示例
await ffmpeg.run(
  '-f', 'concat',
  '-i', 'input.txt',
  '-c:v', 'libvpx-vp9',
  '-pix_fmt', 'yuva420p',
  'out.webm'
);
```

## 依赖库

### GIF 转换
- **GIF.js**: https://github.com/jnordberg/gif.js
  - 纯 JavaScript GIF 编码器
  - 支持 Web Worker 多线程编码
  - 质量可调

### 视频转换
- **FFmpeg.js / FFmpeg.wasm**: https://github.com/ffmpegwasm/ffmpeg.wasm
  - WebAssembly 版本的 FFmpeg
  - 支持多种视频格式转换
  - 可自定义 FFmpeg 命令

### ZIP 处理
- **JSZip**: https://stuk.github.io/jszip/
  - ZIP 文件读写
  - 支持异步操作

## 认证要求

下载 Pixiv 内容需要登录认证：

**Cookie 方式：**
- 需要 `PHPSESSID` cookie
- 保存在 `~/.config/re-sourcer/credentials/pixiv/token.txt`

**请求头：**
```
Cookie: PHPSESSID=<your_session_id>
Referer: https://www.pixiv.net/
```

## 完整下载流程示例

```javascript
// 1. 获取元数据
const metaResponse = await fetch(`https://www.pixiv.net/ajax/illust/${id}/ugoira_meta`, {
  headers: {
    'Cookie': `PHPSESSID=${token}`,
    'Referer': 'https://www.pixiv.net/'
  }
});
const meta = await metaResponse.json();

// 2. 下载 ZIP
const zipResponse = await fetch(meta.body.originalSrc, {
  headers: {
    'Referer': 'https://www.pixiv.net/'
  }
});
const zipBlob = await zipResponse.blob();

// 3. 加载 ZIP
const zip = new JSZip();
await zip.loadAsync(zipBlob);

// 4. 转换为 GIF
const gif = new GIF({
  workers: 4,
  quality: 10,
  width: 1920,
  height: 1080,
  repeat: 0
});

for (const frame of meta.body.frames) {
  const base64 = await zip.file(frame.file).async('base64');
  const img = new Image();
  img.src = `data:image/jpeg;base64,${base64}`;

  await new Promise(resolve => {
    img.onload = () => {
      gif.addFrame(img, { delay: frame.delay });
      resolve();
    };
  });
}

gif.on('finished', (blob) => {
  // 保存 GIF 文件
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${id}.gif`;
  a.click();
});

gif.render();
```

## Rust 实现建议

对于 Rust 后端实现，建议：

1. **下载 ZIP**: 使用 `reqwest` 下载原始 ZIP 文件
2. **ZIP 处理**: 使用 `zip` crate 读取 ZIP 内容
3. **GIF 转换**:
   - 选项 A: 使用 `image` + `gif` crate 纯 Rust 实现
   - 选项 B: 调用外部 `ffmpeg` 命令行工具
4. **视频转换**: 调用 `ffmpeg` 命令行工具

**FFmpeg 命令示例：**
```bash
# 生成 GIF
ffmpeg -f concat -i input.txt -plays 0 output.gif

# 生成 WebM (带透明度)
ffmpeg -f concat -i input.txt -c:v libvpx-vp9 -pix_fmt yuva420p output.webm

# 生成 MP4
ffmpeg -f concat -i input.txt -c:v libx264 -pix_fmt yuv420p output.mp4
```

## 参考资源

- [Pixiv API 非官方文档](https://github.com/upbit/pixivpy)
- [webextension-pixiv-toolkit 源码](https://github.com/leoding86/webextension-pixiv-toolkit)
- [GIF.js 文档](https://github.com/jnordberg/gif.js)
- [FFmpeg.wasm 文档](https://ffmpegwasm.netlify.app/)
