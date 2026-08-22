# forkop-lists

Subnet lists for a [forkop](https://github.com/itdoginfo/podkop) / sing-box setup on an OpenWrt router.

The router used to regenerate these with a local cron job. They now live here so the
work happens in CI and the router just fetches URLs — nothing to maintain on the device.

## Lists

| File | Raw URL | Used by |
|---|---|---|
| `lists/aws-eu-ec2.txt` | [raw](../../raw/main/lists/aws-eu-ec2.txt) | forkop section `Zapret_GameServers_UDP` |
| `lists/wardogs-game-ips.txt` | [raw](../../raw/main/lists/wardogs-game-ips.txt) | forkop section `Zapret_Badseq_Alt2` |

`aws-eu-ec2.txt` is rebuilt by `.github/workflows/update-lists.yml` from
<https://ip-ranges.amazonaws.com/ip-ranges.json>. `wardogs-game-ips.txt` is hand-maintained.

## Why DYNAMODB prefixes are excluded

Games measure per-region latency by opening a TCP connection to
`dynamodb.<region>.amazonaws.com`. When those prefixes are routed through sing-box the
handshake completes **on the router**, so every region reports the same ~5 ms and server
selection breaks.

Measured on the live router:

| Region | intercepted | excluded |
|---|---|---|
| eu-north-1 | 4.7 ms | 27.1 ms |
| eu-central-1 | 5.2 ms | 43.6 ms |
| us-east-1 | 2.8 ms | 127.9 ms |
| ap-southeast-2 | 4.9 ms | 318.6 ms |

## Format

Plain text, one CIDR per line. Lines starting with `#` are not valid CIDRs, so forkop's
`import-plain-list` records them as invalid and skips them — harmless, but keep comments short.

## Schedule caveat

The workflow is set to `*/5 * * * *`, which is GitHub's minimum. Scheduled workflows are
best-effort and often run late under load. AWS ranges change on the order of days, so the
real refresh rate is not important; the interval is just a ceiling on staleness.

## Consuming from forkop

Set `remote_subnet_lists` on the section (a URL, not a local path):

```
uci add_list forkop.<Section>.remote_subnet_lists='https://raw.githubusercontent.com/<owner>/forkop-lists/main/lists/aws-eu-ec2.txt'
uci commit forkop && /etc/init.d/forkop restart
```

forkop accepts `.json`, `.srs` and plain-text URLs for this option and refreshes them on its
own list-update interval (`update_interval`, currently `1h`).
