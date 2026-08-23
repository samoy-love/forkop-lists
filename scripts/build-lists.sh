#!/usr/bin/env bash
# Rebuilds the subnet lists consumed by forkop (OpenWrt router) via remote_subnet_lists URLs.
set -euo pipefail

SRC="https://ip-ranges.amazonaws.com/ip-ranges.json"
RAW="$(mktemp)"
PFX="$(mktemp)"
trap 'rm -f "$RAW" "$PFX"' EXIT

curl -fsSL --retry 5 --retry-delay 3 -o "$RAW" "$SRC"

# EC2 prefixes of every eu-* region, MINUS the DYNAMODB prefixes.
#
# Why DYNAMODB is excluded: games measure per-region latency by opening a TCP
# connection to dynamodb.<region>.amazonaws.com. If those prefixes are routed
# through sing-box, the handshake completes locally on the router and every
# region reports ~5 ms, which breaks server selection. Measured proof:
# eu-north-1 read 4.7 ms while intercepted vs 27.1 ms once excluded.
jq -r '
  ([.prefixes[] | select(.service == "DYNAMODB") | .ip_prefix] | unique) as $ddb
  | .prefixes[]
  | select(.service == "EC2")
  | select(.region | startswith("eu-"))
  | select(.ip_prefix as $p | ($ddb | index($p)) | not)
  | .ip_prefix
' "$RAW" | sort -u > "$PFX"

COUNT=$(wc -l < "$PFX")
if [ "$COUNT" -lt 100 ]; then
  echo "refusing to publish: only $COUNT prefixes (expected >=100)" >&2
  exit 1
fi

{
  echo "# AWS EC2 ranges for all eu-* regions, excluding the DYNAMODB service."
  echo "# Consumed by forkop section Zapret_GameServers_UDP (UDP 1024-65535 only)."
  echo "# Regenerated automatically - do not edit by hand."
  echo "# prefixes: $COUNT"
  cat "$PFX"
} > lists/aws-eu-ec2.lst

echo "wrote lists/aws-eu-ec2.lst ($COUNT prefixes)"

# sing-box source rule-set. Needed because forkop's "rule_set_with_subnets"
# option builds a proper route rule from it, while a plain .lst consumed via
# "domain_ip_lists" only fills the nftables set and leaves sing-box without a
# matching rule (traffic then falls through to the catch-all outbound).
{
  printf '{
  "version": 3,
  "rules": [
    {
      "ip_cidr": [
'
  awk 'NR>1 { printf ",
" } { printf "        \"%s\"", $0 }' "$PFX"
  printf '
      ]
    }
  ]
}
'
} > lists/aws-eu-ec2.json

echo "wrote lists/aws-eu-ec2.json ($COUNT prefixes)"
