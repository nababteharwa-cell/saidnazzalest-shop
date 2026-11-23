// Panel users: create logins, set permissions, reset passwords, disable or remove.
// Runs on Vercel with the Supabase secret key (env SUPABASE_SECRET_KEY), which never reaches the browser.
// Only a signed-in owner (row in public.admins) may call it.
const URL_ = process.env.SUPABASE_URL || 'https://yjmnoqdbwnpowwbjrjjz.supabase.co';
const SECRET = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const PERMS = ['orders', 'products', 'stock', 'history', 'commission', 'settings'];

const adminHeaders = () => {
  const h = { apikey: SECRET, 'Content-Type': 'application/json' };
  if (SECRET.startsWith('eyJ')) h.Authorization = 'Bearer ' + SECRET;   // legacy service_role JWT
  return h;
};
async function sbFetch(path, opts = {}) {
  const r = await fetch(URL_ + path, { ...opts, headers: { ...adminHeaders(), ...(opts.headers || {}) } });
  const text = await r.text();
  let body = null; try { body = text ? JSON.parse(text) : null; } catch (e) { body = text; }
  if (!r.ok) { const m = (body && (body.msg || body.message || body.error_description || body.error)) || ('HTTP ' + r.status); throw Object.assign(new Error(m), { status: r.status }); }
  return body;
}
const rest = (path, opts) => sbFetch('/rest/v1/' + path, opts);
const auth = (path, opts) => sbFetch('/auth/v1/' + path, opts);

async function caller(req) {
  const tok = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (!tok) return null;
  const r = await fetch(URL_ + '/auth/v1/user', { headers: { apikey: req.headers['x-anon-key'] || SECRET, Authorization: 'Bearer ' + tok } });
  if (!r.ok) return null;
  const u = await r.json();
  const own = await rest('admins?select=user_id&user_id=eq.' + encodeURIComponent(u.id));
  return own && own.length ? u : null;
}
const cleanPerms = p => [...new Set((Array.isArray(p) ? p : []).filter(x => PERMS.includes(x)))];
const okPassword = p => typeof p === 'string' && p.length >= 8;

async function setRoles(id, b) {
  if (b.owner === true) await rest('admins', { method: 'POST', headers: { Prefer: 'resolution=ignore-duplicates' }, body: JSON.stringify({ user_id: id }) });
  if (b.owner === false) await rest('admins?user_id=eq.' + id, { method: 'DELETE' });
  await rest('panel_users?on_conflict=user_id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify({ user_id: id, name: (b.name || '').trim() || null, perms: cleanPerms(b.perms), active: b.active !== false, updated_at: new Date().toISOString() }) });
  if (b.stock === 'owner' || b.stock === 'staff') {
    await rest('inv_users?on_conflict=user_id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates' },
      body: JSON.stringify({ user_id: id, role: b.stock, name: (b.name || '').trim() || null }) });
  } else if (b.stock === 'none') {
    await rest('inv_users?user_id=eq.' + id, { method: 'DELETE' });
  }
}

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  const send = (code, obj) => { res.statusCode = code; res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(obj)); };
  try {
    if (req.method !== 'POST') return send(405, { error: 'method' });
    if (!SECRET) return send(503, { error: 'not_configured' });
    let b = req.body;
    if (typeof b === 'string') { try { b = JSON.parse(b); } catch (e) { b = {}; } }
    b = b || {};
    const me = await caller(req);
    if (!me) return send(403, { error: 'owner_only' });
    const owners = (await rest('admins?select=user_id')).map(r => r.user_id);

    if (b.action === 'list') {
      const [list, team, inv] = await Promise.all([auth('admin/users?per_page=1000'), rest('panel_users?select=*'), rest('inv_users?select=user_id,role,name')]);
      const users = (list.users || list || []).map(u => {
        const t = team.find(x => x.user_id === u.id) || {}, s = inv.find(x => x.user_id === u.id);
        return { id: u.id, email: u.email, name: t.name || (s && s.name) || '', owner: owners.includes(u.id), perms: t.perms || [],
                 active: t.active !== false && !(u.banned_until && new Date(u.banned_until) > new Date()), stock: s ? s.role : 'none',
                 last: u.last_sign_in_at || null, me: u.id === me.id };
      });
      return send(200, { users });
    }
    if (b.action === 'create') {
      const email = String(b.email || '').trim().toLowerCase();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return send(400, { error: 'bad_email' });
      if (!okPassword(b.password)) return send(400, { error: 'weak_password' });
      let u;
      try { u = await auth('admin/users', { method: 'POST', body: JSON.stringify({ email, password: b.password, email_confirm: true }) }); }
      catch (e) { return send(400, { error: /already|registered|exists/i.test(e.message) ? 'email_exists' : e.message }); }
      await setRoles(u.id, b);
      return send(200, { ok: true, id: u.id });
    }
    const id = String(b.id || '');
    if (!/^[0-9a-f-]{36}$/.test(id)) return send(400, { error: 'bad_id' });
    if (b.action === 'update') {
      if (id === me.id && (b.owner === false || b.active === false)) return send(400, { error: 'cannot_change_self' });
      if (b.owner === false && owners.includes(id) && owners.length <= 1) return send(400, { error: 'last_owner' });
      await setRoles(id, b);
      await auth('admin/users/' + id, { method: 'PUT', body: JSON.stringify({ ban_duration: b.active === false ? '876000h' : 'none' }) });
      return send(200, { ok: true });
    }
    if (b.action === 'password') {
      if (!okPassword(b.password)) return send(400, { error: 'weak_password' });
      await auth('admin/users/' + id, { method: 'PUT', body: JSON.stringify({ password: b.password }) });
      return send(200, { ok: true });
    }
    if (b.action === 'remove') {
      if (id === me.id) return send(400, { error: 'cannot_change_self' });
      if (owners.includes(id) && owners.length <= 1) return send(400, { error: 'last_owner' });
      await auth('admin/users/' + id, { method: 'DELETE' });
      return send(200, { ok: true });
    }
    return send(400, { error: 'bad_action' });
  } catch (e) {
    return send(500, { error: e.message || 'error' });
  }
};
