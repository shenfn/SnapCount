import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || 'https://igbghrhsdaolxljgiisf.supabase.co'
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || '***LEGACY_ANON_KEY_REDACTED***'

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
