export function getPricingURL(instanceId) {
  // Self-hosted instance: point to the generic pricing page without leaking the
  // instance id to baserow.io. The `instanceId` argument is intentionally unused.
  return 'https://baserow.io/pricing'
}
