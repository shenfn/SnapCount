-- Remove older generic or judgmental companion copy that should not seed new generations.

update public.data_records
set payload_jsonb = payload_jsonb - 'companion_message',
    updated_at = now()
where payload_jsonb->>'companion_message' ~ '(这周第\\s*[0-9一二三四五六七八九十]+\\s*顿|看来.*(吃饱了|胃口不错|凑个单|熬夜)|记得|注意身体|合理饮食|买到.*安心|支付成功的安心)';

update public.transactions
set companion_message = null
where companion_message ~ '(这周第\\s*[0-9一二三四五六七八九十]+\\s*顿|看来.*(吃饱了|胃口不错|凑个单|熬夜)|记得|注意身体|合理饮食|买到.*安心|支付成功的安心)';
