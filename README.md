# sarten

Infrastructure for a single-node Proxmox VE homelab. OpenTofu decides which
guests exist, Ansible configures the host and everything inside the guests, and
each guest runs one docker compose stack. Each layer only does its own job.

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
| `media`, `monitoring`, `wazuh` | each guest's compose stack |

| guest | runs |
| --- | --- |
| `media` | jellyfin, the arr apps, qbittorrent, homepage |
| `monitoring` | prometheus, grafana, the Proxmox exporter |
| `wazuh` | single-node Wazuh manager, indexer and dashboard; takes syslog |

`services/wazuh/` is upstream's single-node stack, trimmed to fit an
unprivileged container: no memlock, a lower file limit, and only the dashboard,
agent and syslog ports published.

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
provider, so both read the same file with no wrapper.

Tofu authenticates with the Proxmox API token stored there. Tokens cannot set
LXC feature flags or bind mounts, so the `lxc` role applies those from the
inventory and Tofu ignores them. Every step is idempotent; re-run the one whose
folder changed. `-t config` pushes only `config/`.

## Once per install

| step | how |
| --- | --- |
| root ssh key | `ssh-copy-id root@<host>` |
| data mirror | `mkfs.btrfs -L sarten-data -d raid1 -m raid1 <disk> <disk>` |
| tailnet | `tailscale up --advertise-routes=<lan>`, then approve the route |
| web UI login for admins | `passwd <user>` |

## Recovery

Both `/` and the data mirror are btrfs RAID1, which refuses to mount with a
disk missing. For `/`, add `rootflags=degraded` to the kernel line at boot, then
`btrfs replace` the dead disk. The data mirror is `nofail` and never blocks
boot; mount it with `-o degraded` and replace the same way.
