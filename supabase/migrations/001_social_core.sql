-- GBSBFORYOU Social core schema (Supabase/PostgreSQL)
-- Apply only to the intended Supabase project after reviewing the project and backups.
-- Public read access is limited to approved/published posts and approved comments.
-- Never place service-role keys or external social tokens in this schema's public tables.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Member' check (char_length(display_name) between 1 and 80),
  bio text not null default '' check (char_length(bio) <= 500),
  preferred_language text not null default 'hi' check (preferred_language in ('hi','en','gor','mr','ta','te')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.editor_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('editor','admin')),
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id)
);
-- No client INSERT/UPDATE/DELETE policy is intentionally provided for editor_roles.
-- Assign roles only through trusted SQL/admin tooling after verifying the user's auth UUID.

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete restrict,
  title text not null check (char_length(title) between 1 and 180),
  body text not null check (char_length(body) between 1 and 20000),
  category text not null default 'community' check (category in ('letter','academy','community','news','creative')),
  language text not null default 'hi' check (language in ('hi','en','gor','mr','ta','te')),
  status text not null default 'pending_review' check (status in ('draft','pending_review','approved','published','rejected','archived')),
  ai_review_status text not null default 'not_run' check (ai_review_status in ('not_run','queued','flagged','passed','error')),
  ai_review_summary text,
  editorial_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  published_at timestamptz,
  source_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete restrict,
  body text not null check (char_length(body) between 1 and 5000),
  status text not null default 'pending_review' check (status in ('pending_review','approved','rejected','hidden')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.moderation_events (
  id uuid primary key default gen_random_uuid(),
  content_type text not null check (content_type in ('post','comment')),
  content_id uuid not null,
  actor_id uuid references auth.users(id),
  action text not null check (action in ('submitted','ai_flagged','ai_passed','approved','published','rejected','hidden','archived','edited')),
  note text,
  created_at timestamptz not null default now()
);

create index if not exists posts_public_feed_idx on public.posts (published_at desc nulls last, created_at desc)
  where status in ('approved','published');
create index if not exists posts_author_idx on public.posts (author_id, created_at desc);
create index if not exists posts_review_queue_idx on public.posts (created_at asc)
  where status = 'pending_review';
create index if not exists comments_post_public_idx on public.comments (post_id, created_at asc)
  where status = 'approved';
create index if not exists comments_review_queue_idx on public.comments (created_at asc)
  where status = 'pending_review';

create or replace function public.is_editor()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.editor_roles er
    where er.user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_editor() from public;
grant execute on function public.is_editor() to anon, authenticated;

alter table public.profiles enable row level security;
alter table public.editor_roles enable row level security;
alter table public.posts enable row level security;
alter table public.comments enable row level security;
alter table public.moderation_events enable row level security;

drop policy if exists "profiles readable by everyone" on public.profiles;
create policy "profiles readable by everyone" on public.profiles
  for select using (true);
drop policy if exists "users insert own profile" on public.profiles;
create policy "users insert own profile" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists "editor roles visible to editors" on public.editor_roles;
create policy "editor roles visible to editors" on public.editor_roles
  for select to authenticated using (public.is_editor());

drop policy if exists "public reads approved posts" on public.posts;
create policy "public reads approved posts" on public.posts
  for select using (status in ('approved','published') or author_id = (select auth.uid()) or public.is_editor());
drop policy if exists "authenticated users submit posts" on public.posts;
create policy "authenticated users submit posts" on public.posts
  for insert to authenticated with check (
    author_id = (select auth.uid()) and status in ('draft','pending_review')
  );
drop policy if exists "authors edit own drafts" on public.posts;
create policy "authors edit own drafts" on public.posts
  for update to authenticated using (
    author_id = (select auth.uid()) and status = 'draft'
  ) with check (
    author_id = (select auth.uid()) and status = 'draft'
  );
drop policy if exists "editors moderate posts" on public.posts;
create policy "editors moderate posts" on public.posts
  for update to authenticated using (public.is_editor()) with check (public.is_editor());

drop policy if exists "public reads approved comments" on public.comments;
create policy "public reads approved comments" on public.comments
  for select using (
    status = 'approved'
    or author_id = (select auth.uid())
    or public.is_editor()
  );
drop policy if exists "authenticated users submit comments" on public.comments;
create policy "authenticated users submit comments" on public.comments
  for insert to authenticated with check (
    author_id = (select auth.uid())
    and status = 'pending_review'
    and exists (
      select 1 from public.posts p
      where p.id = post_id and p.status in ('approved','published')
    )
  );
drop policy if exists "editors moderate comments" on public.comments;
create policy "editors moderate comments" on public.comments
  for update to authenticated using (public.is_editor()) with check (public.is_editor());

drop policy if exists "moderation events visible to editors" on public.moderation_events;
create policy "moderation events visible to editors" on public.moderation_events
  for select to authenticated using (public.is_editor());
drop policy if exists "editors record moderation events" on public.moderation_events;
create policy "editors record moderation events" on public.moderation_events
  for insert to authenticated with check (public.is_editor());

-- Profiles are created by the application after sign-up for now.
-- Add a trusted server-side trigger/function in a separately reviewed migration if needed.
