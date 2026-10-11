-- Additive security hardening for existing Digital Library tables.
-- Does not delete or alter existing rows or remove existing functionality.
-- Verify the project and review these policies before applying.
alter table public.book_files enable row level security;
alter table public.publications enable row level security;
alter table public.products enable row level security;
alter table public.payouts enable row level security;

-- A file is visible only if its book is published, or to its author/editor.
create policy "read files for published books or own books"
on public.book_files for select to anon, authenticated
using (
  exists (
    select 1 from public.books b
    where b.id = book_files.book_id
      and (
        b.publication_status = 'PUBLISHED'
        or exists (
          select 1 from public.authors a
          where a.id = b.author_id and a.user_id = (select auth.uid())
        )
        or public.is_social_editor()
      )
  )
);

-- Publication records are visible for published books, to their authors, and editors.
create policy "read publication records for published or own books"
on public.publications for select to anon, authenticated
using (
  exists (
    select 1 from public.books b
    where b.id = publications.book_id
      and (
        b.publication_status = 'PUBLISHED'
        or exists (
          select 1 from public.authors a
          where a.id = b.author_id and a.user_id = (select auth.uid())
        )
        or public.is_social_editor()
      )
  )
);
create policy "editors manage publication records"
on public.publications for all to authenticated
using (public.is_social_editor())
with check (public.is_social_editor());

-- Products are visible only when active and attached to a published book,
-- or to the book's author/editor.
create policy "read active products for published or own books"
on public.products for select to anon, authenticated
using (
  active = true and exists (
    select 1 from public.books b
    where b.id = products.book_id
      and (
        b.publication_status = 'PUBLISHED'
        or exists (
          select 1 from public.authors a
          where a.id = b.author_id and a.user_id = (select auth.uid())
        )
        or public.is_social_editor()
      )
  )
);
create policy "editors manage products"
on public.products for all to authenticated
using (public.is_social_editor())
with check (public.is_social_editor());

-- Authors may read only their own payouts. No client write policy is added.
create policy "authors read own payouts"
on public.payouts for select to authenticated
using (
  exists (
    select 1 from public.authors a
    where a.id = payouts.author_id and a.user_id = (select auth.uid())
  )
  or public.is_social_editor()
);
