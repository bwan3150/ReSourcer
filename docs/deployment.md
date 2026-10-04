# 部署

Linux / NAS 上部署 ReSourcer 服务端。网页端由服务端一并托管，不需要额外的容器。

## 一键安装

```bash
curl -sSL https://raw.githubusercontent.com/bwan3150/ReSourcer/main/ops/setup.sh | sudo bash
```

脚本会：

1. 问你**持久化数据目录**（下面详述），已装过则沿用上次的，不再追问
2. 下载最新的 `server-v*` 二进制到 `/opt/re-sourcer`
3. 下载 ffmpeg / ffprobe
4. 写 `/opt/re-sourcer/data.json` 和 systemd unit，启动并设为开机自启

重跑同一条命令就是升级。

## 两个目录的分工

| | 路径 | 内容 | 能不能被清空 |
|---|---|---|---|
| 程序目录 | `/opt/re-sourcer` | 二进制、`data.json`、`tmp/`、`uploads_staging/` | 能，重装即可恢复 |
| 数据目录 | 你指定（如 `/volume1/docker/ReSourcer`） | `sqlite/` `config/` `credentials/` `tools/` `backups/` `web/` | **不能** |

分开是因为群晖、QNAP 的系统更新可能把 `/opt` 整个清空重装。数据目录必须指向一个
不会被这种更新波及的卷。

数据目录的解析顺序：

1. 环境变量 `RESOURCER_DATA_DIR`（systemd unit 里就是这么传的）
2. 程序目录下的 `data.json`：`{"data_dir": "/volume1/docker/ReSourcer"}`
3. 都没有则回退到程序目录（单机试用时的行为）

第 2 条让不经 systemd 启动的场景（手动运行、macOS、容器）也能找到数据。

### 从旧版迁移

旧版本把数据放在程序目录下。首次设置数据目录后，服务端启动时会自动把
`sqlite/` `config/` `credentials/` `tools/` 整体搬过去，日志里有 `[migrate]` 开头的记录。
迁移只在目标目录为空且旧目录有数据时执行，不会覆盖已有数据。

手动搬也可以（搬之前先停服务）：

```bash
systemctl stop re-sourcer
mkdir -p /volume1/docker/ReSourcer
for d in sqlite config credentials tools backups; do
  [ -d "/opt/re-sourcer/$d" ] && mv "/opt/re-sourcer/$d" /volume1/docker/ReSourcer/
done
curl -sSL https://raw.githubusercontent.com/bwan3150/ReSourcer/main/ops/setup.sh \
  | RESOURCER_DATA_DIR=/volume1/docker/ReSourcer bash
```

## 更新

三端各自独立：

| | 怎么更新 | 要重启吗 |
|---|---|---|
| 服务端 | 设置 → 关于 → 服务端版本 → 下载，或重跑安装脚本 | 要，靠 systemd `Restart=always` 拉起 |
| 网页端 | 设置 → 关于 → Web 版本 → 下载 | 不用，替换静态文件即可 |
| iOS | TestFlight 自己推送 | — |

服务端和网页端各发各的 release（`server-v*` / `web-v*`），互不影响。

**全新安装时 `web/` 是空的**，访问根路径会 404，启动日志里有提示。
在设置页点一次网页端更新即可；也可以手动把构建产物放进 `<数据目录>/web/`。

## 配置

`<数据目录>/config/` 下：

| 文件 | 作用 |
|---|---|
| `app.json` | 版本号与各端下载地址。`version` 每次启动会对齐到二进制自身的版本 |
| `secret.json` | API Key，自动生成 |
| `tools.json` | ffmpeg / yt-dlp 的下载源 |
| `preference.json` | 运行偏好。`enable_web: false` 可关掉网页端托管，只留后端 API |

`preference.json` 与 `app.json` 分开，是因为 `app.json` 会被更新流程改写，而偏好不该被覆盖。

## 常用命令

```bash
systemctl status re-sourcer        # 状态
systemctl restart re-sourcer       # 重启
journalctl -u re-sourcer -f        # 跟踪日志
journalctl -u re-sourcer -n 100    # 最近 100 行
```

## 数据库备份

服务端每次启动备份一次，之后每 6 小时一次，保留最近 10 份，放在 `<数据目录>/backups/`。
用 SQLite 的 `VACUUM INTO` 而不是直接复制文件 —— WAL 模式下直接 `cp` 可能拿到半写状态。

恢复：

```bash
systemctl stop re-sourcer
cp <数据目录>/backups/data-YYYYMMDD-HHMMSS.db <数据目录>/sqlite/data.db
systemctl start re-sourcer
```

## 开放端口

防火墙限制了 1234 端口时：

```bash
# UFW
sudo ufw allow 1234/tcp

# Firewalld
sudo firewall-cmd --permanent --add-port=1234/tcp
sudo firewall-cmd --reload
```

## 手动安装

不想用脚本的话，`ops/re-sourcer.service` 是一份 unit 模板，按里面的注释改好路径，
放到 `/etc/systemd/system/` 下即可。二进制去 [Releases](../../releases) 下载 `server-v*` 那一条。
