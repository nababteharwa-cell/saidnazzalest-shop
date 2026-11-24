// The shop catalogue, served from Vercel's edge cache so visitors don't wait for the database.
// Refreshed at most once a minute; stock and prices are always re-checked by the database when an order is placed.
// Uses shop_catalog() (13-fast-catalog.sql); until that file is run, it reads the products table page by page instead.
const URL_ = process.env.SUPABASE_URL || 'https://yjmnoqdbwnpowwbjrjjz.supabase.co';
const KEY = process.env.SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_-k0Tgo2wzXApRPHGMjsXCQ_SX0NGDUD';   // public key (same as config.js)
const H = () => ({ apikey: KEY, 'Content-Type': 'application/json' });

async function viaTable() {
  const page = from => fetch(URL_ + '/rest/v1/products?select=data&order=sort.asc,id.asc', { headers: { ...H(), Range: from + '-' + (from + 999) } })
    .then(r => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); });
  const st = fetch(URL_ + '/rest/v1/settings?select=data&id=eq.1', { headers: H() }).then(r => r.json());
  let rows = [], from = 0;
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

module.exports = async (req, res) => {
  const done = (code, body, cache) => { res.statusCode = code; res.setHeader('Content-Type', 'application/json; charset=utf-8'); res.setHeader('Cache-Control', cache); res.end(body); };
  try {
    const r = await fetch(URL_ + '/rest/v1/rpc/shop_catalog', { method: 'POST', headers: H(), body: '{}' });
    const body = r.ok ? await r.text() : await viaTable();
    done(200, body, 'public, max-age=0, s-maxage=60, stale-while-revalidate=600');
  } catch (e) {
    done(502, JSON.stringify({ error: 'upstream' }), 'no-store');
  }
};
