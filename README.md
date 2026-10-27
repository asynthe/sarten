```
        .-~~~~~~~-.
      .'           '.
     /     .---.     \
    |     ( (@) )     |==========[]
     \     '---'     /
      '.           .'
        '-._____.-'
```

# sarten

A home SOC lab: a Proxmox server monitored by a self-hosted Wazuh SIEM, built
and configured entirely as code. Two services face the internet on purpose, a
media server and a honeypot, so the lab watches real-world attacks as well as
its own.

```
        internet
           │ Tailscale Funnel
           ├──────────────────┐
           ▼ :443             ▼ :8443
┌──── sarten · Proxmox VE · Debian 13 ────────────────────────────────────────┐
│ wazuh-agent · rsyslog · node exporter · smartd                              │
│                                                                             │
│ ┌─ media ────────┐ ┌─ honeypot ─────┐ ┌─ monitoring ───┐ ┌─ wazuh ────────┐ │
│ │ Jellyfin       │ │ nginx decoy    │ │ Prometheus     │ │ manager        │ │
│ │ arr apps       │ │ read-only,     │ │ Grafana        │ │ indexer        │ │
│ │ qBittorrent    │ │   no caps      │ │ PVE exporter   │ │ dashboard      │ │
│ │   behind VPN   │ │                │ │                │ │ syslog 514/udp │ │
│ └────────────────┘ └────────────────┘ └────────────────┘ └────────▲───────┘ │
│ ┌─ hermes ───────────────────────────┐                             │        │
│ │ Hermes Agent, native install,      │                             │        │
│ │ dashboard :9119, LAN only           │                             │        │
│ └─────────────────────────────────────┘                             │        │
└───────────────────────────────────────────────────────────────────┼─────────┘
                                                                    │ agents
                                    sarten, media, honeypot, hermes (Debian 13)
                                                                p1 (Windows 11)
```

| folder | what |
| --- | --- |
| `install/` | unattended installer answer file and ISO builder |
| `tofu/` | guests: size, network, mounts |
| `ansible/` | host and guest configuration, one role per concern |
| `config/` | plain files pushed to the host, one folder per app; destinations in `ansible/group_vars/all.yml` |
| `services/` | one compose stack per guest |

| ansible role | does |
| --- | --- |
| `base` | repositories, packages, timezone, container template |
| `users` | admin accounts, ssh keys, Proxmox permissions |
| `storage` | mounts the data mirror, subvolumes, media layout |
| `tailscale` | tailnet access, subnet routing, and `tailscale serve` exposing guest ports as `sarten:<port>` (`tailscale_serve` in group_vars) |
| `config` | copies `config/` onto the host |
| `lxc` | container feature flags and bind mounts, from the host |
| `exporters` | node exporter, SMART metrics and smartd on the host |
| `docker` | docker inside a guest |
| `media`, `monitoring`, `wazuh`, `honeypot` | each guest's compose stack |
| `hermes` | Hermes Agent on its own guest, native install (no docker): a `hermes` system user, the dashboard as a systemd user service on port 9119, LAN only |

## Deploy

```bash
cd ansible && ansible-galaxy collection install -r requirements.yml -p .collections
ansible-playbook site.yml -l sarten -e upgrade=true

cd ../tofu
tofu init && tofu apply

cd ../ansible && ansible-playbook site.yml -l guests
```

Secrets live in `ansible/group_vars/all.sops.yaml`, encrypted with sops to the
age key in `.sops.yaml`; change them with `sops edit`. Ansible loads the file
through the `community.sops` vars plugin and Tofu through the `carlpett/sops`
provider, so both read the same file with no wrapper. The `hermes` role needs
a `hermes` map in there: `provider`, `default`, `api_key`, `api_key_env` (the
`.env` variable name the provider expects, e.g. `OPENROUTER_API_KEY`), and
optionally `base_url`.

## Detections

| what | how | status |
| --- | --- | --- |
| SSH logins, sudo to root, PAM sessions | agent reads `auth.log` on the host | working |
| CIS benchmark: Debian 13, Windows 11 | Wazuh SCA on each agent | working |
| Jellyfin logins and brute force from the internet | Jellyfin log, [custom decoder and rules](services/wazuh/config/ruleset/) | working |
| every honeypot request, scans, SQL injection | nginx access log, custom and built-in web rules | working |
| Proxmox web UI access | agent reads the `pveproxy` access log | collecting |
| file integrity | Wazuh FIM, defaults | collecting |
| vulnerable packages | Wazuh vulnerability detection | working |
| SSH brute force, blocked automatically | hydra from Kali, active response | planned |
| web shells | DVWA target, FIM and YARA | planned |
| network scans | Suricata on the lab bridge | planned |

| rule | level | fires on |
| --- | --- | --- |
| 100102 | 5 | Jellyfin login failed, with the attacker's IP |
| 100103 | 10 | 8 failed Jellyfin logins in 2 minutes from one IP (MITRE T1110) |
| 100110 | 6 | any honeypot request: nothing legitimate ever visits it |
| 100111 | 10 | 20 honeypot requests in a minute from one IP (MITRE T1595) |

Each rule was tested with `wazuh-logtest` and then end to end: a failed login
sent through Tailscale Funnel from outside reached Wazuh as rule 100102 with
the sender's real public IP.

## Honeypot

A decoy "Admin Console" login page, public at port 8443 of the Funnel address.
It has no users, so every request is an alert. It is nginx in a read-only
container with every Linux capability dropped and no privilege escalation; the
form posts nowhere real. It sits on the home network for now and moves to the
isolated lab bridge once that exists.

## Findings

**Default credentials.** The Wazuh stack first ran on upstream's demo
passwords, committed in this public repo. They were rotated into sops, loaded
into the indexer with `securityadmin.sh`, and the old `admin` password was
verified to be rejected. They remain in git history, inert.

**The proxy hid every attacker.** Tailscale Funnel passes the client's address
in `X-Forwarded-For`, but Jellyfin didn't trust it, so every login from the
internet was logged as coming from the Proxmox host. Brute force would have
been unattributable, and Jellyfin treated internet visitors as local. Fixed by
trusting the host as a known proxy; verified with a failed login from outside.

**A nightly blind spot.** Jellyfin names its log after the local date; the
containers ran on UTC, so from 21:00 to midnight the agent watched the next
day's file, which didn't exist yet. Three hours of logins every night would
have gone unseen. Fixed by putting every container on the host's timezone.

## Stack

Proxmox VE · OpenTofu · Ansible · Docker · Wazuh 4.14 · Prometheus · Grafana ·
Tailscale · sops + age

OpenTofu creates the guests, Ansible configures the host and everything inside
them, and each guest runs one compose stack. Nothing decrypted is committed.
Technical reference: [docs/DOCS.md](docs/DOCS.md).

*asynthe, 2026.*
