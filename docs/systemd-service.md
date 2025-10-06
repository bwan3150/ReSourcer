# ReSourcer Systemd 服务配置

在 Linux 服务器上将 ReSourcer 配置为后台服务，实现开机自启。

## 一、编译项目

```bash
cargo build --release
```

## 二、创建 systemd 服务

创建文件 `/etc/systemd/system/resourcer.service`：

```ini
[Unit]
Description=ReSourcer Service
After=network.target

[Service]
Type=simple
User=YOUR_USERNAME
Group=YOUR_USERNAME
WorkingDirectory=/path/to/your/project
ExecStart=/path/to/your/project/target/release/re-sourcer
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**修改配置：**
- `User` 和 `Group` → 你的 Linux 用户名
- `WorkingDirectory` → 项目路径（例如：`/home/ubuntu/re-sourcer`）
- `ExecStart` → 二进制文件路径（例如：`/home/ubuntu/re-sourcer/target/release/re-sourcer`）

## 三、启动服务

```bash
# 重载配置
sudo systemctl daemon-reload

# 启动服务
sudo systemctl start resourcer

# 开机自启
sudo systemctl enable resourcer

# 查看状态
sudo systemctl status resourcer
```

## 四、常用命令

```bash
# 停止服务
sudo systemctl stop resourcer

# 重启服务
sudo systemctl restart resourcer

# 查看日志
sudo journalctl -u resourcer -f
sudo journalctl -u resourcer -n 100 -f
```

## 五、开放端口
这一步是针对防火墙限制了此端口的

```bash
# UFW
sudo ufw allow 1234/tcp

# Firewalld
sudo firewall-cmd --permanent --add-port=1234/tcp
sudo firewall-cmd --reload
```
