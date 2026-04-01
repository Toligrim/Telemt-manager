# Telemt Manager

[Русский](./README.md) | [English](./README.en.md)

`Telemt Manager` 是一个用于在 Linux VPS 上安装和管理 Telemt 的交互式 Bash 脚本。

本项目基于 [An0nX/telemt-docker](https://github.com/An0nX/telemt-docker) 构建，并使用 `whn0thacked/telemt-docker:latest` Docker 镜像作为部署基础。

它可以帮助你：

- 一次运行完成 Telemt 初始安装
- 生成 `32` 位十六进制 secret
- 配置 TLS 伪装域名
- 创建和管理 `systemd` 单元
- 启用或禁用自动更新
- 更新配置、查看状态和日志
- 创建和恢复备份

## 功能

安装完成后，交互式菜单提供以下操作：

1. 更新 Telemt
2. 重新配置 Telemt
3. 完全停止 Telemt 和所有相关 `systemd` 单元
4. 完全删除 Telemt
5. 启用自动更新
6. 禁用自动更新
7. 显示当前状态
8. 显示当前配置
9. 重启 Telemt
10. 查看日志
11. 仅生成新的 secret，不修改其他配置
12. 仅修改伪装域名
13. 检查伪装域名是否可访问
14. 检查端口及冲突
15. 同步管理脚本本身
16. 创建配置备份
17. 恢复配置备份

所有主要操作也都支持通过 CLI 参数执行。

## 运行要求

脚本适用于满足以下条件的 Linux VPS：

- 使用 `systemd`
- 拥有 `root` 权限，或使用带 `sudo` 权限的用户
- 为 Telemt 开放一个入站端口，通常为 `443`

推荐系统：

- Ubuntu 22.04+
- Debian 12+

如果系统中缺少 `docker` 和 `docker compose`，`telemt-manager.sh` 会在 Ubuntu/Debian 上自动尝试安装它们，然后继续完成 Telemt 安装。

## 新 VPS 的基础安全建议

这部分不是运行脚本的硬性要求，但如果你的 VPS 是刚创建的，强烈建议先完成这些基础加固步骤。

### 1. 更新系统

对于 Ubuntu 或 Debian：

```bash
sudo apt update && sudo apt upgrade -y
```

### 2. 创建独立的 sudo 用户

不要长期直接使用 `root`。

```bash
adduser telemt
usermod -aG sudo telemt
```

然后切换到该用户：

```bash
su - telemt
```

### 3. 配置 SSH 密钥登录

在你的本地电脑上执行：

```bash
ssh-keygen -t ed25519
ssh-copy-id telemt@YOUR_SERVER_IP
```

在禁用密码登录之前，请先确认密钥登录正常可用。

### 4. 禁用密码登录，并尽量禁用 root 登录

编辑 SSH 配置：

```bash
sudo nano /etc/ssh/sshd_config
```

推荐配置：

```text
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

修改后重启 SSH：

```bash
sudo systemctl restart ssh
```

### 5. 启用防火墙

以 `ufw` 为例：

```bash
sudo apt install -y ufw
sudo ufw allow OpenSSH
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

如果你使用的 Telemt 端口不是 `443`，请放行对应端口。

### 6. 安装 Fail2ban

```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```

### 7. 启用自动安全更新

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 8. 检查系统时间和时区

```bash
timedatectl
```

如有需要：

```bash
sudo timedatectl set-timezone Europe/Moscow
```

### 9. 不要暴露不必要的服务

至少请确认：

- `22/tcp` 仅用于 SSH
- `443/tcp` 或你选择的 Telemt 端口
- 不要在公网暴露 `9091` 和 `9090`，除非你明确需要

## 在 Ubuntu/Debian 上安装 Docker

如果 Docker 已安装，可以跳过本节。

默认情况下，当脚本检测不到 Docker 时，`telemt-manager.sh` 会在 Ubuntu/Debian 上自动安装它。本节仅适用于你希望提前手动安装 Docker 的情况。

### 方案 1：通过系统仓库快速安装

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
```

检查：

```bash
docker --version
docker compose version
```

### 方案 2：将当前用户加入 docker 组

这样可以在不使用 `sudo` 的情况下运行 Docker：

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

## 在 VPS 上安装 Telemt Manager

### 步骤 1：连接到服务器

```bash
ssh telemt@YOUR_SERVER_IP
```

或者：

```bash
ssh root@YOUR_SERVER_IP
```

### 步骤 2：克隆仓库

```bash
git clone git@github.com:Toligrim/Telemt-manager.git
cd Telemt-manager
```

如果你更喜欢 HTTPS：

```bash
git clone https://github.com/Toligrim/Telemt-manager.git
cd Telemt-manager
```

### 步骤 3：赋予脚本执行权限

```bash
chmod +x telemt-manager.sh
```

### 步骤 4：运行安装脚本

```bash
./telemt-manager.sh
```

如果系统中尚未安装 Telemt，脚本会进入首次安装流程。

如果系统中尚未安装 Docker，脚本会：

- 检测到缺少 `docker` 和 `docker compose`
- 在 Ubuntu/Debian 上安装 `docker.io` 和 `docker-compose-plugin`
- 启用并启动 `docker.service`
- 然后继续 Telemt 的安装流程

脚本会询问你：

- TLS 伪装域名，例如 `google.com`
- 用于 `tg://proxy` 链接的服务器公网域名或 IP
- Telemt 端口，通常为 `443`
- 本地 API 端口，默认 `9091`
- 是否启用 metrics 端口
- proxy 链接中的用户名

随后脚本将会：

- 生成新的 `32` 位十六进制 secret
- 创建 `/opt/telemt`
- 写入配置文件和 `docker-compose.yml`
- 创建 `systemd` 单元
- 启动 Telemt
- 输出可直接使用的 `tg://proxy` 链接

## 文件位置

安装完成后，会使用以下路径：

- `/opt/telemt/telemt-config/telemt.toml`
- `/opt/telemt/docker-compose.yml`
- `/opt/telemt/install.env`
- `/opt/telemt/telemt-manager.sh`
- `/opt/telemt/backups/`
- `/etc/systemd/system/telemt.service`
- `/etc/systemd/system/telemt-autoupdate.service`
- `/etc/systemd/system/telemt-autoupdate.timer`

## 基本使用

### 打开交互式菜单

```bash
./telemt-manager.sh --menu
```

或者直接：

```bash
./telemt-manager.sh
```

如果 Telemt 已安装，脚本将直接打开菜单。

### 更新 Telemt

```bash
./telemt-manager.sh --update
```

### 重新执行完整配置流程

```bash
./telemt-manager.sh --reconfigure
```

### 启用自动更新

```bash
./telemt-manager.sh --enable-autoupdate
```

### 禁用自动更新

```bash
./telemt-manager.sh --disable-autoupdate
```

### 查看状态

```bash
./telemt-manager.sh --status
```

### 查看当前配置

```bash
./telemt-manager.sh --show-config
```

### 查看日志

```bash
./telemt-manager.sh --logs
```

### 生成新的 secret

```bash
./telemt-manager.sh --rotate-secret
```

### 仅修改伪装域名

```bash
./telemt-manager.sh --change-mask-domain
```

### 检查伪装域名

```bash
./telemt-manager.sh --check-mask-domain
```

### 检查端口冲突

```bash
./telemt-manager.sh --check-ports
```

### 手动创建备份

```bash
./telemt-manager.sh --backup
```

### 恢复备份

```bash
./telemt-manager.sh --restore-backup
```

## 自动更新的工作方式

启用自动更新后，脚本会创建一个 `systemd` timer，定期检查 Docker 镜像是否有新版本。

如果发现新镜像：

- 执行 `docker compose pull`
- 重新启动整个栈

如果没有更新：

- 保持当前栈继续运行

检查 timer 状态：

```bash
systemctl status telemt-autoupdate.timer
```

## 如何完全删除 Telemt

通过菜单：

- 选择第 `4` 项

或者通过 CLI：

```bash
./telemt-manager.sh --purge
```

该操作会：

- 停止容器
- 删除 `systemd` 单元
- 删除 `/opt/telemt`

## 故障排查

### Telemt 无法启动

请检查：

```bash
./telemt-manager.sh --status
./telemt-manager.sh --logs
```

### 端口已被占用

请检查：

```bash
./telemt-manager.sh --check-ports
```

### 伪装域名无法访问

请检查：

```bash
./telemt-manager.sh --check-mask-domain
```

### 自动更新没有生效

请检查：

```bash
systemctl status telemt-autoupdate.timer
systemctl status telemt-autoupdate.service
```

## 重要说明

- 本项目并不是 upstream `telemt-docker` 的替代品，而是构建在其之上的管理层。
- 脚本在重写配置前会先自动创建备份。
- 除非你明确需要，否则不要将 API 和 metrics 端口暴露到公网。
- 如果你使用小于 `1024` 的端口，容器将以能够绑定特权端口的能力运行。

## 致谢

- 部署基础：[An0nX/telemt-docker](https://github.com/An0nX/telemt-docker)
- Telemt 核心项目：[telemt/telemt](https://github.com/telemt/telemt)
