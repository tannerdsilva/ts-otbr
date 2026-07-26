#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# ==============================================================================
# Configure OTBR depending on add-on settings
# ==============================================================================

ot-ctl trel enable

if bashio::config.true 'nat64'; then
    bashio::log.info "Enabling NAT64."
    ot-ctl nat64 enable
    ot-ctl dns server upstream enable
fi

mdns_localhostname="$(hostname)-otbr"
bashio::log.info "Setting OpenThread mDNS local hostname to ${mdns_localhostname}."
ot-ctl mdns localhostname "${mdns_localhostname}"
ot-ctl mdns enable

# To avoid asymmetric link quality the TX power from the controller should not
# exceed that of what other Thread routers devices typically use.
ot-ctl txpower 6

ot-ctl br enable

# ==============================================================================
# Custom OMR Prefix + Preference
# ==============================================================================
for i in {1..40}; do
    if ot-ctl state >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# ==============================================================================
# Route preference (applies to external routes published by the BR)
# ==============================================================================
ROUTE_PRF=$(bashio::config 'custom_route_preference' 'med')
bashio::log.info "Setting Border Router route preference to ${ROUTE_PRF}"
ot-ctl br routeprf "${ROUTE_PRF}" || bashio::log.warning "Failed to set br routeprf"