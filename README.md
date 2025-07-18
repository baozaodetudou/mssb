# Mosdns + Singbox/Mihomo 虚拟机分流代理项目（纯自用版本）

## 项目简介

> ⚠️ **重要提示**：本项目为自用版本，可能存在部分 bug，敬请见谅。
> 
> ⚠️ **版本更新**：2025.6.23 之前的是 v1 版本，现在是 v2 版本。
> 如果你当前使用的是 v1 版本，建议先停止所有服务并手动删除目录 `/mssb` 后重新安装本脚本。

### 分支说明

- **主分支**：Mosdns + Singbox/Mihomo - [https://github.com/baozaodetudou/mssb](https://github.com/baozaodetudou/mssb)
- **次分支**：adguard + Mosdns + Singbox/Mihomo - [https://github.com/baozaodetudou/mssb/tree/ami](https://github.com/baozaodetudou/mssb/tree/ami)
- 次分支还处于v1

### 项目概述

封装 `mosdns` 和 `singbox/mihomo` 两个服务，旨在实现高效的分流代理功能。

**核心特性：**

- `mosdns` 使用 53 端口对外提供 DNS 服务
- `singbox/mihomo` 使用 6666 端口与 `mosdns` 对接，代理转发使用TProxy: 7896以及 redirect: 7877
- 代理访问通过 `mosdns` 转发到 `singbox/mihomo`，并启用 `fakeip` 模式（使用网段 28.0.0.0/8），需在主路由上添加相应静态路由
- 文档参考：[fakeip.md](docs/fakeip.md)

**集成组件：**

- `filebrowser`：用于配置文件的可视化管理
- `zashboard`：`singbox/mihomo` 的 Web UI 界面

感谢各位大佬的贡献，特别是 PH 和 hero 两位大佬的支持。

### 系统架构图

![系统架构图](docs/png/fl.png)

## 项目功能

- ✅ **进程管理**：通过 `supervisor` 管理服务进程
- ✅ **高效分流代理**：`mosdns` + `singbox/mihomo` 分流代理架构
- ✅ **可视化管理**：使用 `filebrowser` 管理配置文件
- ✅ **前端界面**：通过 `zashboard` 提供友好的配置界面

## 系统架构

![架构图](docs/png/drawio.png)

```plaintext
+------------------+           +----------------------+
|     filebrowser  |           |       zashboard      |
+------------------+           +----------------------+
           |                               |
+------------------+           +----------------------+
|      mosdns      | --------> |    singbox/mihomo    |
+------------------+           +----------------------+
```

## 服务端口分配

| 服务 | 端口 | 描述                         |
|------|------|----------------------------|
| filebrowser | 8088 | 文件管理界面                     |
| supervisor | 9001 | 进程管理界面                     |
| mosdns | 53 | DNS 服务入口                   |
| mosdns | 7777 | 解析节点域名                     |
| mosdns | 8888 | sing-box使用                 |
| mosdns | 2222 | 内部的国内dns服务器                |
| mosdns | 3333 | 转发国外请求到内部带过期缓存的服务          |
| mosdns | 4444 | 带过期缓存的内部使用/外部使用的国外dns服务器   |
| mosdns | 5656 | 主分流服务器                     |
| http代理 | 7890 | singbox/mihomo 端口          |
| socks5代理 | 7891 | singbox/mihomo 端口          |
| 混合端口 | 7892 | singbox/mihomo 端口          |
| DNS 接口 | 6666 | singbox/mihomo 与 mosdns 对接 |
| TProxy透明代理 | 7896 | nftable 策略使用               |
| redirect代理 | 7877 | nftable 策略使用  |
| Web UI (zashboard) | 9090 | singbox/mihomo Web 界面      |

## 🎉 服务 Web 访问路径

- 🌐 **Mosdns 统计界面**：`http://{Debian主机IP}:9099/graphic`
- 📦 **Supervisor 管理界面**：`http://{Debian主机IP}:9001`
- 🗂️ **文件管理服务 Filebrowser**：`http://{Debian主机IP}:8088`
- 🕸️ **Sing-box/Mihomo 面板 UI**：`http://{Debian主机IP}:9090/ui`

## 安装方法

### 适用于 Debian 12 系统

```bash
# 若主机无代理，可通过导出局域网代理环境变量临时加速安装
# 示例：使用 Mac 上的 surge 或 Windows 上的 mihomo 开启局域网代理
export https_proxy=http://192.168.12.239:6152
export http_proxy=http://192.168.12.239:6152
export all_proxy=socks5://192.168.12.239:6153

# 拉取仓库并安装（包含安装、卸载、启动、停止功能）
git clone --depth=1 https://github.com/baozaodetudou/mssb.git && cd mssb && bash install.sh
```

### 开发分支（不稳定慎用）

```bash
# 若主机无代理，可通过导出局域网代理环境变量临时加速安装
# 示例：使用 Mac 上的 surge 或 Windows 上的 mihomo 开启局域网代理
export https_proxy=http://192.168.12.239:6152
export http_proxy=http://192.168.12.239:6152
export all_proxy=socks5://192.168.12.239:6153

# 拉取仓库并安装（包含安装、卸载、启动、停止功能）
git clone https://github.com/baozaodetudou/mssb.git && cd mssb && git checkout dev && bash install.sh
```

### 查看日志

查看所有服务日志：

```bash
tail -f /var/log/supervisor/*.log
```

## 使用说明

### 1. filebrowser

- **端口**：8088
- **登录设置**：有些人不想要登录可以执行下边的命令

```shell
# 取消用户密码登录功能
supervisorctl stop filebrowser && filebrowser config set --auth.method=noauth -c /mssb/fb/fb.json -d /mssb/fb/fb.db && supervisorctl start filebrowser

# 恢复用户密码登录功能
supervisorctl stop filebrowser && filebrowser config set --auth.method=json -c /mssb/fb/fb.json -d /mssb/fb/fb.db && supervisorctl start filebrowser
```

### 2. supervisor

- **端口**：9001

### 3. mosdns 统计页面

- **地址**：`http://{Debian主机IP}:9099/graphic`

### 4. 功能说明

- `mosdns`：提供 DNS 解析与缓存加速
- `singbox`：提供 SOCKS5 和透明代理
- `zashboard`：配置前端界面，状态显示

### 5. 使用方法

#### 基本设置

- 安装完成后，将主路由的 DNS 设置为 Debian 主机的 IP

#### 设备分流控制

mosdns 可以选择是否启用指定 client 科学开关（默认启用）：

- **规则文件**：`switch1.txt-switch9.txt`，在 `rule` 文件夹内
- **配置文件**：`/mssb/mosdns/sub_config/switch.yaml` 中 `switch2` 
  - `'A'` - 启用
  - `'B'` - 不启用
- **UI 界面**：也可修改，重启不会失效 `/mssb/mosdns/rule/switch2.txt`

**分流规则：**
- **不启用**：全部设备都会走科学
- **启用**：只有 `client_ip.txt` 文件里的内网设备走科学

**设备分流控制**：将需要走代理的设备 IP 添加到 `client_ip.txt` 文件中：

```text
/mssb/mosdns/client_ip.txt
```

文件中未列出的 IP 只使用 mosdns 加速，不通过代理。

#### 其他配置

- **白名单**：强制用国内 DNS 解析，有过期缓存
- **DDNS 域名**：是自己的域名，没过期缓存

由于 mosdns 存在缓存，针对 DDNS 域名需要加进 `ddnslist.txt`，不然由于 IP 更新缓存不更新会导致访问失败：

```text
/mssb/mosdns/ddnslist.txt
```

#### 开关配置

- **屏蔽无解析结果的 A、AAAA 请求及黑名单**
  - 配置文件：`/mssb/mosdns/sub_config/switch.yaml` 中 `switch1`
  - UI 界面：也可修改，重启不会失效 `/mssb/mosdns/rule/switch1.txt`
  - `'A'` - 启用，`'B'` - 不启用

- **泄露版本/不泄露版本开关**
  - 配置文件：`/mssb/mosdns/sub_config/switch.yaml` 中 `switch3`
  - UI 界面：也可修改，重启不会失效 `/mssb/mosdns/rule/switch3.txt`
  - `'A'` - 泄露，`'B'` - 不泄露

> **注意**：PH 佬在界面加了软启动，我这个项目会监听配置文件进行硬启动，所以没啥特殊情况还是建议改配置文件稳妥，UI 只负责显示。

### 6. 路由配置

请在主路由中添加以下路由规则：

#### 主路由 DNS 设置 / DHCP DNS 设置

| 配置项 | 值 |
|--------|-----|
| DNS 服务器 | `{Debian主机IP}` |

#### MosDNS 和 Mihomo fakeip 路由

| 目标地址 | 网关 |
|----------|------|
| 28.0.0.0/8 | `{Debian主机IP}` |
| 8.8.8.8/32 | `{Debian主机IP}` |
| 1.1.1.1/32 | `{Debian主机IP}` |

#### Telegram 路由

| 目标地址 | 网关 |
|----------|------|
| 149.154.160.0/22 | `{Debian主机IP}` |
| 149.154.164.0/22 | `{Debian主机IP}` |
| 149.154.172.0/22 | `{Debian主机IP}` |
| 91.108.4.0/22 | `{Debian主机IP}` |
| 91.108.20.0/22 | `{Debian主机IP}` |
| 91.108.56.0/22 | `{Debian主机IP}` |
| 91.108.8.0/22 | `{Debian主机IP}` |
| 95.161.64.0/22 | `{Debian主机IP}` |
| 91.108.12.0/22 | `{Debian主机IP}` |
| 91.108.16.0/22 | `{Debian主机IP}` |
| 67.198.55.0/24 | `{Debian主机IP}` |
| 109.239.140.0/24 | `{Debian主机IP}` |

#### Netflix 路由

| 目标地址 | 网关 |
|----------|------|
| 207.45.72.0/22 | `{Debian主机IP}` |
| 208.75.76.0/22 | `{Debian主机IP}` |
| 210.0.153.0/24 | `{Debian主机IP}` |
| 185.76.151.0/24 | `{Debian主机IP}` |

## 项目来源和参考

- [https://github.com/herozmy/StoreHouse/tree/latest](https://github.com/herozmy/StoreHouse/tree/latest)
- 感谢英雄佬的脚本教程
- 感谢 Phil Horse 大佬的 mosdns 的优化和功能更新
- 感谢 Jimmy Dada 大佬提供 mosdns 前端页面
- 感谢 mosdns/singbox/mihomo 的各位开发大佬们

感谢所有提供支持与灵感的开源作者！
