-- SESSION MEDIA (2026-11-08): photos/videos a player adds to a session, shown in their teams' feeds.
-- Private bucket. Path = <owner uid>/<file>. Owner uploads/deletes their own; teammates (anyone sharing a team) can read.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('session-media', 'session-media', false, 52428800,
        array['image/jpeg','image/png','image/heic','video/mp4','video/quicktime'])
on conflict (id) do nothing;

create policy "session media: upload own" on storage.objects for insert to authenticated
  with check (bucket_id = 'session-media' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "session media: delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'session-media' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "session media: owner and teammates read" on storage.objects for select to authenticated
  using (bucket_id = 'session-media' and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (select 1 from public.team_members m
               where m.user_id::text = (storage.foldername(name))[1]
                 and m.team_id in (select private.my_teams()))));
