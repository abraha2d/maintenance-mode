#!/usr/bin/env bash

set -eu

RE_TYPE_MASTER='(?<!\w)type\s+master\s*(?=;)'
RE_TYPE_SLAVE='(?<!\w)type\s+slave\s*(?=;)'

RE_ALLOW_UPDATE='(?<!\w)allow-update\s*{[^}]*}\s*(?=;)'
RE_MASTERS='(?<!\w)masters\s*{[^}]*}\s*(?=;)'

. "$(dirname "$(readlink -e "$0")")"/settings.conf

# re-configure bind as slave
bind_master_to_slave() {
    local _masters
    _masters="masters { ${PUBLIC_IPS[*]/%/;} }"

    echo "[maintenance-mode] Reconfiguring BIND as slave..."
    perl -0pi -e "s/$RE_TYPE_MASTER/type slave/g" /etc/bind/named.conf.local
    perl -0pi -e "s/$RE_ALLOW_UPDATE/$_masters/g" /etc/bind/named.conf.local

    systemctl restart bind9.service

    for _domain in "${DOMAINS[@]}"; do
        rndc retransfer "$_domain" 2>/dev/null || echo "[maintenance-mode] Sync failed for $_domain... not a zone?"
    done
}

# re-configure bind as master
bind_slave_to_master() {
    local _allow_update
    _allow_update="allow-update { key $NSUPDATE_KEY_NAME; }"

    echo "[maintenance-mode] Reconfiguring BIND as master..."
    perl -0pi -e "s/$RE_TYPE_SLAVE/type master/g" /etc/bind/named.conf.local
    perl -0pi -e "s/$RE_MASTERS/$_allow_update/g" /etc/bind/named.conf.local

    systemctl restart bind9.service
}

# return current best of $PUBLIC_IPS
select_public_ip() {
    local _ip

    for _ip in "${PUBLIC_IPS[@]}"; do
        if ping -A -c5 -n -W1 "$_ip" >/dev/null; then
            echo "$_ip"
            return
        fi
    done
}

# set_public_ip <ip>
# update all $DOMAINS to point to <ip>
set_public_ip() {
    local _domain
    local _ip
    local _nsupdate_input
    local _sleep

    _ip=$1
    _nsupdate_input=$(mktemp)

    echo "server $_ip" >>"$_nsupdate_input"
    for _domain in "${DOMAINS[@]}"; do
        {
            echo "update delete $_domain. A"
            echo "update add $_domain. 1 A $_ip"
            echo
         } >>"$_nsupdate_input"
    done
    echo "send" >>"$_nsupdate_input"

    echo "[maintenance-mode] Updating public IP to $_ip..."
    for _sleep in 1 2 4 8 16; do
        nsupdate -k $NSUPDATE_KEY_PATH "$_nsupdate_input" && return;
        sleep $_sleep
    done
}

# notify <subj> <msg>
# send notifications to $NOTIFY_EMAILS
notify() {
    local _email
    local _msg
    local _subj

    _subj=$1
    _msg=$2

    echo "($_subj) $_msg"

    for _email in "${NOTIFY_EMAILS[@]}"; do
        mail -s "$_subj" -a "From:$NOTIFY_FROM" "$_email" <<<"$_msg"
    done
}
