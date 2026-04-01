# Telemt Manager

[English](./README.en.md) | [中文](./README.zh-CN.md)

`Telemt Manager` это интерактивный Bash-скрипт для установки и управления Telemt на Linux VPS.

Проект построен поверх [An0nX/telemt-docker](https://github.com/An0nX/telemt-docker) и использует Docker-образ `whn0thacked/telemt-docker:latest` как основу для развертывания.

`Telemt Manager` нужен, когда хочется не собирать Telemt на VPS вручную, а получить один понятный сценарий: установить, настроить, обновлять, проверять состояние и обслуживать инстанс через единый интерактивный скрипт.

## Описание

Скрипт помогает:

- установить Telemt с нуля за один запуск
- сгенерировать `32`-символьный hex secret
- задать домен для TLS-маскировки
- поднять `systemd` unit'ы
- включить или выключить автообновление
- обновлять конфиг, смотреть статус и логи
- делать backup и восстанавливать конфигурацию

После установки доступно интерактивное меню:

1. Обновить Telemt
2. Обновить конфиг
3. Выключить полностью Telemt и все `systemd` unit'ы
4. Удалить полностью Telemt
5. Включить автообновление
6. Выключить автообновление
7. Показать текущий статус
8. Показать текущий конфиг
9. Перезапустить Telemt
10. Показать логи
11. Сгенерировать новый secret без смены остального
12. Изменить только домен маскировки
13. Проверить доступность домена маскировки
14. Проверить порты и конфликты
15. Обновить сам скрипт-менеджер
16. Сделать backup конфига
17. Восстановить backup конфига

Также все основные действия доступны через CLI-флаги.

## Quick Start

Минимальный сценарий установки на чистом VPS:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/Toligrim/Telemt-manager.git
cd Telemt-manager
chmod +x telemt-manager.sh
./telemt-manager.sh
```

Если Docker ещё не установлен, скрипт сам попытается поставить его на поддерживаемой ОС и затем продолжит установку Telemt.

## Установка и использование Telemt

### Требования

Сценарий рассчитан на Linux VPS с:

- `systemd`
- доступом `root` или пользователем с `sudo`
- открытым входящим портом для Telemt, обычно `443`

Поддерживаемые ОС для автоустановки Docker:

- Ubuntu
- Debian
- Fedora
- RHEL
- CentOS Stream
- Rocky Linux
- AlmaLinux

Если `docker` и `docker compose` отсутствуют, `telemt-manager.sh` попытается установить их автоматически на поддерживаемой ОС и затем продолжит установку.

Поддерживаемые сценарии автоустановки Docker:

- Ubuntu через официальный Docker `apt` repository
- Debian через официальный Docker `apt` repository
- Fedora через официальный Docker `dnf` repository
- RHEL, CentOS Stream, Rocky Linux и AlmaLinux через официальный Docker `dnf` repository

Если ОС не поддерживается, скрипт завершится с понятной ошибкой и не будет пытаться угадывать команды установки.

### Шаг 1. Подключитесь к серверу

```bash
ssh telemt@YOUR_SERVER_IP
```

Или:

```bash
ssh root@YOUR_SERVER_IP
```

### Шаг 2. Установите Git, если его ещё нет

Для Ubuntu или Debian:

```bash
sudo apt update
sudo apt install -y git
```

Для Fedora:

```bash
sudo dnf install -y git
```

Для RHEL, Rocky, AlmaLinux, CentOS Stream:

```bash
sudo dnf install -y git
```

### Шаг 3. Клонируйте репозиторий

```bash
git clone git@github.com:Toligrim/Telemt-manager.git
cd Telemt-manager
```

Если удобнее по HTTPS:

```bash
git clone https://github.com/Toligrim/Telemt-manager.git
cd Telemt-manager
```

### Шаг 4. Сделайте скрипт исполняемым

```bash
chmod +x telemt-manager.sh
```

### Шаг 5. Запустите установку

```bash
./telemt-manager.sh
```

Если Telemt ещё не установлен, скрипт перейдёт в режим первичной установки.

Если в системе ещё нет Docker, скрипт:

- определит ОС, версию, архитектуру и пакетный менеджер
- выберет подходящий способ установки Docker
- подключит официальный Docker-репозиторий для вашей платформы
- установит Docker Engine и Docker Compose plugin
- включит и запустит `docker.service`
- проверит, что `docker`, `docker compose` и Docker daemon действительно работают
- продолжит установку Telemt автоматически

Во время настройки скрипт запросит:

- домен для TLS-маскировки
- публичный домен или IP вашего сервера для `tg://proxy` ссылки
- порт Telemt, обычно `443`
- локальный API-порт, по умолчанию `9091`
- включать ли metrics-порт
- имя пользователя для proxy-ссылки

После этого скрипт:

- сгенерирует новый `32`-hex-char secret
- создаст каталог `/opt/telemt`
- запишет конфиг и `docker-compose.yml`
- создаст `systemd` unit'ы
- запустит Telemt
- покажет готовую `tg://proxy` ссылку

### Где хранятся файлы

После установки используются такие пути:

- `/opt/telemt/telemt-config/telemt.toml`
- `/opt/telemt/docker-compose.yml`
- `/opt/telemt/install.env`
- `/opt/telemt/telemt-manager.sh`
- `/opt/telemt/backups/`
- `/etc/systemd/system/telemt.service`
- `/etc/systemd/system/telemt-autoupdate.service`
- `/etc/systemd/system/telemt-autoupdate.timer`

### Базовое использование

Открыть интерактивное меню:

```bash
./telemt-manager.sh --menu
```

Или просто:

```bash
./telemt-manager.sh
```

Если установка уже выполнена, откроется меню.

Ключевые команды:

| Действие | Команда |
| --- | --- |
| Открыть меню | `./telemt-manager.sh --menu` |
| Обновить Telemt | `./telemt-manager.sh --update` |
| Полностью обновить конфиг | `./telemt-manager.sh --reconfigure` |
| Включить автообновление | `./telemt-manager.sh --enable-autoupdate` |
| Выключить автообновление | `./telemt-manager.sh --disable-autoupdate` |
| Посмотреть статус | `./telemt-manager.sh --status` |
| Посмотреть текущий конфиг | `./telemt-manager.sh --show-config` |
| Посмотреть логи | `./telemt-manager.sh --logs` |
| Сгенерировать новый secret | `./telemt-manager.sh --rotate-secret` |
| Сменить только домен маскировки | `./telemt-manager.sh --change-mask-domain` |
| Проверить домен маскировки | `./telemt-manager.sh --check-mask-domain` |
| Проверить конфликты портов | `./telemt-manager.sh --check-ports` |
| Сделать backup | `./telemt-manager.sh --backup` |
| Восстановить backup | `./telemt-manager.sh --restore-backup` |

### Как работает автообновление

При включении автообновления скрипт создаёт `systemd timer`, который периодически запускает проверку нового Docker-образа.

Если новый образ найден:

- выполняется `docker compose pull`
- стек перезапускается

Если обновления нет:

- стек просто остаётся в рабочем состоянии

Проверить состояние timer:

```bash
systemctl status telemt-autoupdate.timer
```

### Как удалить Telemt полностью

Через меню:

- выберите пункт `4`

Или через CLI:

```bash
./telemt-manager.sh --purge
```

Это действие:

- останавливает контейнеры
- удаляет `systemd` unit'ы
- удаляет каталог `/opt/telemt`

### Диагностика проблем

Telemt не запускается:

```bash
./telemt-manager.sh --status
./telemt-manager.sh --logs
```

Порт уже занят:

```bash
./telemt-manager.sh --check-ports
```

Домен маскировки не отвечает:

```bash
./telemt-manager.sh --check-mask-domain
```

Не работает автообновление:

```bash
systemctl status telemt-autoupdate.timer
systemctl status telemt-autoupdate.service
```

## Рекомендации

### Базовая защита нового VPS

Этот блок не обязателен для запуска скрипта, но очень рекомендуется, если VPS только что создан.

#### 1. Обновите систему

Для Ubuntu или Debian:

```bash
sudo apt update && sudo apt upgrade -y
```

#### 2. Создайте отдельного пользователя с `sudo`

Не работайте постоянно под `root`.

```bash
adduser telemt
usermod -aG sudo telemt
```

Затем зайдите под этим пользователем:

```bash
su - telemt
```

#### 3. Настройте вход по SSH-ключу

На вашем локальном компьютере:

```bash
ssh-keygen -t ed25519
ssh-copy-id telemt@YOUR_SERVER_IP
```

Проверьте, что вход по ключу работает, прежде чем отключать пароль.

#### 4. Отключите вход по паролю и, по возможности, вход под `root`

Откройте конфиг SSH:

```bash
sudo nano /etc/ssh/sshd_config
```

Рекомендуемые настройки:

```text
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

После изменений перезапустите SSH:

```bash
sudo systemctl restart ssh
```

#### 5. Включите файрвол

Пример для `ufw`:

```bash
sudo apt install -y ufw
sudo ufw allow OpenSSH
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

Если вы используете другой порт для Telemt, откройте его вместо `443`.

#### 6. Установите Fail2ban

```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```

#### 7. Включите автоматические security-обновления

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

#### 8. Проверьте часовой пояс и время

```bash
timedatectl
```

При необходимости:

```bash
sudo timedatectl set-timezone Europe/Moscow
```

#### 9. Не держите лишние сервисы открытыми наружу

Минимум проверьте:

- `22/tcp` только для SSH
- `443/tcp` или ваш порт Telemt
- не открывайте `9091` и `9090` наружу без необходимости

### Если хотите установить Docker вручную заранее

По умолчанию `telemt-manager.sh` умеет сам поставить Docker из официального Docker-репозитория, если он не найден. Этот раздел нужен только если вы хотите установить Docker вручную заранее.

Для Ubuntu или Debian:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
```

Проверка:

```bash
docker --version
docker compose version
```

Чтобы запускать `docker` без `sudo`:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

## Благодарности

- Основа развертывания: [An0nX/telemt-docker](https://github.com/An0nX/telemt-docker)
- Основной проект Telemt: [telemt/telemt](https://github.com/telemt/telemt)
