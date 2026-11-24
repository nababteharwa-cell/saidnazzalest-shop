// The shop catalogue, served from Vercel's edge cache so visitors don't wait for the database.
// Refreshed at most once a minute; stock and prices are always re-checked by the database when an order is placed.
const URL_ = process.env.SUPABASE_URL || 'https://yjmnoqdbwnpowwbjrjjz.supabase.co';
const KEY = process.env.SUPABASE_PUBLISHABLE_KEY || 'sb_publishable_-k0Tgo2wzXApRPHGMjsXCQ_SX0NGDUD';   // public key (same as config.js)

module.exports = async (req, res) => {
  try {
    const r = await fetch(URL_ + '/rest/v1/rpc/shop_catalog', {
      method: 'POST', headers: { apikey: KEY, 'Content-Type': 'application/json' }, body: '{}'
    });
    const text = await r.text();
    res.statusCode = r.ok ? 200 : 502;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', r.ok ? 'public, max-age=0, s-maxage=60, stale-while-revalidate=600' : 'no-store');
    res.end(r.ok ? text : JSON.stringify({ error: 'upstream', status: r.status }));
  } catch (e) {
    res.statusCode = 502; res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ error: 'upstream' }));
  }
};
