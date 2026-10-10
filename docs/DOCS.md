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
| `tailscale` | tailnet access, subnet routing, and `tailscale serve` exposing guest ports as `sarten:<port>` (`tailscale_serve` in group_vars); entries with `funnel: true` are public at `https://sarten.<tailnet>.ts.net` instead |
| `config` | copies `config/` onto the host |
| `lxc` | container feature flags and bind mounts, from the host |
| `exporters` | node exporter, SMART metrics and smartd on the host |
| `wazuh_agent` | Wazuh agent on the host, held at `wazuh_version`, reading auth and Proxmox web UI logs |
| `docker` | docker inside a guest |
| `media`, `monitoring`, `wazuh` | each guest's compose stack |

| guest | runs |
| --- | --- |
| `media` | jellyfin, the arr apps, qbittorrent behind gluetun, flaresolverr, recyclarr, homepage |
| `monitoring` | prometheus, grafana, the Proxmox exporter |
| `wazuh` | single-node Wazuh manager, indexer and dashboard; takes syslog |

The `media` role also wires the apps together through their APIs: qBittorrent
saves to `/data/downloads/<category>` on the same subvolume as the library, so
imports are hardlinks; each arr gets its root folders and qBittorrent as
download client; Prowlarr syncs its indexers to them, sending Cloudflare sites
through FlareSolverr; Recyclarr keeps Radarr on the TRaSH `HD Bluray + WEB`
profile, with `radarr_formats` on top: only YTS releases pass its minimum score,
nothing over `movie_max_gb`, and other files are upgraded to YTS; Sonarr is on
`WEB-1080p`, naming folders `Title (Year) [tmdbid-N]` and `[tvdbid-N]` for
Jellyfin; Bazarr reads Sonarr and Radarr and fetches `subtitle_languages` for
everything; Jellyfin gets a library per media folder, the plugins in `jellyfin_plugins`,
the collections in `jellyfin_collections` and the accounts in `jellyfin_users`.
`series-es` holds Latin American Spanish dubs, uploaded by hand: no arr app
knows the folder, so nothing renames or replaces them, and its Jellyfin library
fetches `es-MX` metadata. Files holding two TMDB segments are named
`S01E01-E02`. `videos` holds our own shows, also by hand: their `.nfo` files
set `lockdata`, so Jellyfin keeps the local metadata.
Settings spelled out in `site.yml` are enforced; everything else only adds what
is missing, so changes made in the UIs stay, except that non-admin Jellyfin
accounts not in `jellyfin_users` are deleted. Logins are `media_user`
(`jellyfin_admin` on Jellyfin) with `media_password`, skipped from local
addresses on the arr apps and qBittorrent. qBittorrent's traffic leaves only
through the VPN in `vpn`, a map of gluetun environment variables.

`services/wazuh/` is upstream's single-node stack, trimmed to fit an
unprivileged container: no memlock, a lower file limit, and only the dashboard,
agent and syslog ports published. Its passwords live in `wazuh` in
`all.sops.yaml`: `admin_password` logs into the dashboard, `dashboard_password`
is the dashboard's own indexer user, `api_password` is the manager API's
`wazuh-wui`, and the two `_hash` entries are bcrypt hashes of the first two
(the indexer container's `plugins/opensearch-security/tools/hash.sh`). A change
is loaded into the running indexer with `securityadmin.sh`.

## Deploy

```bash
cd ansible && ansible-galaxy collection install -r requirements.yml -p .collections
ansible-playbook site.yml -l sarten -e upgrade=true

cd ../tofu
tofu init && tofu apply

cd ../ansible && ansible-playbook site.yml -l guests
```

Secrets live in `ansible/group_vars/all.sops.yaml`, encrypted with sops to the
age key in `.sops.yaml`; change them with `sops edit`.

| key | used by |
| --- | --- |
| `proxmox_api_token` | tofu |
| `ssh_keys` | `users`, tofu |
| `vpn` | gluetun, a map of its environment variables |
| `media_password` | logins for `media_user` on qBittorrent and the arr apps, and `jellyfin_admin` on Jellyfin |
| `jellyfin_users` | other Jellyfin accounts, `name: password`; the password is only the first one, and a non-admin account missing from the list is deleted |
| `subtitles` | optional Bazarr provider logins, `provider: {key: value}` as in Bazarr's settings, e.g. `opensubtitlescom: {username, password}` |

Paths, the LAN subnet, the tailnet name and the media uid are set once in
`ansible/group_vars/all.yml`; the media stack reads them from a generated `.env`,
and files in `config/` are rendered as templates.

Ansible loads the sops file through the `community.sops` vars plugin and Tofu
through the `carlpett/sops` provider, so both read the same file with no wrapper.

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
| funnel | in the admin console, enable HTTPS certificates and give the host the `funnel` node attribute |
| web UI login for admins | `passwd <user>` |

## Recovery

Both `/` and the data mirror are btrfs RAID1, which refuses to mount with a
disk missing. For `/`, add `rootflags=degraded` to the kernel line at boot, then
`btrfs replace` the dead disk. The data mirror is `nofail` and never blocks
boot; mount it with `-o degraded` and replace the same way.
