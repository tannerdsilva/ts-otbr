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

# ==============================================================================
# Custom OMR Prefix + Preference
# ==============================================================================
if bashio::config.has_value 'custom_omr_prefix'; then
    DESIRED_PREFIX=$(bashio::config 'custom_omr_prefix')
    PREFERENCE=$(bashio::config 'custom_omr_preference' 'med')   # default to med

    if [[ -n "$DESIRED_PREFIX" ]]; then
        bashio::log.info "Custom OMR prefix requested: ${DESIRED_PREFIX} (preference: ${PREFERENCE})"

        # Wait until ot-ctl is ready
        for i in {1..40}; do
            if ot-ctl state >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done

        # Check if already set correctly
        CURRENT=$(ot-ctl br omrprefix local 2>/dev/null | awk '{print $2}' || true)

        if [[ "$CURRENT" == "$DESIRED_PREFIX" ]]; then
            bashio::log.info "✅ Custom OMR prefix already set to ${DESIRED_PREFIX}"
        else
            bashio::log.info "Applying custom OMR prefix: ${DESIRED_PREFIX} with preference ${PREFERENCE}"

            if ot-ctl br omrconfig custom "${DESIRED_PREFIX}" "${PREFERENCE}"; then
                bashio::log.info "✅ Successfully applied custom OMR prefix: ${DESIRED_PREFIX} (${PREFERENCE})"
                sleep 2
            else
                bashio::log.error "❌ Failed to apply custom OMR prefix"
            fi
        fi
    fi
else
    # Get the Thread network name
    NETWORK_NAME=$(ot-ctl dataset active 2>/dev/null | grep -oP 'NetworkName: \K.*' || echo "ha-thread-default")

    # Generate a deterministic ULA /64 from the network name
    HASH=$(echo -n "$NETWORK_NAME" | sha256sum | cut -c1-16)
    GENERATED_PREFIX="fd${HASH:0:2}:${HASH:2:4}:${HASH:6:4}:${HASH:10:4}::/64"

    bashio::log.info "No custom OMR prefix set. Generating deterministic prefix from network name '${NETWORK_NAME}': ${GENERATED_PREFIX}"

    # Apply it
    if ot-ctl br omrconfig custom "${GENERATED_PREFIX}" med; then
        bashio::log.info "✅ Applied deterministic OMR prefix: ${GENERATED_PREFIX}"
    else
        bashio::log.error "Failed to apply deterministic OMR prefix"
    fi
fi