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
└───────────────────────────────────────────────────────────────────┼─────────┘
                                                                    │ agents
                                            sarten, media, honeypot (Debian 13)
                                                                p1 (Windows 11)
```

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
