// db.js — shared storage for customers.html and owner.html
// Paste your Supabase values below (Project Settings -> API).
const SUPABASE_URL = 'PASTE_YOUR_PROJECT_URL_HERE';   // e.g. https://abcd1234.supabase.co
const SUPABASE_KEY = 'PASTE_YOUR_ANON_PUBLIC_KEY_HERE';

const useSupabase = SUPABASE_URL.startsWith('https://') && SUPABASE_KEY.length > 20;

function sbHeaders(extra){
  return Object.assign({
    'apikey': SUPABASE_KEY,
    'Authorization': 'Bearer ' + SUPABASE_KEY,
    'Content-Type': 'application/json'
  }, extra || {});
}

async function storageGet(key, shared){
  if(!useSupabase){
    // Fallback: this browser only (used until Supabase is configured)
    const raw = localStorage.getItem(key);
    if(raw === null) throw new Error('not found');
    return {key, value: raw, shared};
  }
  const res = await fetch(`${SUPABASE_URL}/rest/v1/kv?key=eq.${encodeURIComponent(key)}&select=value`, {
    headers: sbHeaders()
  });
  if(!res.ok) throw new Error('read failed');
  const rows = await res.json();
  if(!rows.length) throw new Error('not found');
  return {key, value: rows[0].value, shared};
}

async function storageSet(key, value, shared){
  if(!useSupabase){
    localStorage.setItem(key, value);
    return {key, value, shared};
  }
  const res = await fetch(`${SUPABASE_URL}/rest/v1/kv`, {
    method: 'POST',
    headers: sbHeaders({'Prefer': 'resolution=merge-duplicates,return=minimal'}),
    body: JSON.stringify({key, value})
  });
  if(!res.ok) throw new Error('write failed');
  return {key, value, shared};
}
