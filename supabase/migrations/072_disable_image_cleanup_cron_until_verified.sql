do $$
begin
  perform cron.unschedule('process-image-cleanup-queue');
exception
  when others then
    null;
end
$$;

do $$
begin
  perform cron.unschedule('cleanup-expired-images');
exception
  when others then
    null;
end
$$;

comment on function public.cleanup_expired_images() is
  'Queues expired source images for cleanup. Automatic cron is intentionally disabled until manual production verification is complete.';

comment on function public.invoke_image_cleanup_worker() is
  'Invokes the image cleanup Edge Function worker. Automatic cron is intentionally disabled until manual production verification is complete.';
