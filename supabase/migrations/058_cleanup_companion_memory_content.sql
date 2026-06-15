-- Clean up companion copy/memory generated before the content guard existed.

update public.data_records
set payload_jsonb = payload_jsonb - 'companion_message',
    updated_at = now()
where payload_jsonb->>'companion_message' ~ '(刚吃完.+又来|这周.*吃过.*今天换成|第\\s*N\\s*顿|超标|记得|注意身体|合理饮食)';

update public.transactions
set companion_message = null
where companion_message ~ '(刚吃完.+又来|这周.*吃过.*今天换成|第\\s*N\\s*顿|超标|记得|注意身体|合理饮食|看来.*熬夜|买个安心|生活还在继续)';

update public.user_companion_memories
set content = concat('用户最近一次睡眠约 ', evidence_jsonb->>'sleep_hours', ' 小时。'),
    updated_at = now()
where memory_type = 'sleep_pattern'
  and evidence_jsonb ? 'sleep_hours'
  and evidence_jsonb->>'sleep_hours' is not null;

update public.user_companion_memories
set content = concat(
      '用户最近记录过',
      case evidence_jsonb->>'meal_type'
        when 'breakfast' then '早餐'
        when 'lunch' then '午餐'
        when 'dinner' then '晚餐'
        when 'snack' then '加餐'
        else '饮食'
      end,
      case
        when coalesce(evidence_jsonb->>'title', '') <> '' then concat('：', evidence_jsonb->>'title')
        else ''
      end,
      case
        when coalesce(evidence_jsonb->>'calories', '') <> '' then concat('，约 ', round((evidence_jsonb->>'calories')::numeric), ' 千卡')
        else ''
      end,
      '。'
    ),
    updated_at = now()
where memory_type = 'food_pattern';
