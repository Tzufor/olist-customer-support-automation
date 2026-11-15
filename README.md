# Olist Customer Support Automation

An n8n and PostgreSQL demo that connects conversational support with proactive review triage.

**Built by Tzuf Horovitz | n8n · Supabase/PostgreSQL · OpenAI**

The project uses an Olist dataset containing 99,441 orders. It demonstrates two workflows: customers can ask about orders and request policy-based actions; a separate manual batch identifies low-rated reviews and prepares support tickets.

## Two workflows, one database

| Workflow | Input | Outcome |
| --- | --- | --- |
| Customer support | Chat message and order ID | Order details, simulated delay compensation, return approval, or a support ticket |
| Review follow-up | Up to 10 unprocessed reviews rated 1 or 2 | English analysis, issue category, and a linked support ticket |

The model interprets messages and writes responses. Parameterized SQL and database functions validate actions, calculate compensation, and store results. The review pipeline preserves identifiers from SQL rather than trusting the model to reproduce them.

## Architecture

```mermaid
flowchart TD
    C[Customer chat] --> A[Support agent]
    A --> M[Postgres chat memory]
    A --> L[Order lookup]
    A --> F[Compensation and return functions]
    A --> T[Support tickets]
    R[Manual review scan] --> Q[Unprocessed low-rated reviews]
    Q --> B[Review analysis agent]
    B --> P[Structured output parser]
    B --> S[Atomic follow-up recording]
    S --> T
    S --> D[Review tracking]
```

The parser constrains the review agent's output; it is an attached sub-node in n8n. Both agents share an OpenAI model configuration, but only the chat agent has conversation memory.

## What it demonstrates

- Order lookup across items, products, payments, reviews, and existing compensation requests.
- PostgreSQL chat memory with a 20-interaction context-window setting.
- SQL-calculated delay compensation, with fixed-value vouchers based on the current order total.
- Per-item standard return requests recorded as `awaiting_return`; approval does not issue a refund.
- Manual escalation for damaged items, wrong items, and disputes.
- Structured review classification and English summaries of Portuguese feedback.
- Database-backed duplicate prevention and review-to-ticket traceability.

## Demo policy

The reference date is fixed at **2018-10-18** to work with historical data. Business days mean Monday–Friday, without holiday calendars.

| Delivery delay | Available simulated benefit |
| --- | --- |
| 1–3 business days | Fixed voucher worth 10% of the current order total |
| 4–7 | 15% refund OR fixed voucher worth 20% |
| 8–14 | 30% refund |
| 15+ | Full refund OR free replacement, including eventual delivery |

Standard returns require delivery within 30 calendar days, unused condition, original packaging, and tags, subject to exclusions. Expected refunds exclude shipping and account for prior compensation. See the limitations below before relying on this calculation.

## Files

- `workflows/olist-support.json`: sanitized n8n import, with credentials removed.
- `sql/01_schema.sql`: 12 empty tables, constraints, indexes, and RLS.
- `sql/02_functions.sql`: three exported business functions.
- `sql/03_access.sql`: explicit Supabase public-role restrictions for the demo.
- `docs/setup.md`: installation and data import.
- `docs/validation.md`: observed tests and untested cases.
- `docs/limitations.md`: known limitations and production gaps.

## Quick start

Use a **new disposable Supabase project**, run SQL scripts in numeric order, import the eight source CSVs, import the n8n workflow, and configure your own PostgreSQL and OpenAI credentials. Follow [setup instructions](docs/setup.md).

**Do not run the setup scripts on the original working database.** They create fresh objects, not migrations.

## Validation and scope

Manual demonstrations covered order lookup, selected compensation/return scenarios, repeated-request handling, and two review batches (20 reviews). No accuracy benchmark, load test, or measured business savings is claimed.

This is a portfolio prototype: no real money transfers, warehouse integration, replacement fulfillment, or outbound customer contact occurs. Order ID lookup is not customer authentication. Review analyses are drafts for human review.

The export preserves current behavior, including documented [known limitations](docs/limitations.md). Generated SQL has been structurally checked but has not yet been executed against a fresh PostgreSQL instance.

## Data and credits

Uses the Brazilian E-Commerce Public Dataset by Olist. Obtain the original dataset separately and comply with its source license. Source CSV data and chat histories are not included in this repository.

Built with AI-assisted development; workflow design, policy decisions, integration, and manual scenario validation are part of this project.
