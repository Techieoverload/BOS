#!/bin/bash
# Runs once: creates this unit's private access token.
[ -f /etc/beacon/env ] && exit 0
TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(24))")
printf 'BEACON_TOKEN=%s\nBEACON_BIND=127.0.0.1\nBEACON_PORT=8080\n' "$TOKEN" > /etc/beacon/env
chmod 600 /etc/beacon/env
