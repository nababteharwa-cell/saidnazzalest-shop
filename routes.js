// Shop addresses, shared by the browser (window.SNRoutes) and the page renderer on Vercel (require).
//   home        {base}/
//   category    {base}/c/{category}            sub-category {base}/c/{category}/{sub}
//   all items   {base}/c/all                   occasion     {base}/c/all?tag={occasion}
//   search      {base}/search?q={words}
//   product     {base}/p/{id}/{name}
// {base} is "/shop-o6bwd2u8fe" on the private link and "" once the shop is public.
(function (root) {
  const PRIVATE = '/shop-o6bwd2u8fe';
  const slug = (en, ar) => {
    let s = String(en || '').toLowerCase().replace(/&/g, ' and ').replace(/['’]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
    if (!s) s = String(ar || '').trim().replace(/[\s/\\?#%&]+/g, '-').replace(/^-+|-+$/g, '');
    return s.slice(0, 80) || 'x';
  };
  // categories: [{name, name_en, subs:[{name, name_en}]}]
  const catSlug = c => slug(c.name_en, c.name);
  const findCat = (cats, s) => { s = decodeURIComponent(s || ''); return cats.find(c => catSlug(c) === s) || null; };
  const findSub = (cat, s) => { s = decodeURIComponent(s || ''); return cat && (cat.subs || []).find(x => slug(x.name_en, x.name) === s) || null; };
  const enc = s => encodeURIComponent(s).replace(/%2D/g, '-');
  const paths = base => ({
    home: () => base + '/',
    all: tag => base + '/c/all' + (tag ? '?tag=' + encodeURIComponent(tag) : ''),
    cat: (c, sub) => base + '/c/' + enc(catSlug(c)) + (sub ? '/' + enc(slug(sub.name_en, sub.name)) : ''),
    search: q => base + '/search' + (q ? '?q=' + encodeURIComponent(q) : ''),
    product: p => base + '/p/' + encodeURIComponent(p.id) + '/' + enc(slug(p.name_en, p.name))
  });
  // path without base → {view, catSlug, subSlug, pid}
  const parse = rest => {
    const seg = String(rest || '').split('?')[0].split('/').filter(Boolean);
    if (!seg.length) return { view: 'home' };
    if (seg[0] === 'c' && seg[1] === 'all') return { view: 'all' };
    if (seg[0] === 'c' && seg[1]) return { view: 'cat', catSlug: seg[1], subSlug: seg[2] || null };
    if (seg[0] === 'search') return { view: 'search' };
    if (seg[0] === 'p' && seg[1]) return { view: 'product', pid: decodeURIComponent(seg[1]) };
    return { view: 'notfound' };
  };
  // The category tree used for addresses: the saved list (settings.categories) plus any category or
  // sub-category that only appears on products. Only categories with visible products are kept.
  const tree = (settings, products) => {
    const vis = products.filter(p => p.visible !== false);
    const saved = (settings && settings.categories) || [];
    const names = [...saved.map(c => c.name), ...vis.map(p => p.cat)].filter((c, i, a) => c && a.indexOf(c) === i && vis.some(p => p.cat === c));
    return names.map(n => {
      const c = saved.find(x => x.name === n) || {}; const ps = vis.filter(p => p.cat === n);
      const name_en = c.name_en || (ps.find(p => p.cat_en) || {}).cat_en || '';
      const subNames = [...(c.subs || []).map(x => x.name), ...ps.map(p => p.sub)].filter((x, i, a) => x && a.indexOf(x) === i && ps.some(p => p.sub === x));
      const subs = subNames.map(sn => { const sx = (c.subs || []).find(x => x.name === sn) || {}; return { name: sn, name_en: sx.name_en || (ps.find(p => p.sub === sn && p.sub_en) || {}).sub_en || '' }; });
      return { name: n, name_en, img: c.img || '', subs };
    });
  };
  const api = { tree, PRIVATE, slug, catSlug, findCat, findSub, paths, parse };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.SNRoutes = api;
})(typeof window !== 'undefined' ? window : globalThis);
