-- Additive integration: Social + Academy alongside the existing Digital Library.
-- This migration intentionally does not drop, rename, or alter existing library tables.
create extension if not exists pgcrypto;

create table if not exists public.social_editor_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('editor','admin')),
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id)
);

create table if not exists public.social_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete restrict,
  title text not null check (char_length(title) between 1 and 180),
  body text not null check (char_length(body) between 1 and 20000),
  category text not null default 'community' check (category in ('letter','academy','community','news','creative','library')),
  language text not null default 'hi' check (language in ('hi','en','gor','mr','ta','te')),
  status text not null default 'pending_review' check (status in ('draft','pending_review','approved','published','rejected','archived')),
  ai_review_status text not null default 'not_run' check (ai_review_status in ('not_run','queued','flagged','passed','error')),
  ai_review_summary text,
  editorial_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  published_at timestamptz,
  source_url text,
  related_book_id uuid references public.books(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.social_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.social_posts(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete restrict,
  body text not null check (char_length(body) between 1 and 5000),
  status text not null default 'pending_review' check (status in ('pending_review','approved','rejected','hidden')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.social_moderation_events (
  id uuid primary key default gen_random_uuid(),
  content_type text not null check (content_type in ('post','comment')),
  content_id uuid not null,
  actor_id uuid references auth.users(id),
  action text not null check (action in ('submitted','ai_flagged','ai_passed','approved','published','rejected','hidden','archived','edited')),
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.academy_courses (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 180),
  slug text not null unique,
  description text not null default '',
  category text not null default 'creator-skills',
  status text not null default 'draft' check (status in ('draft','published','archived')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.academy_lessons (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.academy_courses(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 180),
  content text not null default '',
  position integer not null default 0 check (position >= 0),
  status text not null default 'draft' check (status in ('draft','published','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(course_id, position)
);

create table if not exists public.academy_enrollments (
  user_id uuid not null references auth.users(id) on delete cascade,
  course_id uuid not null references public.academy_courses(id) on delete cascade,
  enrolled_at timestamptz not null default now(),
  status text not null default 'active' check (status in ('active','completed','withdrawn')),
  primary key(user_id, course_id)
);

create table if not exists public.academy_lesson_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson_id uuid not null references public.academy_lessons(id) on delete cascade,
  status text not null default 'not_started' check (status in ('not_started','in_progress','completed')),
  updated_at timestamptz not null default now(),
  primary key(user_id, lesson_id)
);

create index if not exists social_posts_public_feed_idx on public.social_posts (published_at desc nulls last, created_at desc) where status in ('approved','published');
create index if not exists social_posts_review_queue_idx on public.social_posts (created_at asc) where status = 'pending_review';
create index if not exists social_posts_author_idx on public.social_posts (author_id, created_at desc);
create index if not exists social_comments_review_queue_idx on public.social_comments (created_at asc) where status = 'pending_review';
create index if not exists academy_lessons_course_order_idx on public.academy_lessons (course_id, position);

create or replace function public.is_social_editor()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.social_editor_roles r
    where r.user_id = (select auth.uid())
  );
$$;
revoke all on function public.is_social_editor() from public;
grant execute on function public.is_social_editor() to anon, authenticated;

alter table public.social_editor_roles enable row level security;
alter table public.social_posts enable row level security;
alter table public.social_comments enable row level security;
alter table public.social_moderation_events enable row level security;
alter table public.academy_courses enable row level security;
alter table public.academy_lessons enable row level security;
alter table public.academy_enrollments enable row level security;
alter table public.academy_lesson_progress enable row level security;

create policy "social editors can read roles" on public.social_editor_roles for select to authenticated using (public.is_social_editor());
create policy "public reads approved social posts" on public.social_posts for select using (status in ('approved','published') or author_id = (select auth.uid()) or public.is_social_editor());
create policy "authenticated users submit social posts" on public.social_posts for insert to authenticated with check (author_id = (select auth.uid()) and status in ('draft','pending_review'));
create policy "authors edit own social drafts" on public.social_posts for update to authenticated using (author_id = (select auth.uid()) and status = 'draft') with check (author_id = (select auth.uid()) and status = 'draft');
create policy "social editors moderate posts" on public.social_posts for update to authenticated using (public.is_social_editor()) with check (public.is_social_editor());
create policy "public reads approved social comments" on public.social_comments for select using (status = 'approved' or author_id = (select auth.uid()) or public.is_social_editor());
create policy "authenticated users submit social comments" on public.social_comments for insert to authenticated with check (author_id = (select auth.uid()) and status = 'pending_review' and exists (select 1 from public.social_posts p where p.id = post_id and p.status in ('approved','published')));
create policy "social editors moderate comments" on public.social_comments for update to authenticated using (public.is_social_editor()) with check (public.is_social_editor());
create policy "social moderation events readable by editors" on public.social_moderation_events for select to authenticated using (public.is_social_editor());
create policy "social editors write moderation events" on public.social_moderation_events for insert to authenticated with check (public.is_social_editor());
create policy "public reads published academy courses" on public.academy_courses for select using (status = 'published' or public.is_social_editor());
create policy "editors manage academy courses" on public.academy_courses for all to authenticated using (public.is_social_editor()) with check (public.is_social_editor());
create policy "public reads published academy lessons" on public.academy_lessons for select using (status = 'published' or public.is_social_editor());
create policy "editors manage academy lessons" on public.academy_lessons for all to authenticated using (public.is_social_editor()) with check (public.is_social_editor());
create policy "users read own academy enrollments" on public.academy_enrollments for select to authenticated using (user_id = (select auth.uid()) or public.is_social_editor());
create policy "users enroll themselves" on public.academy_enrollments for insert to authenticated with check (user_id = (select auth.uid()));
create policy "users update own lesson progress" on public.academy_lesson_progress for all to authenticated using (user_id = (select auth.uid()) or public.is_social_editor()) with check (user_id = (select auth.uid()) or public.is_social_editor());

-- Social editors are intentionally not auto-assigned. Assign only after confirming the exact auth.users UUID.
