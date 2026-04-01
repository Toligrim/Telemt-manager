# Telemt Manager

[Русский](./README.md) | [中文](./README.zh-CN.md)

`Telemt Manager` is an interactive Bash script for installing and managing Telemt on a Linux VPS.

This project is built on top of [An0nX/telemt-docker](https://github.com/An0nX/telemt-docker) and uses the `whn0thacked/telemt-docker:latest` Docker image as its deployment base.

`Telemt Manager` is for cases where you do not want to assemble Telemt on a VPS by hand and instead want one clear workflow to install, configure, update, inspect, and maintain the instance through a single interactive script.

## Description

It helps you:

- install Telemt from scratch in a single run
- generate a `32`-character hex secret
- configure a TLS camouflage domain
- create and manage `systemd` units
- enable or disable auto-update
- update config, inspect status, and read logs
- create and restore backups

After installation, the interactive menu provides:

1. Update Telemt
2. Reconfigure Telemt
3. Fully stop Telemt and all related `systemd` units
4. Remove Telemt completely
5. Enable auto-update
6. Disable auto-update
7. Show current status
8. Show current config
9. Restart Telemt
10. Show logs
11. Generate a new secret without changing anything else
12. Change only the camouflage domain
13. Check camouflage domain availability
14. Check ports and conflicts
15. Sync the manager script itself
16. Create a config backup
17. Restore a config backup

All key actions are also available through CLI flags.

## Quick Start

Minimal install flow for a fresh VPS:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/Toligrim/Telemt-manager.git
cd Telemt-manager
chmod +x telemt-manager.sh
./telemt-manager.sh
```

If Docker is not installed yet, the script will try to install it automatically on a supported OS and then continue the Telemt setup.

## Install and Use Telemt

### Requirements

The script is intended for a Linux VPS with:

- `systemd`
- `root` access or a user with `sudo`
- an inbound port for Telemt, typically `443`

Supported OS targets for Docker auto-install:

- Ubuntu
- Debian
- Fedora
- RHEL
- CentOS Stream
- Rocky Linux
- AlmaLinux

If `docker` and `docker compose` are missing, `telemt-manager.sh` will try to install them automatically on a supported OS and then continue the Telemt setup.

Supported Docker auto-install targets:

- Ubuntu via the official Docker `apt` repository
- Debian via the official Docker `apt` repository
- Fedora via the official Docker `dnf` repository
- RHEL, CentOS Stream, Rocky Linux, and AlmaLinux via the official Docker `dnf` repository

If the OS is not supported, the script exits with a clear error instead of guessing installation commands.

### Step 1. Connect to the server

```bash
ssh telemt@YOUR_SERVER_IP
```

Or:

```bash
ssh root@YOUR_SERVER_IP
```

### Step 2. Install Git if it is not available yet

For Ubuntu or Debian:

```bash
sudo apt update
sudo apt install -y git
```

For Fedora:

```bash
sudo dnf install -y git
```

For RHEL, Rocky, AlmaLinux, and CentOS Stream:

```bash
sudo dnf install -y git
```

### Step 3. Clone the repository

```bash
git clone git@github.com:Toligrim/Telemt-manager.git
cd Telemt-manager
```

Or via HTTPS:

```bash
git clone https://github.com/Toligrim/Telemt-manager.git
cd Telemt-manager
```

### Step 4. Make the script executable

```bash
chmod +x telemt-manager.sh
```

### Step 5. Run the installer

```bash
./telemt-manager.sh
```

If Telemt is not installed yet, the script will start the first-time installation flow.

If Docker is not installed yet, the script will:

- detect the OS, version, architecture, and package manager
- choose the correct Docker installation strategy
- configure the official Docker repository for your platform
- install Docker Engine and the Docker Compose plugin
- enable and start `docker.service`
- verify that `docker`, `docker compose`, and the Docker daemon actually work
- continue the Telemt installation automatically

During setup, the script will ask for:

- a TLS camouflage domain
- the public domain or IP of your server for the `tg://proxy` link
- the Telemt port, typically `443`
- a local API port, default `9091`
- whether to enable a metrics port
- a username for the proxy link

After that, the script will:

- generate a new `32`-character hex secret
- create `/opt/telemt`
- write the config and `docker-compose.yml`
- create `systemd` units
- start Telemt
- print a ready-to-use `tg://proxy` link

### File locations

After installation, the following paths are used:

- `/opt/telemt/telemt-config/telemt.toml`
- `/opt/telemt/docker-compose.yml`
- `/opt/telemt/install.env`
- `/opt/telemt/telemt-manager.sh`
- `/opt/telemt/backups/`
- `/etc/systemd/system/telemt.service`
- `/etc/systemd/system/telemt-autoupdate.service`
- `/etc/systemd/system/telemt-autoupdate.timer`

### Basic usage

Open the interactive menu:

```bash
./telemt-manager.sh --menu
```

Or simply:

```bash
./telemt-manager.sh
```

If Telemt is already installed, the menu will open.

Key commands:

| Action | Command |
| --- | --- |
| Open menu | `./telemt-manager.sh --menu` |
| Update Telemt | `./telemt-manager.sh --update` |
| Re-run full config | `./telemt-manager.sh --reconfigure` |
| Enable auto-update | `./telemt-manager.sh --enable-autoupdate` |
| Disable auto-update | `./telemt-manager.sh --disable-autoupdate` |
| Show status | `./telemt-manager.sh --status` |
| Show current config | `./telemt-manager.sh --show-config` |
| Show logs | `./telemt-manager.sh --logs` |
| Generate a new secret | `./telemt-manager.sh --rotate-secret` |
| Change only the camouflage domain | `./telemt-manager.sh --change-mask-domain` |
| Check the camouflage domain | `./telemt-manager.sh --check-mask-domain` |
| Check port conflicts | `./telemt-manager.sh --check-ports` |
| Create a backup | `./telemt-manager.sh --backup` |
| Restore a backup | `./telemt-manager.sh --restore-backup` |

### How auto-update works

When auto-update is enabled, the script creates a `systemd` timer that periodically checks for a newer Docker image.

If a new image is found:

- `docker compose pull` is executed
- the stack is restarted

If there is no update:

- the stack is simply kept running

Check timer status:

```bash
systemctl status telemt-autoupdate.timer
```

### How to remove Telemt completely

Through the menu:

- choose item `4`

Or via CLI:

```bash
./telemt-manager.sh --purge
```

This action:

- stops containers
- removes `systemd` units
- removes `/opt/telemt`

### Troubleshooting

Telemt does not start:

```bash
./telemt-manager.sh --status
./telemt-manager.sh --logs
```

A port is already in use:

```bash
./telemt-manager.sh --check-ports
```

The camouflage domain is unavailable:

```bash
./telemt-manager.sh --check-mask-domain
```

Auto-update does not work:

```bash
systemctl status telemt-autoupdate.timer
systemctl status telemt-autoupdate.service
```

## Recommendations

### Basic hardening for a new VPS

This section is optional for running the script, but strongly recommended for a freshly created VPS.

#### 1. Update the system

For Ubuntu or Debian:

```bash
sudo apt update && sudo apt upgrade -y
```

#### 2. Create a dedicated sudo user

Do not work as `root` all the time.

```bash
adduser telemt
usermod -aG sudo telemt
```

Then switch to that user:

```bash
su - telemt
```

#### 3. Configure SSH key login

On your local machine:

```bash
ssh-keygen -t ed25519
ssh-copy-id telemt@YOUR_SERVER_IP
```

Make sure SSH key login works before disabling password authentication.

#### 4. Disable password login and, if possible, root login

Edit the SSH config:

```bash
sudo nano /etc/ssh/sshd_config
```

Recommended values:

```text
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

Then restart SSH:

```bash
sudo systemctl restart ssh
```

#### 5. Enable a firewall

Example with `ufw`:

```bash
sudo apt install -y ufw
sudo ufw allow OpenSSH
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

If you use a different Telemt port, allow that port instead of `443`.

#### 6. Install Fail2ban

```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```

#### 7. Enable automatic security updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

#### 8. Verify time and timezone

```bash
timedatectl
```

If needed:

```bash
sudo timedatectl set-timezone Europe/Moscow
```

#### 9. Do not expose unnecessary services

At minimum, verify:

- `22/tcp` only for SSH
- `443/tcp` or your chosen Telemt port
- do not expose `9091` and `9090` publicly unless you explicitly need them

### If you want to install Docker manually in advance

By default, `telemt-manager.sh` can install Docker from the official Docker repositories when it is not found. This section is only needed if you prefer to install Docker manually in advance.

For Ubuntu or Debian:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
```

Check:

```bash
docker --version
docker compose version
```

To run Docker without `sudo`:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

## Credits

- Deployment base: [An0nX/telemt-docker](https://github.com/An0nX/telemt-docker)
- Core Telemt project: [telemt/telemt](https://github.com/telemt/telemt)
