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
# Custom OMR Prefix (stable prefix across restarts)
# ==============================================================================
if bashio::config.has_value 'custom_omr_prefix'; then
    CUSTOM_PREFIX=$(bashio::config 'custom_omr_prefix')
    if [[ "$CUSTOM_PREFIX" =~ ^fd[0-9a-f:]+::/64$ ]]; then
        # valid ULA /64
        bashio::log.info "Applying custom OMR prefix: ${CUSTOM_PREFIX}"
        ot-ctl br omrconfig custom "${CUSTOM_PREFIX}" low
        # ... rest of the code
    else
        bashio::log.warning "Invalid custom_omr_prefix (must be fdxx:...::/64). Ignoring."
    fi
    if [[ -n "$CUSTOM_PREFIX" ]]; then
        bashio::log.info "Applying custom OMR prefix: ${CUSTOM_PREFIX}"

        # Apply the custom prefix
        if ot-ctl br omrconfig custom "${CUSTOM_PREFIX}" low; then
            bashio::log.info "Custom OMR prefix applied successfully"

            # Restart Thread interface to ensure it takes effect
#             bashio::log.info "Restarting Thread interface to apply new prefix..."
#             ot-ctl thread stop
#             sleep 2
#             ot-ctl thread start
        else
            bashio::log.error "Failed to apply custom OMR prefix"
        fi
    fi
fi