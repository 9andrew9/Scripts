#!/bin/bash

# Create date:   2018-09-10
# Modification:  2023-16-11
# Autor:         Skvortsov Andrew
# Email:         avs@europlan.ru
# VersionZabbix: 6.4
# VersionScript: 2.0.1

temp="/var/log/temp.log"
result="/var/log/report_sla.csv"
urlZabbix="http://your-adress/api_jsonrpc.php"
apiKey="your-apiKey"
mailAdmin="avs85@europlan.ru aao9@europlan.ru rsm1@europlan.ru"
mountAgo=$(date --date='1 months ago' "+%Y-%m-%d %T")
moutnAgoUnixTime=$(date -d "$mountAgo" "+%s")
nowTime=$(date "+%Y-%m-%d %T")
nowUnixTime=$(date +%s)
>$temp
>$result

GetServiceGroup() {
    curl -sS -i -X POST -H 'Content-Type: application/json;' -d ' {
  "jsonrpc": "2.0",
  "method": "service.get",
  "params": {
    "output": ["serviceid","name"],
    "selectChildren": ["serviceid","name","sortorder"],
    "selectParents": ["name"],
    "filter": {"status": -1},
    "sortfield": "sortorder"
  },
  "auth": "'"$apiKey"'",
  "id": 1
  }' ${urlZabbix} | egrep '^{' | jq .result[] | jq -r '(select(.parents == []) | ([.serviceid,.name]))| @tsv'
}

GetServiceIdsInGroup() {
    serviceGroupId="$1"
    curl -sS -i -X POST -H 'Content-Type: application/json;' -d ' {
  "jsonrpc": "2.0",
  "method": "service.get",
  "params": {
    "serviceids": '${serviceGroupId}',
    "output": ["serviceid","name"],
    "selectChildren": ["serviceid","name","sortorder"],
    "selectParents": ["name"],
    "filter": {"status": -1},
    "sortfield": "sortorder"
  },
  "auth": "'"$apiKey"'",
  "id": 1
  }' ${urlZabbix} | egrep '^{' | jq .result[] | jq -r '([.children[].serviceid])'
}

GetGroupTagSla() {
    serviceGroupId="$1"
    curl -sS -i -X POST -H 'Content-Type: application/json;' -d ' {
  "jsonrpc": "2.0",
  "method": "service.get",
  "params": {
    "serviceids": '${serviceGroupId}',
    "output": ["serviceid","name"],
    "selectChildren": ["serviceid","name","sortorder"],
    "selectParents": ["name"],
    "filter": {"status": -1},
    "selectTags": ["value"],
    "sortfield": "sortorder"
  },
  "auth": "'"$apiKey"'",
  "id": 1
  }' ${urlZabbix} | egrep '^{' | jq .result[] | jq -r '(.tags[].value)'
}

GetService() {
    serviceIds=("$1")
    curl -sS -i -X POST -H 'Content-Type: application/json;' -d ' {
  "jsonrpc": "2.0",
  "method": "service.get",
  "params": {
    "serviceids":'"$serviceIds"',
    "selectChildren": ["serviceid","name","sortorder"],
    "selectTags": ["value"],
    "filter": {"status": -1},
    "sortfield": "sortorder"
  },
  "auth": "'"$apiKey"'",
  "id": 1
  }' ${urlZabbix} | egrep '^{' | jq .result[] | jq -r '[ .name +",", .serviceid+",", .tags[].value+","] | @tsv'
}

GetSlaService() {
    slaId="$1"
    serviceid="$2"
    curl -sS -i -X POST -H 'Content-Type: application/json;' -d '{
    "jsonrpc": "2.0",
      "method": "sla.getsli",
      "params": {
      "slaid": "'"$slaId"'",
      "serviceids": "'"$serviceid"'",
      "periods": 1
    },
    "auth": "'"$apiKey"'",
    "id": 1
  }' ${urlZabbix} | egrep '^{' | jq -r '(.result | [.sli[][].sli]) | @tsv'
}

GetSlaReport() {
    GetServiceGroup | while read data; do
        serviceGroupId=$(echo $data | awk '{print $1}')
        serviceGroupName=$(echo $data | awk '{print $2}')
        serviceIdsGroup=$(GetServiceIdsInGroup $serviceGroupId)
        groupTagSla=$(GetGroupTagSla $serviceGroupId)
        echo "${serviceGroupName}"
        GetService "${serviceIdsGroup}" | while read service; do
            serviceName=$(echo $service | cut -d',' -f1)
            serviceId=$(echo $service | cut -d',' -f2)
            serviceSLA=$(GetSlaService $groupTagSla $serviceId)
            echo -e "; $serviceName ; $serviceSLA"
        done
    done
}

SendReport() {
    cat $temp |
        sed "1i ;;;Выгрузка с ${mountAgo};По ${nowTime}" |
        sed "2i Группа; Сервис; SLA в %" |
        iconv -f UTF8 -t CP1251 >>$result
    echo Report_SLA |
        mutt -e "set crypt_use_gpgme=no" -s "sla" $mailAdmin -a $result
}

GetSlaReport >>$temp
SendReport
