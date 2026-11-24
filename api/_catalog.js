// Shared by /api/catalog and the page renderer: the visible shop catalogue.
// Uses shop_catalog() (13-fast-catalog.sql); until that file is run, it reads the products table page by page.
const URL_ = process.env.SUPABASE_URL || 'https://yjmnoqdbwnpowwbjrjjz.supabase.co';
const KEY = process.env.SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_-k0Tgo2wzXApRPHGMjsXCQ_SX0NGDUD';   // public key (same as config.js)
const H = () => ({ apikey: KEY, 'Content-Type': 'application/json' });

async function viaTable() {
  const page = from => fetch(URL_ + '/rest/v1/products?select=data&order=sort.asc,id.asc&limit=1000&offset=' + from, { headers: H() })
    .then(r => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); });
  const st = fetch(URL_ + '/rest/v1/settings?select=data&id=eq.1', { headers: H() }).then(r => r.json());
  const rows = []; let from = 0;
  for (;;) {   // 6 pages at a time
    const got = await Promise.all([0, 1, 2, 3, 4, 5].map(k => page(from + k * 1000)));
    got.forEach(g => rows.push(...g));
    if (got[5].length < 1000) break;
    from += 6000;
  }
  const clean = d => { const x = { ...d }; delete x.src; ['desc', 'desc_en', 'img'].forEach(k => { if (!x[k]) delete x[k]; }); if (Array.isArray(x.tags) && !x.tags.length) delete x.tags; return x; };
  const s = await st;
  return JSON.stringify({ settings: s && s[0] ? s[0].data : null, products: rows.map(r => r.data).filter(d => d.visible !== false).map(clean), at: new Date().toISOString() });
}

// JSON text of {settings, products, at}
async function catalogText() {
  const r = await fetch(URL_ + '/rest/v1/rpc/shop_catalog', { method: 'POST', headers: H(), body: '{}' });
  return r.ok ? await r.text() : await viaTable();
}
let memo = null;   // reused by warm function instances for 60 s
async function catalog() {
  if (memo && Date.now() - memo.t < 60000) return memo.v;
  const v = JSON.parse(await catalogText()); memo = { t: Date.now(), v }; return v;
}
module.exports = { catalogText, catalog };
