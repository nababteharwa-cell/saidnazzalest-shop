// /sitemap.xml – every category, sub-category and product, in Arabic and English. Only once the shop is public.
const R = require('../routes.js');
const { catalog } = require('./_catalog');
const PUBLIC = process.env.SHOP_PUBLIC === '1';
const ORIGIN = (process.env.SITE_ORIGIN || 'https://www.saidnazzalest.com').replace(/\/$/, '');
const x = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
module.exports = async (req, res) => {
  res.setHeader('Content-Type', 'application/xml; charset=utf-8');
  if (!PUBLIC) { res.statusCode = 404; res.setHeader('Cache-Control', 'public, s-maxage=300'); return res.end('<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"></urlset>'); }
  try {
    const c = await catalog(); const ps = (c.products || []).filter(p => p.visible !== false); const T = R.tree(c.settings || {}, ps); const P = R.paths('');
    const urls = [P.home(), P.all(), ...R.SEGMENTS.map(sg => P.seg(sg)), ...T.flatMap(k => [P.cat(k), ...(k.subs.length > 1 ? k.subs.map(s => P.cat(k, s)) : [])]), ...ps.map(P.product)];
    const one = u => { const en = u + (u.includes('?') ? '&' : '?') + 'lang=en';
      return ['ar', 'en'].map(l => `<url><loc>${x(ORIGIN + (l === 'en' ? en : u))}</loc><xhtml:link rel="alternate" hreflang="ar" href="${x(ORIGIN + u)}"/><xhtml:link rel="alternate" hreflang="en" href="${x(ORIGIN + en)}"/></url>`).join(''); };
    res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=3600, stale-while-revalidate=86400');
    res.end('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">' + urls.map(one).join('\n') + '</urlset>');
  } catch (e) { res.statusCode = 502; res.setHeader('Cache-Control', 'no-store'); res.end('<error/>'); }
};
