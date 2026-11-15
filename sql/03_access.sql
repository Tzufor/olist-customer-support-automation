-- Supabase demo setup. Run as the database owner.
-- No public Data API access is granted. Not a production least-privilege role setup.
BEGIN;
REVOKE EXECUTE ON FUNCTION public.execute_delay_compensation(text,text,text)
FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.request_standard_return(text,integer,text,boolean,boolean,boolean,boolean,text)
FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.record_review_followup(text,text,text,text)
FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
COMMIT;
