#set document(title: "sarten SOC Lab — Attack & Detection Report", author: "asynthe")
#set page(
  paper: "a4",
  margin: (x: 2.2cm, y: 2.4cm),
  numbering: "1",
  footer: context [
    #set text(8pt, fill: luma(130))
    sarten SOC lab #h(1fr) #counter(page).display("1 / 1", both: true)
  ],
)
#set text(font: ("Libertinus Serif", "New Computer Modern"), size: 10.5pt, lang: "en")
#set par(justify: true, leading: 0.62em)
#show heading: set block(above: 1.2em, below: 0.7em)
#show heading.where(level: 1): set text(15pt)
#show heading.where(level: 2): set text(12.5pt)
#set raw(theme: none)
#show raw.where(block: true): block.with(
  fill: luma(245), inset: 8pt, radius: 3pt, width: 100%,
)

#let sev(level) = {
  let c = if level >= 10 { rgb("#b00020") } else if level >= 7 { rgb("#c25e00") } else if level >= 4 { rgb("#8a6d00") } else { rgb("#4a4a4a") }
  text(fill: c, weight: "bold")[#level]
}
#let mitre(id, name) = [#raw(id) #name]
#let pending = text(fill: rgb("#b00020"), style: "italic")[[ pending — fill after running this phase ]]

// ---------- title block ----------
#align(center)[
  #text(20pt, weight: "bold")[Attack & Detection Report]
  #v(2pt)
  #text(13pt)[sarten home SOC lab]
  #v(10pt)
  #text(10pt, fill: luma(90))[
    Author: asynthe #h(1.2em) Date: #datetime.today().display("[year]-[month]-[day]") #h(1.2em) Classification: Lab / Portfolio
  ]
]
#line(length: 100%, stroke: 0.5pt + luma(180))
#v(6pt)

= Executive summary

This report documents a controlled offensive exercise against the author's own
home lab, carried out to validate the detection coverage of a self-hosted Wazuh
SIEM. A Parrot Security workstation was used to run reconnaissance, a
credential-access attack, and web-application attacks against intentionally
exposed services. Each action was correlated against the alerts it produced in
Wazuh, mapped to MITRE ATT&CK, and assessed for detection quality.

All targets are the author's own systems on an isolated home network; all
addresses shown are private (RFC 1918). The exercise is a lab simulation, not an
engagement against a third party.

#block(fill: luma(245), inset: 10pt, radius: 3pt, width: 100%)[
  *Headline result* — #pending
]

= Scope & environment

The lab is a single Proxmox VE host running unprivileged LXC guests, each with
one Docker stack. Wazuh agents on the host and guests ship logs to a single-node
Wazuh manager/indexer/dashboard. Two services are deliberately reachable from
the internet through Tailscale Funnel: Jellyfin and an nginx honeypot.

#figure(
  caption: [Targets in scope],
  table(
    columns: (auto, auto, 1fr, auto),
    align: (left, left, left, center),
    stroke: 0.4pt + luma(200),
    inset: 6pt,
    table.header([*Host*], [*Address*], [*Role*], [*Agent*]),
    [sarten], [192.168.1.135], [Proxmox VE host (Debian 13)], [001],
    [media], [192.168.1.140], [Jellyfin + arr stack], [003],
    [wazuh], [192.168.1.142], [Wazuh manager / indexer / dashboard], [000],
    [honeypot], [192.168.1.143], [nginx decoy login page], [004],
    [parrot], [192.168.1.99], [*Attacker* — Parrot Security 7.4], [—],
  ),
)

Wazuh version 4.14.8. The dashboard was cleared of prior events immediately
before this exercise, so every alert shown here is attributable to the campaign.

= Methodology & tooling

Attacks progress along the ATT&CK kill chain: reconnaissance, then credential
access, then exploitation of the web tier. Tools are those shipped with Parrot
Security: `nmap`, `hydra`, `nikto`, and `sqlmap`. For each technique the report
records the exact command, the resulting Wazuh alert(s), and an assessment of
whether and how quickly the activity was detected.

= Attack narrative

== Phase 1 — Reconnaissance
#text(fill: luma(110))[MITRE: #mitre("T1595", "Active Scanning"), #mitre("T1046", "Network Service Discovery")]

*Objective.* Enumerate live hosts and fingerprint exposed services.

*Command (from parrot):*
```bash
sudo nmap -sS -sV -p 22,80,443,8096,8989,9090,3000 192.168.1.135 192.168.1.140 192.168.1.143
```

*Result.* The scan completed in 12 seconds and fingerprinted only intended
services — no unexpected ports were open.

#table(
  columns: (auto, auto, 1fr),
  align: (left, left, left),
  stroke: 0.4pt + luma(200), inset: 6pt,
  table.header([*Host*], [*Open*], [*Service (`nmap -sV`)*]),
  [.135 sarten], [22], [OpenSSH 10.0p2 (Debian)],
  [.140 media], [22, 3000, 8096, 8989], [SSH; Jellyfin and Sonarr on Kestrel (.NET); port 3000 rejected probes with "Host validation failed"],
  [.143 honeypot], [22, 80], [SSH; nginx],
)

*Wazuh detection.* Each of nmap's `-sV` HTTP probes against the honeypot's
port 80 became a honeypot alert:

#table(
  columns: (auto, auto, auto, 1fr),
  align: (center, center, center, left),
  stroke: 0.4pt + luma(200), inset: 6pt,
  table.header([*Rule*], [*Level*], [*Count*], [*Detail*]),
  [100110], [#sev(6)], [9], [Probe paths `/`, `/nmaplowercheck…`, `/sdk`, `/evox/about`, `/HNAP1`; user-agent "Nmap Scripting Engine"],
)

The scan-rate rule 100111 did *not* fire — `-sV` sent only 9 requests, below its
threshold of 20 per minute. Scanning of SSH and the closed ports produced *no*
alerts at all.

#figure(
  rect(width: 100%, height: 4.5cm, fill: luma(245), stroke: 0.4pt + luma(200))[
    #align(center + horizon)[#text(fill: luma(140))[screenshot: docs/wazuh/images/phase1-nmap.png]]
  ],
  caption: [Reconnaissance activity in the Wazuh dashboard],
)

*Analysis.* The honeypot reliably flags service-enumeration traffic, and nmap
did little to hide: the "Nmap Scripting Engine" user-agent and probe paths such
as `/HNAP1` and `/evox/about` are unambiguous scanner fingerprints. Two gaps are
worth recording. First, a low-and-slow service scan stays under the rate-based
rule 100111, so the individual 100110 events carry the detection — a rule keyed
on the scanner user-agent would escalate severity at once. Second, network-layer
scanning of the host (SYN scans, closed ports, SSH banner grabbing) left no
application log and so raised no alert; closing that gap needs a network IDS such
as Suricata, tracked as a planned control.

== Phase 2 — Credential access (SSH brute force)
#text(fill: luma(110))[MITRE: #mitre("T1110.001", "Brute Force: Password Guessing")]

*Objective.* Attempt to brute-force SSH on the Proxmox host.

*Command (from parrot):*
```bash
hydra -l asynthe -P /usr/share/wordlists/rockyou.txt ssh://192.168.1.135 -t 4 -V
```

*Result.* #pending

*Wazuh detection.* #pending

#figure(
  rect(width: 100%, height: 4.5cm, fill: luma(245), stroke: 0.4pt + luma(200))[
    #align(center + horizon)[#text(fill: luma(140))[screenshot: docs/wazuh/images/phase2-ssh.png]]
  ],
  caption: [SSH brute-force alerts],
)

*Analysis.* #pending

== Phase 3 — Web application attacks
#text(fill: luma(110))[MITRE: #mitre("T1190", "Exploit Public-Facing Application"), #mitre("T1595.002", "Vulnerability Scanning")]

*Objective.* Scan and attack the exposed honeypot web service.

*Commands (from parrot):*
```bash
nikto -h http://192.168.1.143
sqlmap -u "http://192.168.1.143/product?id=1" --batch --level 2
```

*Result.* #pending

*Wazuh detection.* #pending

#figure(
  rect(width: 100%, height: 4.5cm, fill: luma(245), stroke: 0.4pt + luma(200))[
    #align(center + horizon)[#text(fill: luma(140))[screenshot: docs/wazuh/images/phase3-web.png]]
  ],
  caption: [Web-attack alerts: custom and built-in web rules],
)

*Analysis.* #pending

= Detection coverage

#figure(
  caption: [Technique-to-detection matrix],
  table(
    columns: (auto, 1fr, auto, auto, auto),
    align: (left, left, center, center, center),
    stroke: 0.4pt + luma(200),
    inset: 6pt,
    table.header([*Phase*], [*Technique*], [*Rule(s)*], [*Level*], [*Detected*]),
    [1], [Active scanning (T1595)], [100110], [#sev(6)], [#text(fill: rgb("#c25e00"))[Partial]],
    [2], [Password guessing (T1110.001)], [5710/5712], [#sev(5)/#sev(10)], [#pending],
    [3], [Exploit public-facing app (T1190)], [31103/31104], [#sev(7)/#sev(6)], [#pending],
    [3], [Vulnerability scanning (T1595.002)], [31508/100111], [#sev(6)/#sev(10)], [#pending],
  ),
)

= Findings & recommendations

#pending

= Appendix A — Custom detection rules

The honeypot and Jellyfin detections used in this exercise are custom Wazuh
decoders and rules maintained in the repository under
`services/wazuh/config/ruleset/`.

#table(
  columns: (auto, auto, 1fr),
  align: (center, center, left),
  stroke: 0.4pt + luma(200),
  inset: 6pt,
  table.header([*Rule*], [*Level*], [*Fires on*]),
  [100102], [#sev(5)], [Jellyfin login failed, with the attacker's IP],
  [100103], [#sev(10)], [8 failed Jellyfin logins in 2 min from one IP (T1110)],
  [100110], [#sev(6)], [Any honeypot request — nothing legitimate visits it],
  [100111], [#sev(10)], [20 honeypot requests in a minute from one IP (T1595)],
)
