-- Exported function bodies; behavior preserved from the demo.
BEGIN;
SET LOCAL search_path = public, pg_catalog;

CREATE OR REPLACE FUNCTION public.execute_delay_compensation(p_order_id text, p_resolution_type text, p_session_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_order public.orders%ROWTYPE;
    v_existing public.compensation_requests%ROWTYPE;

    v_reference_date CONSTANT date := DATE '2018-10-18';
    v_end_date date;
    v_delay integer;
    v_total numeric;
    v_target numeric;
    v_previous numeric := 0;
    v_increment numeric;
    v_request_id bigint;
    v_has_existing boolean;
BEGIN
    -- Validate inputs.
    IF p_resolution_type IS NULL
       OR p_resolution_type NOT IN ('refund', 'voucher', 'replacement')
    THEN
        RETURN jsonb_build_object(
            'result', 'invalid_resolution',
            'message', 'Choose refund, voucher, or replacement.'
        );
    END IF;

    IF p_session_id IS NULL OR btrim(p_session_id) = '' THEN
        RETURN jsonb_build_object(
            'result', 'missing_session',
            'message', 'A workflow-provided session ID is required.'
        );
    END IF;

    -- Serialize compensation operations for this order.
    SELECT *
    INTO v_order
    FROM public.orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('result', 'order_not_found');
    END IF;

    IF v_order.order_status IN ('canceled', 'unavailable') THEN
        RETURN jsonb_build_object(
            'result', 'requires_review',
            'message', 'This order requires a different policy route.'
        );
    END IF;

    IF v_order.order_purchase_timestamp IS NULL
       OR v_order.order_purchase_timestamp::date > v_reference_date
       OR v_order.order_estimated_delivery_date IS NULL
    THEN
        RETURN jsonb_build_object(
            'result', 'requires_review',
            'message', 'Missing or inconsistent order dates.'
        );
    END IF;

    IF v_order.order_status = 'delivered' THEN
        IF v_order.order_delivered_customer_date IS NULL THEN
            RETURN jsonb_build_object(
                'result', 'requires_review',
                'message', 'Delivered order has no delivery date.'
            );
        END IF;

        v_end_date := v_order.order_delivered_customer_date::date;
    ELSIF v_order.order_status IN (
        'created', 'approved', 'invoiced', 'processing', 'shipped'
    ) THEN
        IF v_order.order_delivered_customer_date IS NOT NULL THEN
            RETURN jsonb_build_object(
                'result', 'requires_review',
                'message', 'Order status conflicts with delivery date.'
            );
        END IF;

        v_end_date := v_reference_date;
    ELSE
        RETURN jsonb_build_object(
            'result', 'requires_review',
            'message', 'Unsupported order status.'
        );
    END IF;

    IF v_end_date > v_reference_date
       OR v_end_date < v_order.order_purchase_timestamp::date
    THEN
        RETURN jsonb_build_object(
            'result', 'requires_review',
            'message', 'Dates conflict with the simulation timeline.'
        );
    END IF;

    -- Monday through Friday, excluding the estimated delivery day.
    SELECT COUNT(*)::integer
    INTO v_delay
    FROM generate_series(
        (v_order.order_estimated_delivery_date::date + 1)::timestamp,
        v_end_date::timestamp,
        INTERVAL '1 day'
    ) AS d(day)
    WHERE EXTRACT(ISODOW FROM d.day) BETWEEN 1 AND 5;

    IF v_delay = 0 THEN
        RETURN jsonb_build_object(
            'result', 'not_eligible',
            'delay_business_days', 0
        );
    END IF;

    SELECT SUM(payment_value)
    INTO v_total
    FROM public.order_payments
    WHERE order_id = p_order_id;

    IF v_total IS NULL OR v_total <= 0 THEN
        RETURN jsonb_build_object(
            'result', 'requires_review',
            'message', 'No valid payment total is available.'
        );
    END IF;

    -- Calculate the permitted cumulative compensation.
    IF v_delay BETWEEN 1 AND 3
       AND p_resolution_type = 'voucher'
    THEN
        v_target := ROUND(v_total * 0.10, 2);

    ELSIF v_delay BETWEEN 4 AND 7
          AND p_resolution_type = 'refund'
    THEN
        v_target := ROUND(v_total * 0.15, 2);

    ELSIF v_delay BETWEEN 4 AND 7
          AND p_resolution_type = 'voucher'
    THEN
        v_target := ROUND(v_total * 0.20, 2);

    ELSIF v_delay BETWEEN 8 AND 14
          AND p_resolution_type = 'refund'
    THEN
        v_target := ROUND(v_total * 0.30, 2);

    ELSIF v_delay >= 15 AND p_resolution_type = 'refund' THEN
        v_target := ROUND(v_total, 2);

    ELSIF v_delay >= 15 AND p_resolution_type = 'replacement' THEN
        -- A replacement is not a monetary refund.
        v_target := NULL;

    ELSE
        RETURN jsonb_build_object(
            'result', 'option_not_allowed',
            'delay_business_days', v_delay,
            'requested_option', p_resolution_type
        );
    END IF;

    IF v_target IS NOT NULL AND v_target <= 0 THEN
        RETURN jsonb_build_object(
            'result', 'requires_review',
            'message', 'Calculated amount rounds to zero.'
        );
    END IF;

    -- Avoid overlapping compensation across other request routes.
    IF EXISTS (
        SELECT 1
        FROM public.compensation_requests
        WHERE order_id = p_order_id
          AND status <> 'rejected'
          AND (
              reason <> 'delivery_delay'
              OR order_item_id IS NOT NULL
          )
    ) THEN
        RETURN jsonb_build_object(
            'result', 'requires_review',
            'message', 'Another request exists for this order.'
        );
    END IF;

    SELECT *
    INTO v_existing
    FROM public.compensation_requests
    WHERE order_id = p_order_id
      AND reason = 'delivery_delay'
      AND order_item_id IS NULL
      AND status <> 'rejected'
    FOR UPDATE;

    v_has_existing := FOUND;

    IF v_has_existing THEN
        IF v_existing.status <> 'simulated'
           OR v_existing.is_simulation IS NOT TRUE
        THEN
            RETURN jsonb_build_object(
                'result', 'requires_review',
                'request_id', v_existing.id,
                'message', 'An existing request needs review.'
            );
        END IF;

        -- Do not automatically switch a previously issued benefit.
        IF v_existing.resolution_type IS DISTINCT FROM p_resolution_type
        THEN
            RETURN jsonb_build_object(
                'result', 'requires_review',
                'request_id', v_existing.id,
                'message', 'A different compensation type was already recorded.'
            );
        END IF;

        IF p_resolution_type = 'replacement' THEN
            RETURN jsonb_build_object(
                'result', 'already_processed',
                'request_id', v_existing.id,
                'resolution_type', 'replacement',
                'simulation_only', true
            );
        END IF;

        IF v_existing.amount IS NULL OR v_existing.amount <= 0 THEN
            RETURN jsonb_build_object(
                'result', 'requires_review',
                'message', 'Existing compensation amount is invalid.'
            );
        END IF;

        v_previous := v_existing.amount;

        IF v_previous >= v_target THEN
            RETURN jsonb_build_object(
                'result', 'already_processed',
                'request_id', v_existing.id,
                'resolution_type', p_resolution_type,
                'cumulative_amount', v_previous,
                'additional_amount', 0,
                'simulation_only', true
            );
        END IF;
    END IF;

    v_increment := v_target - v_previous;

    IF v_has_existing THEN
        UPDATE public.compensation_requests
        SET amount = v_target,
            session_id = p_session_id,
            reference_date = v_reference_date,
            completed_at = now()
        WHERE id = v_existing.id
        RETURNING id INTO v_request_id;
    ELSE
        INSERT INTO public.compensation_requests (
            order_id,
            session_id,
            reason,
            resolution_type,
            amount,
            status,
            reference_date,
            approved_at,
            completed_at,
            is_simulation
        )
        VALUES (
            p_order_id,
            p_session_id,
            'delivery_delay',
            p_resolution_type,
            v_target,
            'simulated',
            v_reference_date,
            now(),
            now(),
            true
        )
        RETURNING id INTO v_request_id;
    END IF;

    RETURN jsonb_build_object(
        'result', 'success',
        'request_id', v_request_id,
        'order_id', p_order_id,
        'resolution_type', p_resolution_type,
        'delay_business_days', v_delay,
        'total_paid', v_total,
        'previous_amount', v_previous,
        'additional_amount', v_increment,
        'cumulative_amount', v_target,
        'simulation_only', true,
        'real_money_transferred', false
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_review_followup(p_review_id text, p_order_id text, p_issue_category text, p_analysis text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_ticket_id bigint;
    v_reason text;
BEGIN
    IF p_issue_category IS NULL OR p_issue_category NOT IN (
        'missing_item', 'wrong_item', 'damaged_item',
        'delivery_issue', 'product_quality', 'other', 'unknown'
    ) THEN
        RAISE EXCEPTION 'Invalid issue category';
    END IF;

    IF p_analysis IS NULL OR length(trim(p_analysis)) = 0 THEN
        RAISE EXCEPTION 'Analysis must not be empty';
    END IF;

    -- Serialize writes for this order to prevent concurrent duplicates.
    PERFORM 1
    FROM public.orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    PERFORM 1
    FROM public.order_reviews
    WHERE review_id = p_review_id
      AND order_id = p_order_id
      AND review_score IN (1, 2);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Matching low-rated review not found';
    END IF;

    SELECT ticket_id
    INTO v_ticket_id
    FROM public.review_followups
    WHERE review_id = p_review_id
      AND order_id = p_order_id;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'result', 'already_processed',
            'ticket_id', v_ticket_id,
            'review_id', p_review_id,
            'order_id', p_order_id
        );
    END IF;

    -- Map review categories to existing ticket reasons.
    v_reason := CASE p_issue_category
        WHEN 'missing_item'    THEN 'delivery_dispute'
        WHEN 'delivery_issue'  THEN 'delivery_dispute'
        WHEN 'wrong_item'      THEN 'wrong_item'
        WHEN 'damaged_item'    THEN 'damaged_item'
        WHEN 'product_quality' THEN 'return_review'
        ELSE 'other'
    END;

    INSERT INTO public.support_tickets AS ticket (
        order_id,
        session_id,
        reason,
        customer_claim,
        is_simulation
    )
    VALUES (
        p_order_id,
        'review:' || p_review_id || ':' || p_order_id,
        v_reason,
        'Proactive review follow-up. AI-generated analysis:'
            || E'\n' || p_analysis,
        true
    )
    ON CONFLICT (order_id, reason)
        WHERE status IN ('open', 'in_progress')
    DO UPDATE SET order_id = ticket.order_id
    RETURNING id INTO v_ticket_id;

    INSERT INTO public.review_followups (
        review_id,
        order_id,
        ticket_id,
        issue_category,
        analysis
    )
    VALUES (
        p_review_id,
        p_order_id,
        v_ticket_id,
        p_issue_category,
        p_analysis
    );

    RETURN jsonb_build_object(
        'result', 'recorded',
        'ticket_id', v_ticket_id,
        'review_id', p_review_id,
        'order_id', p_order_id,
        'reason', v_reason
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.request_standard_return(p_order_id text, p_order_item_id integer, p_session_id text, p_is_unused boolean, p_has_original_packaging boolean, p_has_tags_attached boolean, p_is_excluded_item boolean DEFAULT false, p_customer_description text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_order public.orders%ROWTYPE;
    v_existing public.compensation_requests%ROWTYPE;
    v_item record;

    v_reference_date CONSTANT date := DATE '2018-10-18';
    v_delivered_date date;
    v_days_since_delivery integer;

    v_delay_comp_total numeric(10,2) := 0.00;
    v_has_delay_replacement boolean := false;
    v_already_deducted numeric(10,2) := 0.00;
    v_remaining_to_deduct numeric(10,2) := 0.00;
    v_deduction_for_this_item numeric(10,2) := 0.00;
    v_expected_refund numeric(10,2) := 0.00;

    v_is_category_excluded boolean := false;
    v_return_code text;
    v_request_id bigint;
BEGIN
    -- 1. Validate inputs
    IF p_order_id IS NULL OR btrim(p_order_id) = '' THEN
        RETURN jsonb_build_object(
            'result', 'invalid_input',
            'message', 'An order ID is required.'
        );
    END IF;

    p_order_id := btrim(p_order_id);

    IF p_order_item_id IS NULL OR p_order_item_id <= 0 THEN
        RETURN jsonb_build_object(
            'result', 'invalid_input',
            'message', 'A valid order_item_id (1, 2, ...) is required.'
        );
    END IF;

    IF p_session_id IS NULL OR btrim(p_session_id) = '' THEN
        RETURN jsonb_build_object(
            'result', 'missing_session',
            'message', 'A workflow-provided session ID is required.'
        );
    END IF;

    -- 2. Lock order row to serialize operations on this order
    SELECT *
    INTO v_order
    FROM public.orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('result', 'order_not_found');
    END IF;

    -- 3. Verify item belongs to the order and fetch price + category
    SELECT
        i.order_id,
        i.order_item_id,
        i.product_id,
        i.price,
        i.freight_value,
        p.product_category_name,
        t.product_category_name_english
    INTO v_item
    FROM public.order_items i
    LEFT JOIN public.products p ON p.product_id = i.product_id
    LEFT JOIN public.category_translation t ON t.product_category_name = p.product_category_name
    WHERE i.order_id = p_order_id
      AND i.order_item_id = p_order_item_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'result', 'item_not_found',
            'order_id', p_order_id,
            'order_item_id', p_order_item_id,
            'message', 'The specified item number does not belong to this order.'
        );
    END IF;

    -- 4. Check if an active buyer_remorse return request already exists for this item
    SELECT *
    INTO v_existing
    FROM public.compensation_requests
    WHERE order_id = p_order_id
      AND reason = 'buyer_remorse'
      AND order_item_id = p_order_item_id
      AND status <> 'rejected'
    FOR UPDATE;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'result', 'already_processed',
            'request_id', v_existing.id,
            'order_id', p_order_id,
            'order_item_id', p_order_item_id,
            'status', v_existing.status,
            'return_code', v_existing.return_code,
            'item_price', v_item.price,
            'prior_compensation_deducted', COALESCE(v_existing.prior_compensation_deducted, 0.00),
            'expected_refund_amount', v_existing.expected_refund_amount,
            'refund_issued_now', false,
            'simulation_only', true,
            'message', 'An active return request already exists for this item. Refund will only be processed after warehouse inspection.'
        );
    END IF;

    -- 5. Block if non-compatible request types exist (damaged_item, wrong_item, out_of_stock)
    IF EXISTS (
        SELECT 1
        FROM public.compensation_requests
        WHERE order_id = p_order_id
          AND status <> 'rejected'
          AND reason NOT IN ('delivery_delay', 'buyer_remorse')
    ) THEN
        RETURN jsonb_build_object(
            'result', 'requires_review',
            'can_open_ticket', true,
            'suggested_ticket_reason', 'return_review',
            'message', 'Another open issue exists on this order. Manual support review is required.'
        );
    END IF;

    -- 6. Validate delivery status and dates
    IF v_order.order_status <> 'delivered' OR v_order.order_delivered_customer_date IS NULL THEN
        RETURN jsonb_build_object(
            'result', 'not_eligible',
            'sub_reason', 'order_not_delivered',
            'order_status', v_order.order_status,
            'can_open_ticket', true,
            'suggested_ticket_reason', 'return_review',
            'message', 'Only delivered orders with a recorded delivery date can be returned through the standard route.'
        );
    END IF;

    v_delivered_date := v_order.order_delivered_customer_date::date;

    IF v_order.order_purchase_timestamp IS NULL
       OR v_delivered_date < v_order.order_purchase_timestamp::date
       OR v_delivered_date > v_reference_date
    THEN
        RETURN jsonb_build_object(
            'result', 'requires_review',
            'can_open_ticket', true,
            'suggested_ticket_reason', 'return_review',
            'message', 'Order delivery dates conflict with the simulation timeline.'
        );
    END IF;

    -- 7. Check 0 to 30 calendar days window (inclusive of day 30)
    v_days_since_delivery := (v_reference_date - v_delivered_date);

    IF v_days_since_delivery < 0 OR v_days_since_delivery > 30 THEN
        RETURN jsonb_build_object(
            'result', 'not_eligible',
            'sub_reason', 'outside_30_day_window',
            'days_since_delivery', v_days_since_delivery,
            'delivered_date', v_delivered_date,
            'reference_date', v_reference_date,
            'can_open_ticket', true,
            'suggested_ticket_reason', 'return_review',
            'message', 'The 30-calendar-day return window has passed.'
        );
    END IF;

    -- 8. Check excluded categories (food/beverages in DB or customer-disclosed exclusion)
    v_is_category_excluded := COALESCE(v_item.product_category_name, '') IN ('alimentos', 'bebidas', 'alimentos_bebidas');

    IF COALESCE(p_is_excluded_item, false) OR v_is_category_excluded THEN
        RETURN jsonb_build_object(
            'result', 'not_eligible',
            'sub_reason', 'excluded_item_category',
            'category', COALESCE(v_item.product_category_name_english, v_item.product_category_name, 'unknown'),
            'can_open_ticket', true,
            'suggested_ticket_reason', 'return_review',
            'message', 'This item falls under an excluded category (opened cosmetics, underwear/intimate apparel, food/beverages, or custom-made items) and is not eligible for standard return.'
        );
    END IF;

    -- 9. Check item condition declarations (must all be explicitly true)
    IF p_is_unused IS DISTINCT FROM true
       OR p_has_original_packaging IS DISTINCT FROM true
       OR p_has_tags_attached IS DISTINCT FROM true
    THEN
        RETURN jsonb_build_object(
            'result', 'not_eligible',
            'sub_reason', 'condition_requirements_not_met',
            'is_unused', p_is_unused,
            'has_original_packaging', p_has_original_packaging,
            'has_tags_attached', p_has_tags_attached,
            'can_open_ticket', true,
            'suggested_ticket_reason', 'return_review',
            'message', 'Standard return requires the item to be unused, in its original packaging, and with original tags attached.'
        );
    END IF;

    -- 10. Calculate expected refund (item price only, excluding freight_value) minus any un-deducted prior delay compensation
    IF v_item.price IS NULL OR v_item.price <= 0 THEN
        RETURN jsonb_build_object(
            'result', 'requires_review',
            'can_open_ticket', true,
            'suggested_ticket_reason', 'return_review',
            'message', 'Invalid item price in database.'
        );
    END IF;

    SELECT
        COALESCE(SUM(COALESCE(cr.amount, 0.00)), 0.00),
        BOOL_OR(cr.resolution_type = 'replacement')
    INTO v_delay_comp_total, v_has_delay_replacement
    FROM public.compensation_requests cr
    WHERE cr.order_id = p_order_id
      AND cr.reason = 'delivery_delay'
      AND cr.status <> 'rejected';

    IF v_has_delay_replacement THEN
        RETURN jsonb_build_object(
            'result', 'not_eligible',
            'sub_reason', 'already_compensated_with_replacement',
            'can_open_ticket', true,
            'suggested_ticket_reason', 'return_review',
            'message', 'This order was already compensated with a free replacement due to delivery delay.'
        );
    END IF;

    SELECT COALESCE(SUM(COALESCE(cr.prior_compensation_deducted, 0.00)), 0.00)
    INTO v_already_deducted
    FROM public.compensation_requests cr
    WHERE cr.order_id = p_order_id
      AND cr.reason = 'buyer_remorse'
      AND cr.status <> 'rejected';

    v_remaining_to_deduct := GREATEST(v_delay_comp_total - v_already_deducted, 0.00);
    v_deduction_for_this_item := LEAST(ROUND(v_item.price, 2), v_remaining_to_deduct);
    v_expected_refund := ROUND(v_item.price - v_deduction_for_this_item, 2);

    IF v_expected_refund <= 0 THEN
        RETURN jsonb_build_object(
            'result', 'not_eligible',
            'sub_reason', 'fully_compensated_by_prior_delay_refund',
            'item_price', ROUND(v_item.price, 2),
            'prior_delay_compensation', v_delay_comp_total,
            'can_open_ticket', true,
            'suggested_ticket_reason', 'return_review',
            'message', 'Prior delay compensation on this order already covers or exceeds the refundable item price.'
        );
    END IF;

    -- 11. Generate simulated return code and insert awaiting_return record
    v_return_code := 'RET-' || upper(substring(p_order_id from 1 for 6)) || '-' || p_order_item_id::text;

    INSERT INTO public.compensation_requests (
        order_id,
        order_item_id,
        session_id,
        reason,
        resolution_type,
        amount,
        expected_refund_amount,
        prior_compensation_deducted,
        status,
        reference_date,
        customer_description,
        is_unused,
        has_original_packaging,
        has_tags_attached,
        is_excluded_item,
        return_code,
        approved_at,
        is_simulation
    )
    VALUES (
        p_order_id,
        p_order_item_id,
        btrim(p_session_id),
        'buyer_remorse',
        'refund',
        NULL,
        v_expected_refund,
        v_deduction_for_this_item,
        'awaiting_return',
        v_reference_date,
        p_customer_description,
        p_is_unused,
        p_has_original_packaging,
        p_has_tags_attached,
        COALESCE(p_is_excluded_item, false),
        v_return_code,
        now(),
        true
    )
    RETURNING id INTO v_request_id;

    RETURN jsonb_build_object(
        'result', 'success',
        'request_id', v_request_id,
        'order_id', p_order_id,
        'order_item_id', p_order_item_id,
        'status', 'awaiting_return',
        'days_since_delivery', v_days_since_delivery,
        'return_code', v_return_code,
        'item_price', ROUND(v_item.price, 2),
        'shipping_not_refunded', ROUND(v_item.freight_value, 2),
        'prior_compensation_deducted', v_deduction_for_this_item,
        'expected_refund_amount', v_expected_refund,
        'refund_issued_now', false,
        'simulation_only', true,
        'real_money_transferred', false
    );
END;
$function$;
COMMIT;
