# Validation record

These are manually observed demo results, not automated test results.

| Scenario | Observed outcome |
| --- | --- |
| Delivered before estimate: e481f51cbdc54678b7cc49136f2d6af7 | 0 business days late; no delay refund |
| Six-day delay: 001c85b5f68d2be0cb0797afc9e8ce9a | 16.91 refund or 22.54 fixed voucher |
| Repeated compensation request | Existing request returned, no additional amount |
| Return awaiting warehouse receipt | Expected refund displayed; not claimed as issued |
| Existing return with prior compensation | 49.90 minus 15.00 = 34.90; shipping not subtracted twice |
| Review batch 1 | 10 follow-ups recorded |
| Repeat save of batch 1 | Same ticket IDs returned as already_processed |
| Review query after batch 1 | Previously handled reviews excluded |
| Review batch 2 | 10 additional follow-ups recorded |
| Same review ID on different orders | Separate tracking records and tickets |
| Blank review text | unknown classification |
| Read-back from database | Original review, order/customer, analysis and ticket joined correctly |

The 15.00 prior-compensation return example used a manually seeded test record; it is not evidence that every deduction edge case works.

Still untested: fresh database installation, simultaneous writes, all policy boundaries, failure recovery, high-volume review scans, and model accuracy on a labeled benchmark.
