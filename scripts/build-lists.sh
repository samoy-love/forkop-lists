#!/usr/bin/env bash
# Пересобирает списки подсетей, которые роутер тянет через remote_subnet_lists.
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
  echo "# Потребитель — роутер OpenWrt, секция Zapret_Games через remote_subnet_lists."
  echo "# Файл собирается автоматически, руками не править."
  echo "# префиксов: $COUNT"
  cat "$PFX"
} > lists/aws-eu-ec2.lst

echo "записан lists/aws-eu-ec2.lst ($COUNT префиксов)"

# Тот же список в виде source rule-set для sing-box.
#
# ВНИМАНИЕ: подключать этот .json через rule_set_with_subnets НЕЛЬЗЯ —
# sing-box 1.14 отвергает IP-фильтры в DNS-правилах и падает на старте с
# "Legacy Address Filter Fields in DNS rules is deprecated". Роутер потребляет
# .lst через remote_subnet_lists. Файл оставлен для совместимости.
#
# JSON собирается через jq, а не printf+awk: прежняя версия скрипта падала,
# потому что внутри awk-программы стоял настоящий перевод строки вместо \n,
# и awk отвечал "unterminated string" (все прогоны с 08.09 были красные).
jq -R -s -c '
  {version: 3, rules: [ {ip_cidr: (split("\n") | map(select(length > 0))) } ]}
' "$PFX" | jq '.' > lists/aws-eu-ec2.json

echo "записан lists/aws-eu-ec2.json ($COUNT префиксов)"
