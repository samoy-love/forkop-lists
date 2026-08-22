# forkop-lists

Subnet lists for a [forkop](https://github.com/itdoginfo/podkop) / sing-box setup on an OpenWrt router.

The router used to regenerate these with a local cron job. They now live here so the
work happens in CI and the router just fetches URLs — nothing to maintain on the device.

## Lists

| File | Raw URL | Used by |
|---|---|---|
| `lists/aws-eu-ec2.lst` | [raw](../../raw/main/lists/aws-eu-ec2.lst) | forkop section `Zapret_GameServers_UDP` |
| `lists/wardogs-game-ips.lst` | [raw](../../raw/main/lists/wardogs-game-ips.lst) | forkop section `Zapret_Badseq_Alt2` |

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

In LuCI these lists go into a section's **Conditions -> "Domain and IP lists"** field, which is
the UCI option `domain_ip_lists`. It takes URLs (or local paths) to `.lst` files holding
domains and/or subnets, and forkop splits the two apart on import.

```
uci add_list forkop.<Section>.domain_ip_lists='https://raw.githubusercontent.com/tr0llex/forkop-lists/main/lists/aws-eu-ec2.lst'
uci commit forkop && /etc/init.d/forkop restart
```

Do **not** use `remote_subnet_lists` — the option exists in the code but the sing-box config
generator rejects it with `section has unsupported matcher remote_subnet_lists`.

The neighbouring field **"Rule sets"** (`rule_set`) takes `.srs` / `.json` instead, but it
ignores subnets by default, so it is the wrong choice for these files.

Lists refresh on forkop's own interval (`update_interval`, currently `1h`).
