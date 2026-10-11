-- Keep the SECURITY DEFINER helper outside the exposed public API schema.
-- Policies retain their function dependency when PostgreSQL moves the function.
begin;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;
alter function public.is_social_editor() set schema private;
grant execute on function private.is_social_editor() to anon, authenticated, service_role;
revoke execute on function private.is_social_editor() from public;
commit;
