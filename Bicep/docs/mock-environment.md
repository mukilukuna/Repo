# Mock Environment – Known Limitations

## VPN Gateway SKU: Basic

The mock environment uses the **Basic** SKU VPN Gateway instead of `VpnGw1`.

**Why Basic?**
- Cost: ~€25/month vs ~€140/month for VpnGw1.
- The pilot's objective is to produce tunnel metrics (`TunnelConnectionCount`, `TunnelEgressBytes`) for alert rule validation, not to test VPN configuration parity.

**Limitations of Basic SKU:**
- Does not support IKEv2 (production environments use IKEv2 per existing Bicep audit).
- Does not support BGP.
- Cannot be upgraded to a higher SKU — must delete and redeploy.

**Impact on monitoring baseline:**
- None. Alert rules 7–9 (VPN tunnel connectivity, bandwidth) work with the Basic SKU.
- When onboarding a real customer, their production VPN Gateway will be `VpnGw1` or higher.

## AVD Host Pool quota

If AVD quota is unavailable in West Europe, remove the `hostPool` resource from `resources.bicep` and document the gap here.

**Affected alert rules:** 10 (hosts unavailable), 11 (connection errors), 12 (scaling failed).

**Workaround:** Deploy in `northeurope` (typically less saturated) or request a quota increase via Azure Support.

## Cost reduction tips

- **VM:** Deallocate `vm-pilot-mock-weu-001` when not actively testing. Saves ~€30/month.
- **AVD session host:** Deallocate when not testing. Saves ~€30/month.
- **VPN Gateway:** Cannot be deallocated. Delete and redeploy for extended periods of non-use.
- **RSV + Storage:** Minimal cost at rest; no action needed.
