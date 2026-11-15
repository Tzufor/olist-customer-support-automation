# Known limitations

## Business logic to review before expanding the demo

- The current return function sums all non-rejected delivery-delay amounts, including vouchers and pending/approved entries, rather than explicitly limiting deductions to completed monetary refunds. This behavior is preserved from the source export and needs a deliberate policy decision and regression tests.
- Deductions are allocated against return requests in creation order, not proportionally across items. A zero expected refund is rejected without reserving a deduction. Multi-item edge cases need testing.
- Some exclusions rely on customer declarations and model-supplied booleans; unknown exclusion information can become false.
- The lookup query emits a fixed compensation_execution_status label even when existing requests are returned. The action tool and stored records are authoritative.
- Active support tickets are reused by order and broad reason. Different issues can share that scope. Review analyses remain in review_followups, but repeated chat-ticket submissions do not append a new claim.
- Return codes use the first six characters of the order ID and item number; uniqueness is not guaranteed by that format.

## Model quality

Manual output inspection found occasional mistranslation of poor-quality slang as suspected counterfeiting and imperfect date reasoning. Prompt revisions reduce these issues but do not establish an accuracy guarantee. Human review is required. Schema validation checks structure, not factual correctness.

## Operational scope

- Historical dataset and fixed reference date, not live order state.
- Manual batches, no scheduling or queue claiming. Concurrent scans may repeat model work even though the database protects duplicate recording.
- No real payment, shipment, warehouse, outbound message, or agent notification integration.
- No customer authentication/ownership authorization or public-chat abuse controls.
- No concurrency, throughput, adversarial-input, or comprehensive policy-boundary test suite.
- RLS enabled with backend owner access; not a complete production security design.
- The source dataset lacks customer email/phone and actual product names/descriptions.
