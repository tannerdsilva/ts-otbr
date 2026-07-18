#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# ==============================================================================
# Configure OTBR depending on add-on settings
# ==============================================================================

# ==============================================================================
# Custom BR ULA Prefix (parent of all OMR prefixes - most important for stability)
# ==============================================================================
if bashio::config.has_value 'custom_br_ula_prefix'; then
    ULA_PREFIX=$(bashio::config 'custom_br_ula_prefix')
    bashio::log.info "Setting custom BR ULA prefix: ${ULA_PREFIX}"

    if ot-ctl br ulaprefix set "${ULA_PREFIX}"; then
        bashio::log.info "✅ BR ULA prefix applied successfully"
    else
        bashio::log.error "❌ Failed to set BR ULA prefix"
    fi
fi

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
# Custom OMR Prefix (stable across restarts)
# ==============================================================================
if bashio::config.has_value 'custom_omr_prefix'; then
    CUSTOM_PREFIX=$(bashio::config 'custom_omr_prefix')
    bashio::log.info "Custom OMR prefix requested: ${CUSTOM_PREFIX}"

    if [[ -z "$CUSTOM_PREFIX" ]]; then
        bashio::log.info "No custom prefix set — using auto behavior"
    else
        # Wait for ot-ctl to be ready
        bashio::log.info "Waiting for ot-ctl to be ready..."
        for i in {1..40}; do
            if ot-ctl state >/dev/null 2>&1; then
                bashio::log.info "ot-ctl is ready (attempt $i)"
                break
            fi
            sleep 1
        done

        # Apply the custom prefix
        if ot-ctl br omrconfig custom "${CUSTOM_PREFIX}" med; then
            bashio::log.info "✅ Successfully applied custom OMR prefix: ${CUSTOM_PREFIX}"

            # Force Thread restart to ensure the network picks it up
            bashio::log.info "Restarting Thread interface to apply changes..."
            ot-ctl thread stop
            sleep 3
            ot-ctl thread start
        else
            bashio::log.error "❌ Failed to apply custom OMR prefix"
        fi
    fi
else
    bashio::log.info "No custom_omr_prefix configured in add-on settings"
fi