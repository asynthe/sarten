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
and configured entirely as code. One service, Jellyfin, faces the internet on
purpose, so the lab watches real-world traffic as well as its own.

```
            internet
               │ Tailscale Funnel (HTTPS)
               ▼
┌──────────── sarten · Proxmox VE · Debian 13 ─────────────┐
│ wazuh-agent · rsyslog · node exporter · smartd           │
│                                                          │
│ ┌─ media ──────┐  ┌─ monitoring ─┐  ┌─ wazuh ──────────┐ │
│ │ Jellyfin     │  │ Prometheus   │  │ manager          │ │
│ │ arr apps     │  │ Grafana      │  │ indexer          │ │
│ │ qBittorrent  │  │ PVE exporter │  │ dashboard        │ │
│ │  behind VPN  │  │              │  │ syslog 514/udp   │ │
│ └──────────────┘  └──────────────┘  └────────▲─────────┘ │
└──────────────────────────────────────────────┼───────────┘
                                               │ agents, 1514/tcp
                                   sarten (Debian 13)
                                   p1 (Windows 11)
```

## Detections

| what | how | status |
| --- | --- | --- |
| SSH logins, sudo to root, PAM sessions | agent reads `auth.log` on the host | working |
| CIS benchmark: Debian 13, Windows 11 | Wazuh SCA on each agent | working |
| Proxmox web UI access | agent reads the `pveproxy` access log | collecting |
| file integrity, vulnerable packages | Wazuh FIM and vulnerability detection, defaults | collecting |
| Jellyfin brute force over Funnel | Jellyfin log, custom decoder and rules | planned |
| SSH brute force, blocked automatically | hydra from Kali, active response | planned |
| SQL injection, XSS, web shells | DVWA target, web logs, FIM and YARA | planned |
| network scans | Suricata on the lab bridge | planned |

The planned rows run in an isolated lab: a deliberately weak target and a Kali
VM on a bridge with no route to the home network.

## Findings

**Default credentials.** The Wazuh stack first ran on upstream's demo
passwords, committed in this public repo. They were rotated into sops, loaded
into the indexer with `securityadmin.sh`, and the old `admin` password was
verified to be rejected. They remain in git history, inert.

## Stack

Proxmox VE · OpenTofu · Ansible · Docker · Wazuh 4.14 · Prometheus · Grafana ·
Tailscale · sops + age

OpenTofu creates the guests, Ansible configures the host and everything inside
them, and each guest runs one compose stack. Nothing decrypted is committed.
Technical reference: [docs/DOCS.md](docs/DOCS.md).

*asynthe, 2026.*
