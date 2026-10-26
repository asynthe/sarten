containers = {
  media = {
    id       = 110
    ip       = "192.168.1.140/24"
    template = "local-btrfs:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
    cores    = 4
    memory   = 8192
    disk     = 32
    tags     = ["docker", "media"]
    notes    = <<-EOT
      # media
      docker compose, `/opt/media` · source: `services/media` in the sarten repo

      | service | |
      | --- | --- |
      | Homepage | http://192.168.1.140:3000 |
      | Jellyfin | http://192.168.1.140:8096 |
      | Sonarr | http://192.168.1.140:8989 |
      | Radarr | http://192.168.1.140:7878 |
      | Lidarr | http://192.168.1.140:8686 |
      | Prowlarr | http://192.168.1.140:9696 |
      | Bazarr | http://192.168.1.140:6767 |
      | qBittorrent | http://192.168.1.140:8080 |
    EOT
  }

  monitoring = {
    id       = 120
    ip       = "192.168.1.141/24"
    template = "local-btrfs:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
    cores    = 2
    memory   = 4096
    disk     = 32
    tags     = ["docker", "monitoring"]
    notes    = <<-EOT
      # monitoring
      docker compose, `/opt/monitoring` · source: `services/monitoring` in the sarten repo

      | service | |
      | --- | --- |
      | Grafana | http://192.168.1.141:3000 |
      | Prometheus | http://192.168.1.141:9090 |
    EOT
  }

  hermes = {
    id       = 150
    ip       = "192.168.1.143/24"
    template = "local-btrfs:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
    cores    = 2
    memory   = 4096
    disk     = 24
    tags     = ["hermes"]
    notes    = <<-EOT
      # hermes
      native install (install.sh), runs as the `hermes` system user · source: `ansible/roles/hermes`

      | service | |
      | --- | --- |
      | Dashboard | http://192.168.1.143:9119 |
    EOT
  }

  wazuh = {
    id       = 130
    ip       = "192.168.1.142/24"
    template = "local-btrfs:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
    cores    = 4
    memory   = 8192
    disk     = 64
    tags     = ["docker", "security"]
    notes    = <<-EOT
      # wazuh
      docker compose, `/opt/wazuh` · source: `services/wazuh` in the sarten repo

      | service | |
      | --- | --- |
      | Dashboard | https://192.168.1.142 |
      | Agents | 1514/tcp, enrollment 1515/tcp |
      | Syslog | 514/udp |
    EOT
  }
}
