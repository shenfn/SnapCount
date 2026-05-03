-- ════════════════════════════════════════════════════════════════════
-- Storage RLS 修复：登录用户无法访问 receipt-images
-- 原因：002 的策略只授权 to anon，登录后的 authenticated 角色被拒绝
-- ════════════════════════════════════════════════════════════════════

-- 补充 authenticated 角色的 select 权限
create policy "allow_auth_select_receipt_images"
on storage.objects
for select
to authenticated
using (bucket_id = 'receipt-images');

-- 补充 authenticated 角色的 delete 权限（用户删除记录时需要清理截图）
create policy "allow_auth_delete_receipt_images"
on storage.objects
for delete
to authenticated
using (bucket_id = 'receipt-images');
