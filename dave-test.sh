#!/bin/bash
# Helper script to test Dave sandbox

DAVE_URL="http://127.0.0.1:18790"
DAVE_TOKEN="dave-sandbox-token-12345"

case "$1" in
  status)
    curl -s "$DAVE_URL/health"
    ;;
  logs)
    docker logs dave-sandbox --tail 50
    ;;
  restart)
    docker restart dave-sandbox
    ;;
  stop)
    docker stop dave-sandbox
    ;;
  start)
    docker start dave-sandbox
    ;;
  shell)
    docker exec -it dave-sandbox /bin/bash
    ;;
  *)
    echo "Usage: $0 {status|logs|restart|stop|start|shell}"
    echo ""
    echo "Dave Sandbox: http://127.0.0.1:18790"
    echo "Token: dave-sandbox-token-12345"
    ;;
esac
