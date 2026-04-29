-- ════════════════════════════════════════════════════════════════════
-- receipt-images 私有桶 signed URL 访问策略
-- 目的：允许前端使用 anon key 对已知 path 调 createSignedUrl()
-- 说明：bucket 仍保持 private；客户端不能直接公开访问原图 URL
-- ════════════════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public)
values ('receipt-images', 'receipt-images', false)
on conflict (id) do update set public = false;

drop policy if exists "allow_anon_select_receipt_images" on storage.objects;

create policy "allow_anon_select_receipt_images"
on storage.objects
for select
to anon
using (bucket_id = 'receipt-images');
