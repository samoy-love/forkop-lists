#!/usr/bin/env bash
# Пересобирает списки подсетей, которые роутер тянет через domain_ip_lists.
set -euo pipefail

SRC="https://ip-ranges.amazonaws.com/ip-ranges.json"
RAW="$(mktemp)"
PFX="$(mktemp)"
trap 'rm -f "$RAW" "$PFX"' EXIT

curl -fsSL --retry 5 --retry-delay 3 -o "$RAW" "$SRC"

# Префиксы EC2 европейских регионов И региона GLOBAL, МИНУС префиксы DYNAMODB.
#
# Почему нужен GLOBAL: серверы матчей Wardogs живут в 54.115.0.0/16, а этот
# префикс опубликован AWS с region="GLOBAL", а не "eu-*". Пока фильтр брал
# только eu-*, игровой UDP не попадал в обход, и через полторы секунды после
# начала матча игрока выбрасывало. Проверено 09.09.2026: 54.115.0.0/16
# присутствует в ip-ranges.json как service=EC2, region=GLOBAL.
#
# Почему исключается DYNAMODB: игры измеряют задержку до региона, открывая
# TCP-соединение к dynamodb.<region>.amazonaws.com. Если эти префиксы завернуть
# в sing-box, рукопожатие завершается локально на роутере и все регионы
# показывают ~5 мс, что ломает выбор сервера. Замер: eu-north-1 показывал
# 4.7 мс при перехвате против 27.1 мс без него.
jq -r '
  ([.prefixes[] | select(.service == "DYNAMODB") | .ip_prefix] | unique) as $ddb
  | .prefixes[]
  | select(.service == "EC2")
  | select((.region | startswith("eu-")) or (.region == "GLOBAL"))
  | select(.ip_prefix as $p | ($ddb | index($p)) | not)
  | .ip_prefix
' "$RAW" | sort -u > "$PFX"

COUNT=$(wc -l < "$PFX")
if [ "$COUNT" -lt 100 ]; then
  echo "отказываюсь публиковать: всего $COUNT префиксов (ожидалось >=100)" >&2
  exit 1
fi

# Страховка: подсеть серверов матчей Wardogs обязана быть в списке.
if ! grep -qx '54\.115\.0\.0/16' "$PFX"; then
  echo "отказываюсь публиковать: в списке нет 54.115.0.0/16 (серверы матчей Wardogs)" >&2
  exit 1
fi

{
  echo "# Диапазоны AWS EC2: все регионы eu-* плюс GLOBAL, без сервиса DYNAMODB."
  echo "# Потребитель — роутер OpenWrt, секции Tachyon/Forkop через domain_ip_lists."
  echo "# Файл собирается автоматически, руками не править."
  echo "# префиксов: $COUNT"
  cat "$PFX"
} > lists/aws-eu-ec2.lst

echo "записан lists/aws-eu-ec2.lst ($COUNT префиксов)"

write_source_ruleset() {
  local input="$1"
  local output="$2"

  jq -R -s '
    {version: 3, rules: [
      {ip_cidr: (
        split("\n")
        | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
        | map(select(length > 0 and (startswith("#") | not)))
      )}
    ]}
  ' "$input" > "$output"
}

# Source rule-sets are generated from the plain lists so the two public formats
# cannot silently drift apart.
write_source_ruleset lists/aws-eu-ec2.lst lists/aws-eu-ec2.json
write_source_ruleset lists/wardogs-game-ips.lst lists/wardogs-game-ips.json

SING_BOX_BIN="${SING_BOX_BIN:-sing-box}"
"$SING_BOX_BIN" rule-set compile --output lists/aws-eu-ec2.srs lists/aws-eu-ec2.json
"$SING_BOX_BIN" rule-set compile --output lists/wardogs-game-ips.srs lists/wardogs-game-ips.json

echo "записаны source и binary rule-sets из .lst списков"
