-- Fresh demo database only. Do not run on the existing project.

BEGIN;

SET LOCAL search_path = public, pg_catalog;

CREATE SEQUENCE public.n8n_chat_histories_id_seq;

CREATE TABLE public."category_translation" (
    "product_category_name" text NOT NULL,
    "product_category_name_english" text
);

CREATE TABLE public."compensation_requests" (
    "id" bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    "order_id" text NOT NULL,
    "session_id" text NOT NULL,
    "reason" text DEFAULT 'delivery_delay'::text NOT NULL,
    "resolution_type" text,
    "amount" numeric(12,2),
    "status" text DEFAULT 'pending_review'::text NOT NULL,
    "reference_date" date NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "order_item_id" bigint,
    "customer_description" text,
    "approved_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "is_simulation" boolean DEFAULT true NOT NULL,
    "request_key" uuid DEFAULT gen_random_uuid() NOT NULL,
    "is_unused" boolean,
    "has_original_packaging" boolean,
    "has_tags_attached" boolean,
    "is_excluded_item" boolean DEFAULT false,
    "expected_refund_amount" numeric(10,2),
    "prior_compensation_deducted" numeric(10,2) DEFAULT 0.00,
    "return_code" text
);

CREATE TABLE public."customers" (
    "customer_id" text NOT NULL,
    "customer_unique_id" text,
    "customer_zip_code_prefix" text,
    "customer_city" text,
    "customer_state" text
);

CREATE TABLE public."n8n_chat_histories" (
    "id" integer DEFAULT nextval('n8n_chat_histories_id_seq'::regclass) NOT NULL,
    "session_id" character varying(255) NOT NULL,
    "message" jsonb NOT NULL
);

CREATE TABLE public."order_items" (
    "order_id" text NOT NULL,
    "order_item_id" bigint NOT NULL,
    "product_id" text,
    "seller_id" text,
    "shipping_limit_date" timestamp without time zone,
    "price" numeric,
    "freight_value" numeric
);

CREATE TABLE public."order_payments" (
    "order_id" text NOT NULL,
    "payment_sequential" bigint NOT NULL,
    "payment_type" text,
    "payment_installments" bigint,
    "payment_value" numeric
);

CREATE TABLE public."order_reviews" (
    "review_id" text NOT NULL,
    "order_id" text NOT NULL,
    "review_score" bigint,
    "review_comment_title" text,
    "review_comment_message" text,
    "review_creation_date" timestamp without time zone,
    "review_answer_timestamp" timestamp without time zone
);

CREATE TABLE public."orders" (
    "order_id" text NOT NULL,
    "customer_id" text,
    "order_status" text,
    "order_purchase_timestamp" timestamp without time zone,
    "order_approved_at" timestamp without time zone,
    "order_delivered_carrier_date" timestamp without time zone,
    "order_delivered_customer_date" timestamp without time zone,
    "order_estimated_delivery_date" timestamp without time zone
);

CREATE TABLE public."products" (
    "product_id" text NOT NULL,
    "product_category_name" text,
    "product_name_lenght" bigint,
    "product_description_lenght" bigint,
    "product_photos_qty" bigint,
    "product_weight_g" bigint,
    "product_length_cm" bigint,
    "product_height_cm" bigint,
    "product_width_cm" bigint
);

CREATE TABLE public."review_followups" (
    "review_id" text NOT NULL,
    "order_id" text NOT NULL,
    "ticket_id" bigint NOT NULL,
    "issue_category" text NOT NULL,
    "analysis" text NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public."sellers" (
    "seller_id" text NOT NULL,
    "seller_zip_code_prefix" text,
    "seller_city" text,
    "seller_state" text
);

CREATE TABLE public."support_tickets" (
    "id" bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    "order_id" text NOT NULL,
    "session_id" text NOT NULL,
    "reason" text NOT NULL,
    "customer_claim" text NOT NULL,
    "status" text DEFAULT 'open'::text NOT NULL,
    "is_simulation" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "resolved_at" timestamp with time zone
);

ALTER SEQUENCE public.n8n_chat_histories_id_seq OWNED BY public.n8n_chat_histories.id;

ALTER TABLE public."category_translation" ADD CONSTRAINT "category_translation_pkey" PRIMARY KEY (product_category_name);

ALTER TABLE public."compensation_requests" ADD CONSTRAINT "compensation_requests_amount_check" CHECK ((amount > (0)::numeric));

ALTER TABLE public."compensation_requests" ADD CONSTRAINT "compensation_requests_pkey" PRIMARY KEY (id);

ALTER TABLE public."compensation_requests" ADD CONSTRAINT "compensation_requests_reason_check" CHECK ((reason = ANY (ARRAY['delivery_delay'::text, 'buyer_remorse'::text, 'damaged_item'::text, 'wrong_item'::text, 'out_of_stock'::text])));

ALTER TABLE public."compensation_requests" ADD CONSTRAINT "compensation_requests_request_key_key" UNIQUE (request_key);

ALTER TABLE public."compensation_requests" ADD CONSTRAINT "compensation_requests_resolution_type_check" CHECK ((resolution_type = ANY (ARRAY['refund'::text, 'voucher'::text, 'replacement'::text])));

ALTER TABLE public."compensation_requests" ADD CONSTRAINT "compensation_requests_status_check" CHECK ((status = ANY (ARRAY['pending_review'::text, 'awaiting_return'::text, 'approved'::text, 'rejected'::text, 'simulated'::text])));

ALTER TABLE public."customers" ADD CONSTRAINT "customers_pkey" PRIMARY KEY (customer_id);

ALTER TABLE public."n8n_chat_histories" ADD CONSTRAINT "n8n_chat_histories_pkey" PRIMARY KEY (id);

ALTER TABLE public."order_items" ADD CONSTRAINT "order_items_pkey" PRIMARY KEY (order_id, order_item_id);

ALTER TABLE public."order_payments" ADD CONSTRAINT "order_payments_pkey" PRIMARY KEY (order_id, payment_sequential);

ALTER TABLE public."order_reviews" ADD CONSTRAINT "orser_reviews_pkey" PRIMARY KEY (review_id, order_id);

ALTER TABLE public."orders" ADD CONSTRAINT "orders_pkey" PRIMARY KEY (order_id);

ALTER TABLE public."products" ADD CONSTRAINT "products_pkey" PRIMARY KEY (product_id);

ALTER TABLE public."review_followups" ADD CONSTRAINT "review_followups_analysis_check" CHECK ((length(TRIM(BOTH FROM analysis)) > 0));

ALTER TABLE public."review_followups" ADD CONSTRAINT "review_followups_issue_category_check" CHECK ((issue_category = ANY (ARRAY['missing_item'::text, 'wrong_item'::text, 'damaged_item'::text, 'delivery_issue'::text, 'product_quality'::text, 'other'::text, 'unknown'::text])));

ALTER TABLE public."review_followups" ADD CONSTRAINT "review_followups_pkey" PRIMARY KEY (review_id, order_id);

ALTER TABLE public."sellers" ADD CONSTRAINT "sellers_pkey" PRIMARY KEY (seller_id);

ALTER TABLE public."support_tickets" ADD CONSTRAINT "support_tickets_pkey" PRIMARY KEY (id);

ALTER TABLE public."support_tickets" ADD CONSTRAINT "support_tickets_reason_check" CHECK ((reason = ANY (ARRAY['delivery_dispute'::text, 'damaged_item'::text, 'wrong_item'::text, 'return_review'::text, 'compensation_review'::text, 'other'::text])));

ALTER TABLE public."support_tickets" ADD CONSTRAINT "support_tickets_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'resolved'::text])));

ALTER TABLE public."compensation_requests" ADD CONSTRAINT "compensation_requests_item_fkey" FOREIGN KEY (order_id, order_item_id) REFERENCES order_items(order_id, order_item_id);

ALTER TABLE public."compensation_requests" ADD CONSTRAINT "compensation_requests_order_id_fkey" FOREIGN KEY (order_id) REFERENCES orders(order_id);

ALTER TABLE public."review_followups" ADD CONSTRAINT "review_followups_order_id_fkey" FOREIGN KEY (order_id) REFERENCES orders(order_id);

ALTER TABLE public."review_followups" ADD CONSTRAINT "review_followups_ticket_id_fkey" FOREIGN KEY (ticket_id) REFERENCES support_tickets(id);

ALTER TABLE public."support_tickets" ADD CONSTRAINT "support_tickets_order_id_fkey" FOREIGN KEY (order_id) REFERENCES orders(order_id);

ALTER TABLE public."category_translation" ENABLE ROW LEVEL SECURITY;

CREATE UNIQUE INDEX compensation_requests_active_scope_idx ON public.compensation_requests USING btree (order_id, reason, COALESCE(order_item_id, (0)::bigint)) WHERE (status <> 'rejected'::text);

ALTER TABLE public."compensation_requests" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."customers" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."n8n_chat_histories" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."order_items" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."order_payments" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."order_reviews" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."orders" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."products" ENABLE ROW LEVEL SECURITY;

CREATE INDEX review_followups_ticket_id_idx ON public.review_followups USING btree (ticket_id);

ALTER TABLE public."review_followups" ENABLE ROW LEVEL SECURITY;

ALTER TABLE public."sellers" ENABLE ROW LEVEL SECURITY;

CREATE UNIQUE INDEX support_tickets_open_reason_idx ON public.support_tickets USING btree (order_id, reason) WHERE (status = ANY (ARRAY['open'::text, 'in_progress'::text]));

ALTER TABLE public."support_tickets" ENABLE ROW LEVEL SECURITY;

COMMIT;
