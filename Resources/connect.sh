#!/usr/bin/env bash

set -e

SSH_USER=juanma
HOST=gaia.tecnologica.ar
SSH_PORT=22
PORT=5432
CONTAINER=sem-com-ar
#CONTAINER=development-tecnologica-ar
NETWORK=reverse-proxy
#NETWORK=web-proxy
LOCALHOST=127.0.0.1
LOCALPORT=25432
#LOCALPORT=15432
LOG_FILE="${LOG_FILE:-/tmp/connect.log}"
SSH_OPTIONS=()

if [[ -n "${SSH_CONNECT_TIMEOUT:-}" ]]; then
  SSH_OPTIONS+=(-o "ConnectTimeout=$SSH_CONNECT_TIMEOUT")
fi

if [[ -n "${SSH_SERVER_ALIVE_INTERVAL:-}" ]]; then
  SSH_OPTIONS+=(-o "ServerAliveInterval=$SSH_SERVER_ALIVE_INTERVAL")
fi

if [[ -n "${SSH_SERVER_ALIVE_COUNT_MAX:-}" ]]; then
  SSH_OPTIONS+=(-o "ServerAliveCountMax=$SSH_SERVER_ALIVE_COUNT_MAX")
fi

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -u USER        SSH user (default: $SSH_USER)
  -H HOST        SSH host (default: $HOST)
  -P PORT        SSH port (default: $SSH_PORT)
  -p PORT        Remote service port (default: $PORT)
  -c CONTAINER   Docker container name (default: $CONTAINER)
  -n NETWORK     Docker network name (default: $NETWORK)
  -b ADDRESS     Local bind address (default: $LOCALHOST)
  -l PORT        Local forwarded port (default: $LOCALPORT)
  -h             Show this help
EOF
}

OPTIONS=$(getopt "u:H:P:p:c:n:b:l:h" "$@")
if [ $? -ne 0 ]; then
  usage
  exit 1
fi

eval set -- "$OPTIONS"

while true; do
  case "$1" in
    -u)
      SSH_USER=$2
      shift 2
      ;;
    -H)
      HOST=$2
      shift 2
      ;;
    -P)
      SSH_PORT=$2
      shift 2
      ;;
    -p)
      PORT=$2
      shift 2
      ;;
    -c)
      CONTAINER=$2
      shift 2
      ;;
    -n)
      NETWORK=$2
      shift 2
      ;;
    -b)
      LOCALHOST=$2
      shift 2
      ;;
    -l)
      LOCALPORT=$2
      shift 2
      ;;
    -h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
  esac
done

IP=$(ssh "${SSH_OPTIONS[@]}" -p "$SSH_PORT" "$SSH_USER@$HOST" "docker network inspect $NETWORK | sed -n '/$CONTAINER/,/IPv4Address/p' | grep IPv4Address | cut -d: -f2 | tr -d ' \",' | cut -d/ -f1")

if [[ -z "${RUNNING_IN_BACKGROUND:-}" ]]; then
    export RUNNING_IN_BACKGROUND=1

    if command -v setsid >/dev/null 2>&1; then
        setsid "$0" "$@" > "$LOG_FILE" 2>&1 < /dev/null &
        echo "Script enviado al segundo plano con setsid. PID: $!"
    else
        nohup "$0" "$@" > "$LOG_FILE" 2>&1 < /dev/null &
        echo "Script enviado al segundo plano con nohup. PID: $!"
    fi
    exit 0
fi

echo "Script iniciado en segundo plano"
echo "PID: $$"
echo "Log: $LOG_FILE"
echo "Estableciendo puente $HOST:$SSH_PORT->$IP:$PORT => $LOCALHOST:$LOCALPORT"

exec ssh "${SSH_OPTIONS[@]}" -p "$SSH_PORT" -N -L "$LOCALHOST:$LOCALPORT:$IP:$PORT" "$SSH_USER@$HOST"
