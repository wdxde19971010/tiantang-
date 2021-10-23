#!/bin/sh

set -e

if [ "$SKIP_UPNP_AUTOCONFIG" = true ]; then
  exit 0
fi

RULE_NAME_REGEX="tiantang:(TCP|UDP):"

OLD_IFS="$IFS"
IFS=$(printf '\n')

# Retrieve the IP address of the active ethernet interface
ETH_IP_ADDRESS=$(ip a sh up scope global | grep inet | awk '{split($2,a,"/"); print a[1]}')

LISTENING_PORTS=$(netstat -nlp | grep qemu)

EXISTING_RULES=$(upnpc -l | grep -E "$RULE_NAME_REGEX" | awk '{print $2, $3}')

printf "[%s] IP address of the ethernet interface is $ETH_IP_ADDRESS\n" "$TIME"
printf "[%s] Outputs of netstat are:\n${LISTENING_PORTS}\n" "$TIME"
printf "[%s] Existing UPnP rules of tiantang are:\n${EXISTING_RULES}\n" "$TIME"

# Find out ports listening and add the UPnP rule
for line in $LISTENING_PORTS
do
  ADDR_AND_PORT=$(echo "$line" | awk '{print $4}')
  PROTOCOL=$(echo "$line" | awk '{print toupper($1)}')

  LISTENING_ADDR=$(echo "$ADDR_AND_PORT" | awk '{split($1,a,":"); print a[1]}')
  LISTENING_PORT=$(echo "$ADDR_AND_PORT" | awk '{split($1,a,":"); print a[2]}')

  if [ "$LISTENING_ADDR" = "127.0.0.1" ]; then
    continue
  fi

  RULE_TO_BE_CHECKED="${PROTOCOL} ${LISTENING_PORT}->${ETH_IP_ADDRESS}:${LISTENING_PORT}"
  printf "[%s] Checking if \"${RULE_TO_BE_CHECKED}\" exists in the UPnP rules...\n" "$TIME"

  # Continue to the next one if the current port is forwarded
  if echo "$EXISTING_RULES" | grep -q "$RULE_TO_BE_CHECKED"; then
    printf "[%s] Found \"${RULE_TO_BE_CHECKED}\". Continueing to the next one.\n" "$TIME"
    continue
  fi

  printf "========Adding new rule========\n"
  upnpc -e "tiantang:$PROTOCOL:$LISTENING_PORT" -a "$ETH_IP_ADDRESS" "$LISTENING_PORT" "$LISTENING_PORT" "$PROTOCOL"
  printf "==========Rule added===========\n"
  printf "\n"
done

for line in ${EXISTING_RULES}
do
  PROTOCOL=$(echo "${line}" | awk '{print tolower($1)}')
  PORT=$(echo "${line}" | awk '{split($2,a,"->"); print a[1]}')
  NETSTAT_TARGET_OUTPUT="0.0.0.0:${PORT}"
  
  MATCHED_LINE_COUNT=$(echo "${LISTENING_PORTS}" | grep "${PROTOCOL}" | grep -c "${NETSTAT_TARGET_OUTPUT}")

  if [ "${MATCHED_LINE_COUNT}" = 0 ]; then
    printf "[%s] Found invalid rule ${PORT}/${PROTOCOL}\n" "$TIME"
    printf "========Deleting rule========\n"
    upnpc -d "${PORT}" "${PROTOCOL}"
    printf "========Rule deleted=========\n"
  fi
done

IFS="$OLD_IFS"
