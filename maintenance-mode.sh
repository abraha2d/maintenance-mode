#!/usr/bin/env bash

set -eu

. "$(dirname "$(readlink -e "$0")")"/utils.sh

current_ip=$(dig @127.0.0.1 "${DOMAINS[0]}" +short)

while true; do
    next_ip=$(select_public_ip)

    if [ -z "$next_ip" ] && [ "$current_ip" != "$MAINTENANCE_IP" ]; then
        # No good public IPs were found, and not in maintenance mode
        bind_slave_to_master
        notify "maintenance-mode: ENABLED" "No healthy public IPs were found."
        next_ip=$MAINTENANCE_IP
    elif [ -n "$next_ip" ] && [ "$current_ip" == "$MAINTENANCE_IP" ]; then
        # In maintenance mode, but a good public IP was found
        bind_master_to_slave
        notify "maintenance-mode: DISABLED" "A healthy public IP was found."
    fi

    if [ "$next_ip" != "$current_ip" ]; then
        # The current public IP is not the best
        set_public_ip "$next_ip"
        notify "maintenance-mode: CHANGED" "Updated from $current_ip to $next_ip."
        current_ip=$next_ip
    fi

    sleep 1;
done
