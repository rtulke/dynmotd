# dynmotd
Dynamic Message of the Day — a single Bash script that displays system information on login.

![Example](/data/screenshot.png)

## Features

- Color schemes (switchable via config block at top of script)
- Enable/disable individual information sections
- Per-host description, environment label and SLA tag
- Maintenance log with add/delete/list support
- Automatic dependency installation on `--install`
- Multi-distribution support (Debian, RHEL, SUSE, Arch, Alpine families)
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
  -u | --uninstall              Uninstall dynmotd (log deletion is optional)
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

## Configuration

Edit the config block at the top of the installed script:

```bash
vim /usr/local/bin/dynmotd
```

### Enable / disable sections

```bash
SYSTEM_INFO="1"         # system information
STORAGE_INFO="1"        # storage / disk usage
USER_INFO="1"           # user sessions and SSH keys
ENVIRONMENT_INFO="1"    # environment label (function, env, SLA)
MAINTENANCE_INFO="1"    # maintenance log entries
UPDATE_INFO="1"         # available package updates
VERSION_INFO="1"        # version banner
```

`1` = enabled, `0` = disabled.

### Maintenance log display

```bash
LIST_LOG_ENTRY="2"      # number of log lines shown in the MOTD
```

### Color schemes

Three schemes are pre-defined in the config block. Uncomment a scheme to activate it:

```bash
## DOT - day of the tentacle (default: grey / pink / green / red)
F1=${C_GREY}; F2=${C_PINK}; F3=${C_LGREEN}; F4=${C_RED}

## retro hacker (all green)
#F1=${C_GREEN}; F2=${C_GREEN}; F3=${C_GREEN}; F4=${C_RED}

## retro alert (all red)
#F1=${C_RED}; F2=${C_RED}; F3=${C_RED}; F4=${C_RED}
```

## Known Issues

### FQDN or IP address not displayed correctly

`hostname --fqdn` returns only the short hostname when `/etc/hostname` contains just the short name. Fix:

```bash
hostname mail.example.com
hostname > /etc/hostname
```

Also check `/etc/hosts`:
```
127.0.1.1  mail.example.com
```

### SSH key shows "- Unknown -"

This happens when the key has no comment field. Either add a comment to the end of the key line in `~/.ssh/authorized_keys`, or generate keys with:

```bash
ssh-keygen -C "your.name@example.com"
```

### UPDATE_INFO shows errors on non-Debian systems

Set `UPDATE_INFO="0"` if you are not using a supported package manager (apt, dnf, yum, zypper, pacman).
