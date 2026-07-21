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

# Keep TX power conservative so we don't create asymmetric links
ot-ctl txpower 6

# ==============================================================================
# Wait until ot-ctl is ready
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

# ==============================================================================
# Disable automatic OMR management so we fully control prefixes
# (this also stops the Routing Manager from injecting a ::/0)
# ==============================================================================
bashio::log.info "Disabling automatic OMR prefix management"
ot-ctl br omrconfig disable || true

# ==============================================================================
# Custom / deterministic OMR + optional on-link prefix
# ==============================================================================
if bashio::config.has_value 'custom_omr_prefix'; then
    DESIRED_OMR=$(bashio::config 'custom_omr_prefix')
    OMR_PRF=$(bashio::config 'custom_omr_preference' 'med')
    DESIRED_ONLINK=$(bashio::config 'custom_onlink_prefix' '')

    bashio::log.info "Custom OMR prefix requested: ${DESIRED_OMR} (preference: ${OMR_PRF})"

    # Remove any previous instance of this prefix (idempotent)
    ot-ctl prefix remove "${DESIRED_OMR}" >/dev/null 2>&1 || true

    # Add as on-mesh OMR prefix WITHOUT the default-route flag (no ::/0)
    # Flags: p=preferred, a=SLAAC, o=on-mesh, s=stable
    if ot-ctl prefix add "${DESIRED_OMR}" paros "${OMR_PRF}"; then
        bashio::log.info "✅ Added OMR prefix ${DESIRED_OMR} (paos ${OMR_PRF})"
    else
        bashio::log.error "❌ Failed to add OMR prefix ${DESIRED_OMR}"
    fi

    if [[ -n "${DESIRED_ONLINK}" ]]; then
        bashio::log.info "Custom on-link prefix requested: ${DESIRED_ONLINK}"
        bashio::log.info "Note: local on-link prefix is still owned by the Routing Manager (PIO on AIL)."
        bashio::log.info "      A deterministic ULA will be used if no better on-link prefix is present."
        # Future-proofing: if a public CLI setter appears we can add it here.
    fi

else
    # -----------------------------------------------------------------
    # No custom OMR → generate a durable /48 ULA from the network name
    # then carve a stable /64 OMR from it
    # -----------------------------------------------------------------
    NETWORK_NAME=$(ot-ctl dataset active 2>/dev/null | grep -oP 'NetworkName: \K.*' || echo "ha-thread-default")

    # 48-bit hash → proper ULA /48  (fdXX:XXXX:XXXX::/48)
    HASH=$(echo -n "${NETWORK_NAME}" | sha256sum | cut -c1-12)
    ULA_48="fd${HASH:0:2}:${HASH:2:4}:${HASH:6:4}::/48"
    GENERATED_OMR="${ULA_48%/*}:0::/64"          # first /64 from the /48

    bashio::log.info "No custom OMR prefix set."
    bashio::log.info "Network name '${NETWORK_NAME}' → durable ULA /48 ${ULA_48}"
    bashio::log.info "Using OMR /64 ${GENERATED_OMR}"

    ot-ctl prefix remove "${GENERATED_OMR}" >/dev/null 2>&1 || true

    if ot-ctl prefix add "${GENERATED_OMR}" paos med; then
        bashio::log.info "✅ Applied deterministic OMR prefix: ${GENERATED_OMR}"
    else
        bashio::log.error "❌ Failed to apply deterministic OMR prefix"
    fi
fi

# Publish the local Network Data changes
if ot-ctl netdata register; then
    bashio::log.info "✅ Network Data registered"
else
    bashio::log.error "❌ netdata register failed"
fi

# Small settle time
sleep 2

# Optional visibility
bashio::log.info "Current local prefixes:"
ot-ctl prefix || true
bashio::log.info "Current OMR / on-link view:"
ot-ctl br omrprefix || true
ot-ctl br onlinkprefix || true