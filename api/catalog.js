// The shop catalogue, served from Vercel's edge cache so visitors don't wait for the database.
// Refreshed at most once a minute; stock and prices are always re-checked by the database when an order is placed.
const { catalogText } = require('./_catalog');
module.exports = async (req, res) => {
  const done = (code, body, cache) => { res.statusCode = code; res.setHeader('Content-Type', 'application/json; charset=utf-8'); res.setHeader('Cache-Control', cache); res.end(body); };
  try { done(200, await catalogText(), 'public, max-age=0, s-maxage=60, stale-while-revalidate=600'); }
  catch (e) { done(502, JSON.stringify({ error: 'upstream', detail: String(e && e.message || e).slice(0, 200) }), 'no-store'); }
};
