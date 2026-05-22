# GeoIP 数据库目录

本目录用于存放 GeoIP 数据库文件，用于 GoAccess 的地理位置分析功能。

## 📦 数据库文件

- `GeoLite2-City.mmdb` - 国家/地区地理位置数据库（来源：Country.mmdb）
- `GeoLite2-ASN.mmdb` - 自治系统号数据库（来源：Country-asn.mmdb）

## 📥 自动更新（推荐）

### 数据源

本脚本使用 [Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip) 增强版数据库，相比原版 MaxMind GeoLite2 具有以下优势：

- ✅ 更新更频繁（每日更新）
- ✅ 数据更准确
- ✅ 包含中国大陆地区优化数据
- ✅ 提供 SHA256 校验文件确保完整性

### 使用更新脚本

本目录包含自动更新脚本 `更新GeoLite2.sh`，支持自动检测和更新数据库。

#### 基本用法

```bash
# 更新所有数据库
./更新GeoLite2.sh

# 只更新 Country 数据库（国家/地区）
./更新GeoLite2.sh -c

# 只更新 ASN 数据库
./更新GeoLite2.sh -a

# 强制更新（忽略版本检查）
./更新GeoLite2.sh -f

# 显示版本信息
./更新GeoLite2.sh -v

# 清理旧的备份文件
./更新GeoLite2.sh -C
```

#### 跨平台支持

脚本支持以下环境：
- ✅ Linux（CentOS/Ubuntu/Debian 等）
- ✅ Windows Git Bash
- ✅ macOS

#### 自动更新特性

- **自动获取版本**：通过 GitHub API 获取最新 release tag
- **SHA256 校验**：下载后验证文件完整性
- **原子更新**：先下载到临时文件，验证成功后再替换
- **自动备份**：更新前自动备份旧版本
- **清理机制**：自动清理超过 7 天的备份文件

## 📥 手动下载

### 从 GitHub Releases 下载

```bash
# 查看最新版本
# https://github.com/Loyalsoldier/geoip/releases/latest

# 下载 Country.mmdb（国家/地区数据库）
wget -O GeoLite2-City.mmdb https://github.com/Loyalsoldier/geoip/releases/download/{版本号}/Country.mmdb

# 下载 Country-asn.mmdb（ASN 数据库）
wget -O GeoLite2-ASN.mmdb https://github.com/Loyalsoldier/geoip/releases/download/{版本号}/Country-asn.mmdb

# 下载校验文件
wget https://github.com/Loyalsoldier/geoip/releases/download/{版本号}/Country.mmdb.sha256sum
wget https://github.com/Loyalsoldier/geoip/releases/download/{版本号}/Country-asn.mmdb.sha256sum
```

## 🔄 更新频率

Loyalsoldier/geoip 数据库每日更新，建议定期更新以获得准确的地理位置数据。

## ⚙️ 定时任务设置

### 宝塔面板定时任务

在宝塔面板添加计划任务：

```bash
# 每天凌晨 3 点自动更新
0 3 * * * cd /www/wwwroot/GoAccess-管理/GeoIP && ./更新GeoLite2.sh >> /var/log/GeoIP更新日志.log 2>&1
```

### Linux Crontab

```bash
# 编辑 crontab
crontab -e

# 添加定时任务（每天凌晨 3 点）
0 3 * * * cd /www/wwwroot/GoAccess-管理/GeoIP && ./更新GeoLite2.sh
```

## 📝 注意事项

- 本脚本使用 Loyalsoldier/geoip 增强版数据库，数据更准确
- 数据库文件较大（约 60-80 MB），请确保有足够的磁盘空间
- 如果不使用地理位置功能，可以不下载这些数据库文件
- 更新脚本会自动清理超过 7 天的备份文件
