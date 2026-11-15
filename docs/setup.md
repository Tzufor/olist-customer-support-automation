# Setup

## Database

Use a new Supabase project and run these scripts as its database owner:
1. sql/01_schema.sql
2. sql/02_functions.sql
3. sql/03_access.sql

The schema reproduces exported columns, constraints, indexes, and RLS flags. It is not a full pg_dump: existing grants, policies, triggers, sequence positions, and live data were not exported. The access script deliberately grants no client Data API access.

Import CSVs with header matching through the table editor:

| Source filename | Table |
| --- | --- |
| olist_customers_dataset.csv | customers |
| olist_orders_dataset.csv | orders |
| olist_products_dataset.csv | products |
| olist_sellers_dataset.csv | sellers |
| olist_order_items_dataset.csv | order_items |
| olist_order_payments_dataset.csv | order_payments |
| olist_order_reviews_dataset.csv | order_reviews |
| product_category_name_translation.csv | category_translation |

Preserve empty values as NULL and identifier/ZIP fields as text. Do not import source data into compensation_requests, support_tickets, review_followups, or n8n_chat_histories. These start empty.

## n8n

Import workflows/olist-support.json into a new workflow.
Select your PostgreSQL credential on every Postgres node and the memory node, and select your OpenAI credential on the model node. The exported model is gpt-5-mini; API use may incur charges.

Connection credentials, workflow instance metadata, and webhook ID were removed. Configure a fresh chat endpoint when needed. No account access or API secrets are included.

The demo was run using the database-owner connection. RLS does not restrict a privileged owner connection: this is not a least-privilege production configuration. Before public deployment, add authentication, order ownership checks, rate limits, and a narrowly privileged database role.

Open the test chat to exercise customer support. Start the review branch from the manual trigger. Its query processes at most 10 reviews per run. Re-running the whole branch selects the next unprocessed batch; repeating only the save step with the same inputs should return already_processed.

No schedule is configured, and the workflow export is inactive.
