# Mihomo Tools (LXC Gateway Edition)

![Platform](https://img.shields.io/badge/Platform-Proxmox%20LXC-orange?style=flat-square)
![Language](https://img.shields.io/badge/Language-Bash-green?style=flat-square)
![Core](https://img.shields.io/badge/Core-Mihomo%20(Clash.Meta)-blue?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-lightgrey?style=flat-square)

**Mihomo Tools** 是一个专为 Linux 环境（特别是 Proxmox VE LXC 容器）设计的轻量级、模块化 Mihomo (Clash Meta) 管理脚本。

它可以帮助你快速搭建 **透明网关 (旁路由)**，自动处理复杂的 Linux 网络转发、NAT 规则、Docker 防火墙冲突以及内核更新。

---

## 🚀 核心功能

* **🛠️ 模块化设计**：功能分离，易于维护和扩展。
* **🌐 网关一键初始化**：自动开启 IP 转发、设置 NAT (Masquerade)、**暴力修复 Docker 导致的断网问题**。
* **🔄 自动更新**：支持一键更新 GeoIP/GeoSite 数据库和 Mihomo 内核（自动抓取 GitHub Latest）。
* **⚙️ 配置管理**：支持订阅链接下载、校验及自动重载。
* **🐕 看门狗 (Watchdog)**：自动监测进程和网络状态，崩溃/断网时自动重启并发送通知。
* **🗑️ 纯净卸载**：支持一键完全卸载脚本及残留数据。

---

## 📋 环境要求 (必读)

本项目推荐运行在 **Proxmox VE (PVE)** 的 **LXC 容器** 中（Debian 12/13 或 Ubuntu 22.04+）。

### ⚠️ PVE 宿主机预设 (TUN 模式开启)

在安装脚本之前，**必须**在 PVE 宿主机上为 LXC 容器开启 TUN 设备权限。

1.  登录 PVE **宿主机** Shell。
2.  编辑容器配置文件（将 `105` 替换为你的容器 ID）：
    ```bash
    nano /etc/pve/lxc/105.conf
    ```
3.  在文件末尾添加以下两行：
    ```text
    lxc.cgroup2.devices.allow: c 10:200 rwm
    lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
    ```
4.  **重启该 LXC 容器**。

---

## ⚡ 快速安装 / 升级

进入 LXC 容器终端，执行以下 **一键命令**：

```bash
git clone https://github.com/KyleYu2024/mihomo-tools.git /etc/mihomo-tools && bash /etc/mihomo-tools/install.sh

```
##  🖥 WEB UI配置  ##
1.  http://ip:7838  进入web ui
2.  可配置修改config.yaml
3.  配置webhook通知
4.  启动/停止/重启 mihomo
5.  快速跳转到ui面板

##  ⚙️ 高级设置  ##
在终端用mihomo-cli命令管理页面，可进行内核更新，程序卸载等高级操作
