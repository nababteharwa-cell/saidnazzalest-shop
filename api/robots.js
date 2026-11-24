// /robots.txt – points Google to the sitemap once the shop is public.
const PUBLIC = process.env.SHOP_PUBLIC === '1';
const ORIGIN = (process.env.SITE_ORIGIN || 'https://www.saidnazzalest.com').replace(/\/$/, '');
module.exports = (req, res) => {
  res.setHeader('Content-Type', 'text/plain; charset=utf-8'); res.setHeader('Cache-Control', 'public, s-maxage=3600');
  res.end('User-agent: *\nDisallow: /api/\nDisallow: /stock/\n' + (PUBLIC ? 'Allow: /\nSitemap: ' + ORIGIN + '/sitemap.xml\n' : 'Allow: /\n'));
};
