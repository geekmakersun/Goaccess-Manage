# GoAccess 快速入门指南

> GoAccess 是一个开源的实时 Web 日志分析器和交互式查看器，专为系统管理员、DevOps 工程师和安全专业人员设计。本文档将帮助你从安装到上手使用 GoAccess。
>
> **前置知识**：本文档假设读者具备基本的 Linux 命令行操作能力，了解 Web 服务器（如 Apache/Nginx）和访问日志的基本概念。

## 目录

1. [概述](#1-概述)
2. [安装 GoAccess](#2-安装-goaccess)
3. [确定日志格式](#3-确定日志格式)
4. [运行 GoAccess](#4-运行-goaccess)
5. [常用命令参数速查](#5-常用命令参数速查)
6. [Docker 部署](#6-docker-部署)
7. [配置文件说明](#7-配置文件说明)
8. [多站点部署与 Nginx 反向代理](#8-多站点部署与-nginx-反向代理)
9. [故障排除与资源](#9-故障排除与资源)

---

## 1. 概述

**GoAccess** 是一个开源的实时 Web 日志分析器和交互式查看器，运行在 \*nix 系统的终端中或直接在浏览器中使用。它能够实时解析 Web 服务器日志，直接在终端或通过实时 HTML 仪表板呈现数据，便于监控流量、检测异常和快速排查问题。

### 核心特性

- **实时分析**：在终端或浏览器中实时查看日志统计数据
- **终端 + HTML 双模式输出**：支持终端交互式查看和生成静态/实时 HTML 报告
- **高性能**：默认哈希表存储，基准测试可达 **10 万行/秒** 的解析速度
- **低内存占用**：约 340 万行日志仅消耗约 134 MiB 内存
- **支持多种日志格式**：内置 Apache (COMBINED)、Nginx、CloudFront、AWS ELB/ALB 等预定义格式
- **丰富的统计面板**：独立访客、请求文件、404 错误、操作系统、浏览器、地理位置等 20+ 面板

### 系统要求

- **必需依赖**：`ncurses`（终端显示库）
- **可选依赖**：`GeoIP`/`GeoIP2`（地理位置定位）、`OpenSSL`（WebSocket TLS 支持）、`zlib`（解析压缩日志）

> 当前最新稳定版本：**v1.10.2**

## 2. 安装 GoAccess

GoAccess 提供多种安装方式，选择最适合你环境的方式即可。

### 2.1 从源码编译安装

下载、解压并编译（推荐方式，可获取最新版本）：

```bash
# 下载最新稳定版
wget https://tar.goaccess.io/goaccess-1.10.2.tar.gz
tar -xzvf goaccess-1.10.2.tar.gz
cd goaccess-1.10.2/

# 配置、编译、安装
./configure --enable-utf8 --enable-geoip=mmdb --with-zlib
make
make install
```

**编译配置选项说明：**

| 选项 | 说明 |
|------|------|
| `--enable-utf8` | 启用宽字符支持（需要 `ncursesw`） |
| `--enable-geoip=mmdb` | 启用 GeoIP2 地理位置支持 |
| `--with-openssl` | 启用 OpenSSL 支持（WebSocket TLS） |
| `--with-zlib` | 启用 zlib 支持（直接解析 .gz 压缩日志） |
| `--enable-debug` | 编译调试符号 |

### 2.2 使用包管理器安装

各主流发行版的安装命令：

**Debian / Ubuntu：**

```bash
# 官方源（推荐，获取最新版本）
wget -O - https://deb.goaccess.io/gnugpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/goaccess.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/goaccess.gpg arch=$(dpkg --print-architecture)] https://deb.goaccess.io/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/goaccess.list
sudo apt-get update
sudo apt-get install goaccess
```

**其他发行版：**

```bash
# Fedora
sudo yum install goaccess

# Arch Linux
sudo pacman -S goaccess

# macOS (Homebrew)
brew install goaccess

# FreeBSD
sudo pkg install sysutils/goaccess

# OpenSUSE
sudo zypper ar -f obs://server:http http
sudo zypper in goaccess
```

> **注意**：包管理器安装的版本可能不是最新的。如需最新稳定版，建议使用源码编译或官方 Debian 仓库。

### 2.3 各发行版编译依赖

| 发行版 | NCurses（必需） | GeoIP2（可选） | OpenSSL（可选） |
|--------|----------------|---------------|----------------|
| Ubuntu/Debian | `libncursesw6-dev` | `libmaxminddb-dev` | `libssl-dev` |
| Fedora/RHEL/CentOS | `ncurses-devel` | `libmaxminddb-devel` | `openssl-devel` |
| Arch Linux | `ncurses` | `libmaxminddb` | `openssl` |

### 2.4 从 GitHub 构建开发版

```bash
git clone https://github.com/allinurl/goaccess.git
cd goaccess
autoreconf -fi
./configure --enable-utf8 --enable-geoip=mmdb
make
make install
```

## 3. 确定日志格式

安装完成后，使用 GoAccess 之前需要确定你的 Web 服务器日志格式。GoAccess 内置了多种预定义日志格式，也可以通过命令行或配置文件指定自定义格式。

### 3.1 预定义日志格式

GoAccess 支持以下预定义格式名称，可直接通过 `--log-format` 参数使用：

| 格式名称 | 说明 |
|----------|------|
| `COMBINED` | Apache/Nginx 组合日志格式（最常用） |
| `VCOMBINED` | 带虚拟主机的组合日志格式 |
| `COMMON` | Apache/Nginx 通用日志格式 |
| `VCOMMON` | 带虚拟主机的通用日志格式 |
| `W3C` | W3C 扩展日志文件格式 |
| `CLOUDFRONT` | Amazon CloudFront Web 分发日志 |
| `AWSELB` | Amazon 弹性负载均衡器日志 |
| `AWSALB` | Amazon 应用负载均衡器日志 |
| `AWSS3` | Amazon S3 日志 |
| `CADDY` | Caddy JSON 结构化日志 |
| `TRAEFIKCLF` | Traefik CLF 格式日志 |
| `SQUID` | Squid 原生日志格式 |
| `CLOUDSTORAGE` | Google Cloud Storage 日志 |

### 3.2 如何确定你的日志格式

**方法一：使用交互式配置对话框（推荐新手）**

```bash
goaccess access.log -c
```

运行后会弹出日志格式选择界面，从预定义格式中选择匹配你服务器的格式。

**方法二：命令行直接指定**

```bash
# Apache/Nginx 标准组合格式
goaccess access.log --log-format=COMBINED

# 带虚拟主机的组合格式
goaccess access.log --log-format=VCOMBINED
```

**方法三：在配置文件中永久设置**

编辑配置文件（见[第 7 节](#7-配置文件说明)），设置以下参数：

```
log-format COMBINED
date-format %d/%b/%Y
time-format %H:%M:%S
```

### 3.3 自定义日志格式

如果你的日志格式不在预定义列表中，可以使用自定义格式。格式说明符如下：

| 说明符 | 含义 |
|--------|------|
| `%h` | 远程主机（IP） |
| `%d` | 日期 |
| `%t` | 时间 |
| `%r` | 请求行 |
| `%s` | HTTP 状态码 |
| `%b` | 响应大小（字节） |
| `%R` | 引荐 URL |
| `%u` | 远程用户 |
| `%v` | 虚拟主机 |
| `%e` | HTTP 认证用户 |
| `%C` | 缓存状态 |
| `%M` | MIME 类型 |
| `%K` | SSL/TLS 加密信息 |

> **提示**：如果不确定日志格式，可以在 [GitHub Issues](https://github.com/allinurl/goaccess/issues) 提交几行日志样本请求帮助。

### 3.4 常见问题：非英语日志日期

如果你的访问日志包含英语月份（如 `12/Jan/2021`），但系统区域设置不是英语，需要设置 `LC_TIME`：

```bash
LC_TIME="en_US.UTF-8" goaccess access.log --log-format=COMBINED
```

## 4. 运行 GoAccess

安装并确定日志格式后，即可开始使用 GoAccess 分析日志。以下是三种最常见的使用场景。

### 4.1 终端实时输出

在终端中以交互式仪表板实时查看日志统计：

```bash
goaccess access.log -c
```

- `-c` 参数会弹出日志格式配置对话框，选择格式后即可看到实时统计面板
- 使用 `TAB` 键在各个面板之间切换
- 按 `q` 退出

### 4.2 生成静态 HTML 报告

将分析结果输出为一份静态 HTML 文件，适合离线查看和分享：

```bash
goaccess access.log -o report.html --log-format=COMBINED
```

- `-o report.html` 指定输出文件路径
- `--log-format=COMBINED` 指定日志格式（也可在配置文件中预设）

**解析多个日志文件（含压缩文件）：**

```bash
zcat -f /var/log/apache2/access.log* | goaccess -a -o report.html --log-format=COMBINED
```

### 4.3 生成实时 HTML 报告

生成一份实时更新的 HTML 仪表板，数据通过 WebSocket 推送到浏览器：

```bash
goaccess access.log -o /var/www/html/report.html --log-format=COMBINED --real-time-html
```

**重要说明：**

- **报告文件托管**：将 `report.html` 放在 Web 服务器的文档根目录下。GoAccess 本身**不提供 HTTP 服务**来托管 HTML 文件，需要你自行配置 Web 服务器（如 Nginx/Apache）来提供报告页面的访问。
- **实时数据推送**：GoAccess 内置了一个 **WebSocket 服务器**，负责将实时解析的日志数据推送到浏览器端。这是一个独立于 HTTP 的服务，默认监听 `7890` 端口。
- **访问方式**：通过浏览器访问 `http://example.com/report.html` 打开报告页面，页面会自动通过 WebSocket 连接 GoAccess 获取实时数据。
- **端口要求**：确保 WebSocket 端口（默认 `7890`）已开放，且浏览器可以访问到该端口。
- **无 Web 服务器**：如果没有运行 Web 服务器，可以直接在浏览器中打开生成的 HTML 文件（如按 `Ctrl+O`），但实时功能将不可用。
- **TLS/SSL 支持**：如需通过 HTTPS/WSS 提供实时数据，需使用 `--ssl-cert` 和 `--ssl-key` 参数，编译时需启用 `--with-openssl`。

### 4.4 从标准输入读取

GoAccess 也支持从管道读取日志数据。**注意：管道模式下不会弹出格式选择对话框，必须显式指定日志格式参数：**

```bash
# 解析单个日志
cat access.log | goaccess --log-format=COMBINED -

# 实时追踪日志
tail -f /var/log/apache2/access.log | goaccess --log-format=COMBINED -
```

## 5. 常用命令参数速查

以下按功能分类列出 GoAccess 最常用的命令行参数。

### 日志格式相关

| 参数 | 说明 | 示例 |
|------|------|------|
| `--log-format` | 指定日志格式 | `--log-format=COMBINED` |
| `--date-format` | 指定日期格式 | `--date-format=%d/%b/%Y` |
| `--time-format` | 指定时间格式 | `--time-format=%H:%M:%S` |
| `--datetime-format` | 合并日期时间格式（需配合 `%x` 使用，且不可与 `--date-format`/`--time-format` 同时使用） | `--datetime-format=%d/%b/%Y:%H:%M:%S %z` |

### 输入输出相关

| 参数 | 说明 | 示例 |
|------|------|------|
| `-f` | 指定输入日志文件 | `-f /var/log/nginx/access.log` |
| `-o` | 指定输出文件 | `-o report.html` |
| `-p` | 指定配置文件 | `-p /etc/goaccess.conf` |
| `-` | 从标准输入读取 | `cat access.log \| goaccess -` |

### 终端界面相关

| 参数 | 说明 | 示例 |
|------|------|------|
| `-c` | 启动时弹出日志格式配置对话框 | `goaccess access.log -c` |
| `-i` | 高亮当前活动面板 | `-i` |
| `-m` | 启用鼠标支持 | `-m` |
| `--color-scheme` | 选择终端配色方案（1=单色, 2=绿色, 3=Monokai） | `--color-scheme=3` |

### HTML 报告相关

| 参数 | 说明 | 示例 |
|------|------|------|
| `--real-time-html` | 启用实时 HTML 报告 | `--real-time-html` |
| `--html-report-title` | 设置 HTML 报告标题 | `--html-report-title="My Report"` |
| `--html-refresh` | HTML 刷新间隔（秒） | `--html-refresh=5` |
| `--html-custom-css` | 加载自定义 CSS | `--html-custom-css=style.css` |
| `--html-custom-js` | 加载自定义 JS | `--html-custom-js=custom.js` |

### 服务器/实时相关

| 参数 | 说明 | 示例 |
|------|------|------|
| `--addr` | 绑定 IP 地址 | `--addr=127.0.0.1` |
| `--port` | WebSocket 端口（默认 7890） | `--port=8080` |
| `--daemonize` | 以守护进程运行 | `--daemonize` |
| `--ws-url` | WebSocket 服务器 URL | `--ws-url=wss://example.com` |
| `--origin` | 限制 WebSocket 来源 | `--origin=http://example.com` |
| `--ssl-cert` | TLS 证书路径 | `--ssl-cert=/path/to/cert.crt` |
| `--ssl-key` | TLS 私钥路径 | `--ssl-key=/path/to/priv.key` |

### 解析与性能相关

| 参数 | 说明 | 示例 |
|------|------|------|
| `-a` | 启用用户代理列表（增加内存消耗） | `-a` |
| `-q` | 移除查询字符串（减少内存消耗） | `-q` |
| `--no-progress` | 禁用解析进度显示 | `--no-progress` |
| `--max-items` | 每个面板最大显示条目数 | `--max-items=100` |
| `--tz` | 设置输出时区 | `--tz=Asia/Shanghai` |

## 6. Docker 部署

GoAccess 提供官方 Docker 镜像 `allinurl/goaccess`，适合容器化环境部署。

### 6.1 生成静态 HTML 报告

通过管道将日志传入 Docker 容器，输出静态报告：

```bash
cat access.log | docker run --rm -i -e LANG=$LANG allinurl/goaccess \
  -a -o html --log-format COMBINED - > report.html
```

### 6.2 生成实时 HTML 报告

使用 `tail -F` 持续读取日志，并映射 WebSocket 端口：

```bash
tail -F access.log | docker run -p 7890:7890 --rm -i -e LANG=$LANG allinurl/goaccess \
  -a -o html --log-format COMBINED --real-time-html - > report.html
```

**参数说明：**

- `--rm`：容器运行结束后自动删除
- `-i`：保持标准输入打开
- `-e LANG=$LANG`：传递语言环境变量，确保 UTF-8 编码正确
- `-p 7890:7890`：将容器内的 WebSocket 端口映射到宿主机

### 6.3 使用 Docker Compose（推荐生产环境）

```yaml
version: '3'
services:
  goaccess:
    image: allinurl/goaccess
    ports:
      - "7890:7890"
    volumes:
      - ./access.log:/var/log/access.log:ro
      - ./report.html:/var/www/html/report.html
    command: >
      -a -o /var/www/html/report.html
      --log-format=COMBINED
      --real-time-html
      --ws-url=ws://localhost:7890
    restart: unless-stopped
```

> **注意**：实时模式下，需要确保宿主机的 `7890` 端口可访问，以便浏览器通过 WebSocket 接收实时数据。

## 7. 配置文件说明

使用配置文件可以避免每次都在命令行中重复输入参数，实现配置的持久化管理。

### 7.1 配置文件位置

GoAccess 按以下顺序查找配置文件：

1. `~/.goaccessrc`（用户主目录）
2. `%sysconfdir%/goaccess.conf`（系统配置目录，通常为 `/etc/`、`/usr/etc/` 或 `/usr/local/etc/`）

运行以下命令可查看默认配置文件的路径：

```bash
goaccess --dcf
```

默认配置文件模板可在 GitHub 上找到：
[goaccess.conf](https://github.com/allinurl/goaccess/blob/master/config/goaccess.conf)

### 7.2 常用配置项

以下是一个实用的配置文件示例，涵盖最常见的配置场景：

```ini
# ==================== 日志格式 ====================
# 使用预定义格式（COMBINED / VCOMBINED / COMMON / W3C 等）
log-format COMBINED
date-format %d/%b/%Y
time-format %H:%M:%S

# ==================== 输出设置 ====================
# HTML 报告标题
html-report-title My Server Analytics

# HTML 刷新间隔（秒），仅实时模式有效
html-refresh 5

# 每个面板最大显示条目数
max-items 50

# ==================== 界面设置 ====================
# 终端配色方案：1=单色, 2=绿色, 3=Monokai
color-scheme 3

# 启用鼠标支持
with-mouse true

# 高亮活动面板
hl-header true

# ==================== 解析设置 ====================
# 启用用户代理列表（会增加内存消耗）
enable-panel AGENTS

# 移除查询字符串（减少内存消耗）
query-string true

# 时区设置
tz Asia/Shanghai

# ==================== 服务器设置 ====================
# WebSocket 端口
port 7890

# 绑定地址
addr 0.0.0.0

# 以守护进程运行
daemonize false

# 实时 HTML
real-time-html true

# WebSocket URL
ws-url wss://example.com
```

### 7.3 使用自定义配置文件

通过 `-p` 参数指定配置文件路径：

```bash
goaccess access.log -p /path/to/my-goaccess.conf -o report.html
```

## 8. 多站点部署与 Nginx 反向代理

在生产环境中，通常需要为多个站点分别生成实时报告，并通过域名远程访问。本节说明多站点部署的架构和配置方法。

### 8.1 多站点 WebSocket 要点

**每个站点需要独立的 GoAccess 实例和端口。** GoAccess 的 WebSocket 服务器与日志解析是一一绑定的，多个站点不能共用同一个 WebSocket 服务：

```
站点 A (example.com)  →  GoAccess 实例 A  →  WebSocket 端口 7890
站点 B (blog.com)     →  GoAccess 实例 B  →  WebSocket 端口 7891
站点 C (shop.com)     →  GoAccess 实例 C  →  WebSocket 端口 7892
```

### 8.2 WebSocket 绑定 127.0.0.1 与远程访问

**问题：** 如果 GoAccess 的 WebSocket 绑定 `127.0.0.1`，远程浏览器无法直接连接到该地址，实时功能将失效。

```
远程用户浏览器 ──→ Nginx (域名) ──→ 返回 HTML 报告页面 ✅
远程用户浏览器 ──→ WebSocket 连接 ──→ 127.0.0.1:7890 ❌ (浏览器在远程，连不到本地)
```

**解决方案：通过 Nginx 反向代理 WebSocket。** GoAccess 绑定本地地址（安全），Nginx 负责将域名的 WebSocket 请求转发到本地 GoAccess：

```nginx
server {
    server_name stats.example.com;

    # HTML 报告文件
    location / {
        root /var/www/goaccess;
        index report.html;
    }

    # 反向代理 WebSocket 到本地 GoAccess
    location /ws {
        proxy_pass http://127.0.0.1:7890;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }
}
```

对应的 GoAccess 启动命令：

```bash
# --addr 绑定本地（安全，不直接暴露端口）
# --ws-url 告诉浏览器通过域名路径连接 WebSocket
goaccess /var/log/nginx/access.log \
  -o /var/www/goaccess/report.html \
  --log-format=COMBINED \
  --real-time-html \
  --addr=127.0.0.1 \
  --port=7890 \
  --ws-url=ws://stats.example.com/ws
```

**关键参数说明：**

| 参数 | 作用 |
|------|------|
| `--addr=127.0.0.1` | WebSocket 仅监听本地，外部无法直连（安全） |
| `--port=7890` | 本地 WebSocket 端口，多站点需使用不同端口 |
| `--ws-url=ws://域名/ws` | 嵌入 HTML 报告中，告诉浏览器 WebSocket 的连接地址 |

### 8.3 多站点完整配置示例

**Nginx 配置（多站点）：**

```nginx
# 站点 A
server {
    server_name stats-a.example.com;
    root /var/www/goaccess/a;

    location / {
        index report.html;
    }

    location /ws {
        proxy_pass http://127.0.0.1:7890;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }
}

# 站点 B
server {
    server_name stats-b.example.com;
    root /var/www/goaccess/b;

    location / {
        index report.html;
    }

    location /ws {
        proxy_pass http://127.0.0.1:7891;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }
}
```

**GoAccess 启动命令（多实例）：**

```bash
# 站点 A
goaccess /var/log/site-a/access.log \
  -o /var/www/goaccess/a/report.html \
  --log-format=COMBINED \
  --real-time-html \
  --addr=127.0.0.1 --port=7890 \
  --ws-url=ws://stats-a.example.com/ws \
  --daemonize

# 站点 B
goaccess /var/log/site-b/access.log \
  -o /var/www/goaccess/b/report.html \
  --log-format=COMBINED \
  --real-time-html \
  --addr=127.0.0.1 --port=7891 \
  --ws-url=ws://stats-b.example.com/ws \
  --daemonize
```

### 8.4 Systemd 服务管理（推荐）

为每个站点创建独立的 systemd 服务，便于管理和自动重启：

```ini
# /etc/systemd/system/goaccess-site-a.service
[Unit]
Description=GoAccess real-time report for Site A
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/goaccess /var/log/site-a/access.log \
  -o /var/www/goaccess/a/report.html \
  --log-format=COMBINED \
  --real-time-html \
  --addr=127.0.0.1 --port=7890 \
  --ws-url=ws://stats-a.example.com/ws
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
# 启用并启动服务
sudo systemctl daemon-reload
sudo systemctl enable goaccess-site-a
sudo systemctl start goaccess-site-a

# 查看状态
sudo systemctl status goaccess-site-a
```

### 8.5 HTTPS/WSS 配置

如果使用 HTTPS 访问报告，WebSocket 也需要使用 `wss://` 协议。有两种方式：

**方式一：Nginx 终止 TLS（推荐）**

Nginx 处理 SSL 证书，WebSocket 通过 `wss://` 连接：

```nginx
server {
    server_name stats.example.com;

    ssl_certificate     /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location /ws {
        proxy_pass http://127.0.0.1:7890;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }
}
```

GoAccess 启动时 `--ws-url` 使用 `wss://`：

```bash
goaccess access.log \
  -o /var/www/goaccess/report.html \
  --real-time-html \
  --addr=127.0.0.1 --port=7890 \
  --ws-url=wss://stats.example.com/ws
```

**方式二：GoAccess 直接启用 TLS**

需要编译时启用 `--with-openssl`：

```bash
goaccess access.log \
  -o /var/www/goaccess/report.html \
  --real-time-html \
  --addr=127.0.0.1 --port=7890 \
  --ssl-cert=/path/to/cert.pem \
  --ssl-key=/path/to/key.pem \
  --ws-url=wss://stats.example.com:7890
```

> **推荐方式一**，由 Nginx 统一管理 TLS 证书，更易维护且支持证书自动续期。

## 9. 故障排除与资源

### 9.1 常见问题

**Q: 日志解析后面板数据为空？**

检查日志格式是否匹配。使用 `-c` 参数启动交互式配置对话框重新选择格式，或在命令行中显式指定 `--log-format`。

**Q: 实时 HTML 报告无法连接 WebSocket？**

- 确认 WebSocket 端口（默认 `7890`）已开放
- 检查防火墙设置是否放行了该端口
- 如果使用反向代理（如 Nginx），需配置 WebSocket 代理转发

**Q: 中文或其他非 ASCII 字符显示异常？**

确保编译时启用了 `--enable-utf8` 选项，并且终端支持 UTF-8 编码。

**Q: 如何处理 IIS 日志格式？**

GoAccess 内置了通用格式选项，也可使用 [自动提取脚本](https://gist.github.com/soheilpro/a34957550b1bd7d42be2) 从 IIS 日志文件中自动提取格式。

**Q: 如何将 Nginx 的 `log_format` 转换为 GoAccess 格式？**

使用 [nginx2goaccess](https://github.com/stockrt/nginx2goaccess) 脚本进行自动转换。

### 9.2 性能参考

| 指标 | 数值 |
|------|------|
| 解析速度 | ~100,000 行/秒（i7-8700K, 16GB RAM） |
| 内存占用 | ~134 MiB / 340 万行（全功能开启） |
| 大数据集 | ~4 亿行（74GB）约 1 小时 20 分钟，消耗 ~12GB RAM |

> 使用 `-q` 参数移除查询字符串可显著降低内存消耗。

### 9.3 官方资源

| 资源 | 链接 |
|------|------|
| 官方网站 | https://goaccess.io |
| GitHub 仓库 | https://github.com/allinurl/goaccess |
| Man Page（完整手册） | https://goaccess.io/man |
| FAQ | https://goaccess.io/faq |
| 下载页面 | https://goaccess.io/download |
| 问题反馈 | https://github.com/allinurl/goaccess/issues |

### 9.4 推荐教程

- [GoAccess 详细教程](https://arnaudr.io/2020/08/10/goaccess-14-a-detailed-tutorial/) — 涵盖安装、配置和高级用法的全面指南

---

> **文档信息**：基于 GoAccess 官方文档整理，当前覆盖版本 v1.9.4 ~ v1.10.2。最后更新：2026-05-20。
