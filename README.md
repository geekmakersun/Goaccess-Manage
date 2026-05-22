# GoAccess 多站点管理系统

## 📋 项目简介

这是一个为**宝塔面板**环境设计的**GoAccess 自动化管理系统**，支持多站点日志分析、数据持久化和自动化报告生成。

### ✨ 核心特性

- 🚀 **自动化安装**：从源代码编译安装最新版 GoAccess
- 🌐 **多站点支持**：通过配置文件管理多个站点，互不干扰
- 🌍 **地理位置分析**：集成免费版 GeoLite2 数据库
- 📊 **HTML 报告**：生成美观的可视化报告
- 🔄 **自动化更新**：支持定时任务自动更新报告和 GeoIP 数据库
- 💻 **跨平台兼容**：支持 Debian/Ubuntu、CentOS/RHEL、Arch、openSUSE 等主流 Linux 发行版

## 📁 目录结构

```
GoAccess-管理/                    # 🎯 项目根目录
├── README.md                    # 📖 主文档
├── CHANGELOG.md                 # 📝 更新日志
├── LICENSE                      # 📜 许可证文件
├── .gitattributes               # Git 属性配置
│
├── 文档/                         # 📖 文档目录
│   ├── GoAccess快速入门指南.md   # 📘 快速入门教程
│   └── GeoIP/                   # GeoIP 相关文档
│       ├── README.md            # GeoIP 说明文档
│       └── 使用说明.md           # GeoIP 使用说明
│
├── 脚本/                         # 🔧 脚本目录
│   ├── 安装GoAccess.sh          # 安装脚本
│   ├── 卸载GoAccess.sh          # 卸载脚本
│   ├── 分析所有站点.sh           # 分析脚本（批量处理）
│   ├── 配置审计系统.sh          # 审计配置脚本
│   └── GeoIP/                   # GeoIP 相关脚本
│       └── 更新GeoLite2.sh      # GeoIP 更新脚本
│
├── 配置/                         # ⚙️ 配置目录
│   ├── 配置模板.conf            # 📋 配置模板
│   └── 站点配置/                # 📝 站点配置文件目录
│       └── .gitkeep
│
├── 数据/                         # 💾 数据目录
│   └── GeoIP/                   # GeoIP 数据库
│       ├── GeoLite2-City.mmdb   # 国家/地区数据库
│       ├── GeoLite2-ASN.mmdb    # ASN 数据库
│       ├── GeoIP.version        # 版本信息
│       └── 日志/                # GeoIP 日志
│           ├── GeoIP更新日志.log
│           └── 审计日志.log
│
└── 日志/                         # 📝 日志目录
    └── .gitkeep

/www/wwwroot/
└── 您的网站/                     # 🌐 各站点目录
    └── site-log.html            # 📊 访问报告
```

## 🚀 快速开始

### 1. 安装 GoAccess

```bash
cd /www/wwwroot/GoAccess-管理
sudo ./脚本/安装GoAccess.sh
```

#### 版本检查功能
- 脚本会自动检查系统中已安装的 GoAccess 版本
- 如果已安装最新版本，会自动跳过安装过程
- 如果已安装更高版本，会提示用户确认是否继续安装旧版本
- 支持 `--force` 参数强制重新安装：
```bash
sudo ./脚本/安装GoAccess.sh --force
```

### 2. 创建站点配置

在 **配置/站点配置** 目录中创建配置文件：

```bash
cd /www/wwwroot/GoAccess-管理/配置/站点配置
cp ../配置模板.conf 我的网站.conf
nano 我的网站.conf
```

### 3. 生成报告

```bash
cd /www/wwwroot/GoAccess-管理
# 推荐以 www 用户运行（与网站运行身份一致，避免权限问题）
sudo -su www ./脚本/分析所有站点.sh
```

### 4. 查看报告

分析完成后，您可以通过以下方式查看报告：

1. **浏览器访问**：在浏览器中访问 `https://您的域名/site-log.html`
2. **宝塔面板**：在宝塔面板的网站目录中找到 `site-log.html` 文件并点击查看

### 5. 设置定时任务（宝塔面板）

```bash
# 每天凌晨 2 点自动分析所有站点（以 www 用户运行）
0 2 * * * cd /www/wwwroot/GoAccess-管理 && sudo -su www ./脚本/分析所有站点.sh

# 每月 1 号自动更新 GeoIP 数据库（需要 root）
0 0 1 * * cd /www/wwwroot/GoAccess-管理 && sudo ./脚本/GeoIP/更新GeoLite2.sh
```

## ⚠️ 重要：用户权限说明

本系统涉及两种运行模式，请注意区分：

| 脚本 | 需要权限 | 推荐运行用户 | 原因 |
|------|---------|------------|------|
| 脚本/安装GoAccess.sh | **必须 root** | root | 编译安装需要系统目录写入权限 |
| 脚本/GeoIP/更新GeoLite2.sh | **必须 root** | root | 需要更新 /usr/share/GeoIP 系统目录 |
| 脚本/分析所有站点.sh | **普通用户** | www | 生成的报告需要被网站用户访问 |

### 为什么分析脚本要用 www 用户运行？

1. **权限一致**：网站以 www 用户运行，生成的报告文件权限需要匹配
2. **日志访问**：日志文件归属 www 用户，其他用户可能无法读取
3. **避免权限问题**：以 root 运行会导致生成的文件被 root 独占，www 用户无法写入数据库

### 权限问题排查

如果遇到权限错误，请检查：

```bash
# 检查日志文件权限
ls -la /www/wwwlogs/您的域名.log

# 检查输出目录权限
ls -la /www/wwwroot/您的域名/
```

## 📖 详细文档

- [GoAccess快速入门指南.md](文档/GoAccess快速入门指南.md) - 快速入门教程
- [CHANGELOG.md](CHANGELOG.md) - 更新日志
- [GeoIP使用说明](文档/GeoIP/使用说明.md) - GeoIP 数据库使用说明

## 🔧 配置说明

### 必需配置项

```bash
# 日志文件路径（支持通配符）
log-file=/www/wwwlogs/您的域名.log

# HTML 报告输出路径
output-html=/www/wwwroot/您的域名/site-log.html

# 日志格式（根据实际日志格式选择）
log-format=1  # Nginx 默认日志格式
# log-format=2 # Apache 默认日志格式
```

### 可选配置项

```bash
# HTML 报告标题
html-report-title=网站访问分析

# GeoIP 数据库路径
geoip-database=/usr/share/GeoIP/GeoLite2-City.mmdb

# 忽略爬虫（默认不启用，完整统计）
# ignore-crawlers=true
```

## 🎨 支持的系统

| 系统家族 | 发行版 | 包管理器 |
|---------|--------|---------|
| Debian | Debian, Ubuntu, Linux Mint | apt/apt-get |
| RHEL | CentOS, Rocky, AlmaLinux, RHEL, Fedora, OpenCloudOS | dnf/yum |
| Arch | Arch Linux, Manjaro | pacman |
| SUSE | openSUSE, SLES | zypper |

## 📜 许可证

本项目采用 MIT 许可证。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📧 联系方式

如有问题，请在 GitHub 上提交 Issue。

---

**最后更新：2026-05-22 15:47 (v3.3.0)**
