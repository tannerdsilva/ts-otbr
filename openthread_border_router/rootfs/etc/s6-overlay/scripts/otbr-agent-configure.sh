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
fi