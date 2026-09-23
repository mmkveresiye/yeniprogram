// =====================================================================
//  Shared config + helpers (loaded by index.html, admin.html, app.html)
//  Load order in every page: tailwind CDN -> supabase-js CDN -> config.js
// =====================================================================

// 1) Fill these two in: Supabase Dashboard > Project Settings > API
const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-PUBLIC-KEY';

const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
const SESSION_KEY = 'mmk_session';

// ---------- Session helpers (localStorage) ---------------------------

function getSession() {
  try { return JSON.parse(localStorage.getItem(SESSION_KEY)); } catch { return null; }
}
function setSession(s) { localStorage.setItem(SESSION_KEY, JSON.stringify(s)); }
function clearSession() { localStorage.removeItem(SESSION_KEY); }

// Guards a page: verifies the stored token with the database.
// Returns the session (with a fresh display name) or redirects to login.
async function requireRole(role) {
  const s = getSession();
  if (!s || s.role !== role || !s.token) { location.replace('index.html'); return null; }
  try {
    const { data, error } = await sb.rpc('app_validate', { p_token: s.token, p_role: role });
    if (error || !data || !data.valid) throw new Error('invalid session');
    return { ...s, name: data.name };
  } catch {
    clearSession();
    location.replace('index.html');
    return null;
  }
}

async function logout() {
  const s = getSession();
  if (s && s.token) { try { await sb.rpc('app_logout', { p_token: s.token }); } catch {} }
  clearSession();
  location.replace('index.html');
}

// Escapes text before putting it into innerHTML
function esc(v) {
  return String(v ?? '').replace(/[&<>"']/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

// Small toast used by admin.html and app.html
function toast(msg, isError = false) {
  let el = document.getElementById('toast');
  if (!el) {
    el = document.createElement('div');
    el.id = 'toast';
    el.setAttribute('role', 'status');
    document.body.appendChild(el);
  }
  el.textContent = msg;
  el.className = 'fixed bottom-5 left-1/2 -translate-x-1/2 z-50 px-4 py-2.5 rounded-md text-sm text-white shadow-lg '
    + (isError ? 'bg-margin' : 'bg-ink');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => { el.className = 'hidden'; }, 3200);
}

// ---------- Theme: Tailwind config, fonts, ledger-paper background ----

if (window.tailwind) {
  tailwind.config = {
    theme: {
      extend: {
        colors: {
          paper:  '#EDF1EC',   // pale green-grey ledger paper
          ink:    '#14261F',   // text
          cloth:  '#1F5B4A',   // ledger cover green (primary)
          clothdk:'#174739',
          rule:   '#CBD8CF',   // ruled lines / borders
          margin: '#C2453A',   // red margin line (errors, destructive)
          brass:  '#8A6A1C'    // pending / attention
        },
        fontFamily: {
          display: ['Fraunces', 'Georgia', 'serif'],
          sans: ['"IBM Plex Sans"', 'system-ui', 'sans-serif']
        }
      }
    }
  };
}

(function injectTheme() {
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = 'https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,700&family=IBM+Plex+Sans:wght@400;500;600&display=swap';
  document.head.appendChild(link);

  const style = document.createElement('style');
  style.textContent = `
    body { font-family: 'IBM Plex Sans', system-ui, sans-serif; }
    .tabular { font-variant-numeric: tabular-nums; }
    .ledger-paper {
      background-color: #EDF1EC;
      background-image:
        linear-gradient(to right, transparent 63px, #C2453A 63px, #C2453A 65px, transparent 65px),
        repeating-linear-gradient(to bottom, transparent 0, transparent 31px, #CBD8CF 31px, #CBD8CF 32px);
    }
    :focus-visible { outline: 2px solid #1F5B4A; outline-offset: 2px; }
  `;
  document.head.appendChild(style);
})();
