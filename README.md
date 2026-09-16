# forkop-lists

Subnet lists for a [forkop](https://github.com/itdoginfo/podkop) / Tachyon / sing-box setup on an OpenWrt router.

The router used to regenerate these with a local cron job. They now live here so the
work happens in CI and the router just fetches URLs — nothing to maintain on the device.

## Lists

| File | Raw URL | Used by |
|---|---|---|
| `lists/aws-eu-ec2.lst` | [raw](../../raw/main/lists/aws-eu-ec2.lst) | plain domain/IP list |
| `lists/wardogs-game-ips.lst` | [raw](../../raw/main/lists/wardogs-game-ips.lst) | plain domain/IP list |
| `lists/aws-eu-ec2.json` | [raw](../../raw/main/lists/aws-eu-ec2.json) | sing-box source rule-set |
| `lists/wardogs-game-ips.json` | [raw](../../raw/main/lists/wardogs-game-ips.json) | sing-box source rule-set |
| `lists/aws-eu-ec2.srs` | [raw](../../raw/main/lists/aws-eu-ec2.srs) | sing-box binary rule-set |
| `lists/wardogs-game-ips.srs` | [raw](../../raw/main/lists/wardogs-game-ips.srs) | sing-box binary rule-set |

`aws-eu-ec2.lst` is rebuilt by `.github/workflows/update-lists.yml` from
<https://ip-ranges.amazonaws.com/ip-ranges.json>. `wardogs-game-ips.lst` is hand-maintained.

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

## Consuming from forkop or Tachyon

In LuCI these `.lst` lists go into a section's **Conditions -> "Domain and IP lists"** field,
which is the UCI option `domain_ip_lists`. It takes URLs (or local paths) to plain text files
holding domains and/or subnets, and the router splits the two apart on import.

```
uci add_list forkop.<Section>.domain_ip_lists='https://raw.githubusercontent.com/samoy-love/forkop-lists/main/lists/aws-eu-ec2.lst'
uci commit forkop && /etc/init.d/forkop restart
```

For Tachyon, add these same URLs to **Conditions -> "Domain and IP lists"**:

```
https://raw.githubusercontent.com/samoy-love/forkop-lists/main/lists/aws-eu-ec2.lst
https://raw.githubusercontent.com/samoy-love/forkop-lists/main/lists/wardogs-game-ips.lst
```

Do **not** put the `.lst` URLs into **"Rule sets"**. That field expects a sing-box `.srs` or
source `.json` rule-set; a plain `.lst` there is interpreted as a binary rule-set and makes
sing-box reject the configuration.

The neighbouring **"Rule sets"** (`rule_set`) field is for the `.srs` / `.json` files listed
above when the consumer explicitly supports sing-box rule-sets. The JSON files are generated
from the corresponding `.lst` files and are kept in sync by CI.

For Tachyon, use these `.srs` URLs in **Conditions -> "Rule sets"** when the list must be
used as a sing-box rule-set:

```
https://raw.githubusercontent.com/samoy-love/forkop-lists/main/lists/aws-eu-ec2.srs
https://raw.githubusercontent.com/samoy-love/forkop-lists/main/lists/wardogs-game-ips.srs
```

The `.srs` files are compiled from the corresponding source `.json` files with sing-box
1.14.0. The plain `.lst` links remain available for **Domain and IP lists** consumers.

Lists refresh on forkop's own interval (`update_interval`, currently `1h`).
