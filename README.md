# dynmotd
Dynamic Message of the Day — a single Bash script that displays system information on login.

![Example](/data/screenshot.png)

## Features

- Color schemes (switchable via config block at top of script)
- Enable/disable individual information sections
- Per-host description, environment label and SLA tag
- Maintenance log with add/delete/list support
- Automatic dependency installation on `--install`
- `--update` for non-interactive binary updates (Ansible / Puppet / cron)
- Multi-distribution support (Debian, RHEL, SUSE, Arch, Alpine families)
- All IPv4 addresses + optional IPv6 from all active interfaces
- Load average (1m / 5m / 15m) and realistic available memory
- Optional Fail2Ban section (auto-hidden if fail2ban is not installed)
- Single self-contained shell script, no external dependencies beyond coreutils

## Supported Linux Distributions

Distributions actively supported (last ~10 years, 2015 – 2025):

### Debian family
| Distribution            | Versions / Releases          | Status              |
|-------------------------|------------------------------|---------------------|
| Debian                  | 8 (Jessie) – 12 (Bookworm)   | Tested              |
| Ubuntu                  | 16.04 LTS – 24.04 LTS        | Tested              |
| Linux Mint              | 18 – 22                      | Tested              |
| Raspberry Pi OS         | Bullseye, Bookworm           | Tested              |
| Kali Linux              | Rolling (2020+)              | Tested              |
| Pop!_OS                 | 20.04 – 22.04                | Compatible          |
| Elementary OS           | 6 – 7                        | Compatible          |
| MX Linux                | 19 – 23                      | Compatible          |
| Devuan                  | 3 – 5                        | Compatible          |
| Zorin OS                | 16 – 17                      | Compatible          |

### RHEL family
| Distribution            | Versions                     | Status              |
|-------------------------|------------------------------|---------------------|
| CentOS                  | 7, 8, Stream 8/9             | Tested              |
| RHEL                    | 7, 8, 9                      | Tested              |
| Rocky Linux             | 8, 9                         | Tested              |
| AlmaLinux               | 8, 9                         | Tested              |
| Fedora                  | 35 – 41                      | Tested              |
| Oracle Linux            | 7, 8, 9                      | Compatible          |
| CloudLinux              | 7, 8                         | Compatible          |

### SUSE family
| Distribution            | Versions                     | Status              |
|-------------------------|------------------------------|---------------------|
| openSUSE Leap           | 15.x                         | Tested              |
| openSUSE Tumbleweed     | Rolling                      | Tested              |
| SLES                    | 12, 15                       | Compatible          |

### Arch family
| Distribution            | Versions                     | Status              |
|-------------------------|------------------------------|---------------------|
| Arch Linux              | Rolling                      | Compatible          |
| Manjaro                 | Rolling                      | Compatible          |
| EndeavourOS             | Rolling                      | Compatible          |

### Other
| Distribution            | Versions                     | Status              |
|-------------------------|------------------------------|---------------------|
| Alpine Linux            | 3.x                          | Compatible          |

> "Tested" = verified by the author. "Compatible" = dependency auto-install supported, not explicitly tested.
> Tell me if you have verified it on a distribution not listed here.

## Installation

The script must run as root.

```bash
sudo -i
git clone https://github.com/rtulke/dynmotd.git
cd dynmotd
./dynmotd.sh --install
```

`--install` automatically:
1. Detects your Linux distribution
2. Installs any missing dependencies via your native package manager
3. Copies the script to `/usr/local/bin/dynmotd`
4. Creates `/etc/profile.d/motd.sh` so dynmotd runs on every login
5. Runs first-time environment setup (function, environment label, SLA)

To verify the installation, log out and back in:

```bash
exit
sudo -i
```

## Manual dependency installation

If you prefer to install packages yourself before running `--install`:

**Debian / Ubuntu / Raspberry Pi OS / Mint**
```bash
apt update && apt install -y coreutils procps hostname sed gawk grep dnsutils lsb-release
```

**CentOS 7 / RHEL 7**
```bash
yum install -y hostname procps-ng gawk bind-utils
```

**CentOS Stream 8-9 / Rocky / AlmaLinux / RHEL 8-9**
```bash
dnf install -y hostname procps-ng gawk bind-utils
```

**Fedora**
```bash
dnf install -y hostname procps-ng gawk bind-utils
```

**openSUSE / SLES**
```bash
zypper install -y hostname procps gawk bind-utils lsb-release
```

**Arch / Manjaro**
```bash
pacman -Sy inetutils procps-ng gawk bind
```

**Alpine Linux**
```bash
apk add bind-tools busybox-extras procps gawk
```

## Usage

```
Usage: dynmotd [OPTION] [value]

  e.g.  dynmotd -a "deployed new SSL certificate"

Options:

  -a | --addlog "..."           Add a maintenance log entry
  -d | --rmlog  [line-number]   Delete a log entry by line number
  -l | --log                    List all log entries
  -c | --config                 Reconfigure environment settings
  -i | --install                Install dynmotd and its dependencies
  -U | --update                 Update binary only (no setup, safe for Ansible/cron)
  -u | --uninstall              Uninstall dynmotd (log deletion is optional)
  -v | --version                Show version and exit
  -h | --help                   Show this help
```

## Uninstall

```bash
dynmotd --uninstall
```

The uninstaller asks two separate questions:
1. Whether to delete the log and configuration data in `/root/.dynmotd/`
2. Final confirmation before removing the binary and profile hook

System packages that were installed as dependencies are **never** removed automatically. Remove them with your package manager if desired.

## Update

To update an already-installed dynmotd to a newer version without running the full setup again:

```bash
cd dynmotd
git pull
sudo bash dynmotd.sh --update
```

`--update` only replaces the binary at `/usr/local/bin/dynmotd`. It does not ask setup questions, does not touch logs or configuration, and does not reinstall packages — safe to run from Ansible, Puppet, or a cron job.

## Configuration

Edit the config block at the top of the installed script:

```bash
vim /usr/local/bin/dynmotd
```

### Enable / disable sections

```bash
SYSTEM_INFO="1"         # system information (hostname, IP, kernel, CPU, memory, load)
STORAGE_INFO="1"        # storage / disk usage
USER_INFO="1"           # user sessions and SSH keys
ENVIRONMENT_INFO="1"    # environment label (function, env, SLA)
MAINTENANCE_INFO="1"    # maintenance log entries
UPDATE_INFO="1"         # available package updates
FAIL2BAN_INFO="1"       # fail2ban banned IPs (auto-hidden if fail2ban is not installed)
VERSION_INFO="1"        # version banner
```

`1` = enabled, `0` = disabled.

### Maintenance log display

```bash
LIST_LOG_ENTRY="2"      # number of log lines shown in the MOTD
```

### Color schemes

Seven schemes are pre-defined. Uncomment exactly one block to activate it (`F1` = labels, `F2` = borders, `F3` = values, `F4` = warnings):

| # | Name | Character |
|---|------|-----------|
| 1 | **DOT** *(default)* | grey labels · pink borders · green values |
| 2 | **Retro Hacker** | all green, Matrix style |
| 3 | **Retro Alert** | all red, maximum urgency |
| 4 | **Ocean** | cyan/blue, cool and professional |
| 5 | **Solarized Dark** | grey with warm yellow accent |
| 6 | **Nord** | ice blue, clean and modern |
| 7 | **Amber** | brown/yellow, classic CRT terminal |

Example — switching to Nord:

```bash
vim /usr/local/bin/dynmotd
```

Comment out the active scheme and uncomment Nord:

```bash
## 1. DOT - day of the tentacle (default)
#F1=${C_GREY}
#F2=${C_PINK}
#F3=${C_LGREEN}
#F4=${C_RED}

## 6. nord — ice blue, clean and modern
F1=${C_LBLUE}
F2=${C_LCYAN}
F3=${C_WHITE}
F4=${C_YELLOW}
```

## Known Issues

### Hostname not displayed correctly

The `Hostname` field uses `hostname --fqdn`. If `/etc/hostname` contains only the short name, only the short name is shown. Fix:

```bash
hostname mail.example.com
hostname > /etc/hostname
```

Also check `/etc/hosts`:
```
127.0.1.1  mail.example.com
```

> **Note:** The `Address v4` / `Address v6` fields are read directly from network interfaces via `ip -brief addr show` and are not affected by hostname resolution.

### SSH key shows "- Unknown -"

This happens when the key has no comment field. Either add a comment to the end of the key line in `~/.ssh/authorized_keys`, or generate keys with:

```bash
ssh-keygen -C "your.name@example.com"
```

### UPDATE_INFO shows errors on non-Debian systems

Set `UPDATE_INFO="0"` if you are not using a supported package manager (apt, dnf, yum, zypper, pacman).
