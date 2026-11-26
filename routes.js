// Shop addresses, shared by the browser (window.SNRoutes) and the page renderer on Vercel (require).
//   home        {base}/
//   category    {base}/c/{category}            sub-category {base}/c/{category}/{sub}
//   all items   {base}/c/all                   occasion     {base}/c/all?tag={occasion}
//   business    {base}/b/{type}                 one category in it {base}/b/{type}?c={category}
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
  // Shop by business type: each type takes whole categories ('*') or chosen families of a category.
  // A product can belong to several types. Category and family names are those of the stock app (stock/catalog.js).
  const B = 'الحلويات والخبز', D = 'تزيين الكيك والحفلات', S = 'علب الحلويات والشوكولاتة', G = 'تغليف وهدايا',
        T = 'تيك أواي وتعبئة الطعام', C = 'القهوة والمشروبات', V = 'التقديم والضيافة', K = 'معدات ومستلزمات المطبخ';
  const SEGMENTS = [
    { key: 'restaurants', name: 'المطاعم والوجبات السريعة', name_en: 'Restaurants & takeaway',
      desc: 'علب الوجبات والسفري، الألمنيوم، الأكياس، وأدوات المطبخ والتقديم', desc_en: 'Meal and takeaway boxes, foil, bags, kitchen and serving tools',
      pick: { [T]: '*', [K]: ['أجهزة وماكينات', 'طناجر ومقالي', 'سكاكين وأدوات تقطيع', 'أدوات المطبخ', 'حفظ وتخزين', 'تنظيف', 'موازين وعيارات', 'ورق كاشير وباركود'],
              [V]: ['صحون وأطباق', 'جاطات وزبادي', 'أدوات المائدة', 'سدور وصواني تقديم'], [C]: ['كاسات ورق وبلاستيك', 'أغطية ومصاصات وحراكات', 'قناني وعبوات', 'حمّالات كاسات'] } },
    { key: 'cafes', name: 'المقاهي والكافيهات', name_en: 'Cafés & coffee shops',
      desc: 'كاسات القهوة وأغطيتها، أدوات الباريستا، الحمّالات، وأدوات التقديم', desc_en: 'Coffee cups and lids, barista tools, cup carriers and serveware',
      pick: { [C]: '*', [V]: ['كاسات وفناجين', 'صحون وأطباق', 'سدور وصواني تقديم', 'ستاندات عرض', 'أدوات المائدة'],
              [T]: ['أكياس ومستلزمات', 'ورق لف ومحارم', 'معالق وأطقم سفري', 'علب بلاستيك وشفاف'], [K]: ['أجهزة وماكينات', 'تنظيف', 'ورق كاشير وباركود'],
              [S]: ['كاسات حلويات'], [G]: ['مرطبانات وعبوات'] } },
    { key: 'sweet-shops', name: 'محلات الحلويات والشوكولاتة', name_en: 'Sweet & chocolate shops',
      desc: 'علب الحلويات والشوكولاتة، الكاسات، التغليف والهدايا، وستاندات العرض', desc_en: 'Sweet and chocolate boxes, dessert cups, gift packaging and display stands',
      pick: { [S]: '*', [G]: '*', [B]: ['قوالب شوكولاتة', 'أدوات التحضير والتزيين', 'أكياس صب وأقماع'], [D]: ['توبرات وعيدان', 'شموع وزينة'],
              [V]: ['ستاندات عرض', 'سدور وصواني تقديم'], [T]: ['أكياس ومستلزمات', 'كفوف ومرايل'] } },
    { key: 'bakeries', name: 'المخابز وصناعة الكيك', name_en: 'Bakeries & cake makers',
      desc: 'القوالب والصواني، ورق الخبز، أدوات التزيين، وعلب وقواعد الكيك', desc_en: 'Moulds and tins, baking paper, decorating tools, cake boxes and boards',
      pick: { [B]: '*', [D]: '*', [S]: ['علب كيك', 'قواعد كيك ودانتيل', 'كاسات حلويات'], [K]: ['أجهزة وماكينات', 'موازين وعيارات', 'أدوات المطبخ', 'حفظ وتخزين'],
              [T]: ['كفوف ومرايل', 'أكياس ومستلزمات'] } },
    { key: 'catering', name: 'التموين والمناسبات', name_en: 'Catering & events',
      desc: 'صواني وسدور التقديم، الجاطات، أطقم السفري، الألمنيوم، والزينة', desc_en: 'Serving trays, bowls, disposable sets, foil trays and decorations',
      pick: { [V]: '*', [T]: ['صحون وصواني سفري', 'ألمنيوم وقصدير', 'معالق وأطقم سفري', 'ورق لف ومحارم', 'علب وجبات', 'أغطية'],
              [C]: ['كاسات ورق وبلاستيك', 'أباريق ودلال', 'قناني وعبوات'], [D]: ['شموع وزينة', 'فلين وتنسيق', 'توبرات وعيدان'],
              [K]: ['عربايات وأثاث', 'طناجر ومقالي', 'حفظ وتخزين'] } }
  ];
  SEGMENTS.forEach(s => { s.img = '/photos/types/' + s.key + '.webp'; });
  const inSeg = (seg, p) => { const v = seg && seg.pick[p.cat]; return v === '*' || (Array.isArray(v) && v.includes(p.sub)); };
  const segRank = (seg, p) => { const k = Object.keys(seg.pick).indexOf(p.cat); return k < 0 ? 99 : k; };   // the type's main categories first
  const findSeg = k => SEGMENTS.find(s => s.key === decodeURIComponent(k || '')) || null;
  const enc = s => encodeURIComponent(s).replace(/%2D/g, '-');
  const paths = base => ({
    home: () => base + '/',
    all: tag => base + '/c/all' + (tag ? '?tag=' + encodeURIComponent(tag) : ''),
    cat: (c, sub) => base + '/c/' + enc(catSlug(c)) + (sub ? '/' + enc(slug(sub.name_en, sub.name)) : ''),
    seg: (s, c) => base + '/b/' + s.key + (c ? '?c=' + encodeURIComponent(catSlug(c)) : ''),
    search: q => base + '/search' + (q ? '?q=' + encodeURIComponent(q) : ''),
    product: p => base + '/p/' + encodeURIComponent(p.id) + '/' + enc(slug(p.name_en, p.name))
  });
  // path without base → {view, catSlug, subSlug, pid}
  const parse = rest => {
    const seg = String(rest || '').split('?')[0].split('/').filter(Boolean);
    if (!seg.length) return { view: 'home' };
    if (seg[0] === 'c' && seg[1] === 'all') return { view: 'all' };
    if (seg[0] === 'c' && seg[1]) return { view: 'cat', catSlug: seg[1], subSlug: seg[2] || null };
    if (seg[0] === 'b' && seg[1] && !seg[2]) return { view: 'seg', segKey: seg[1] };
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
  const api = { tree, SEGMENTS, inSeg, segRank, findSeg, PRIVATE, slug, catSlug, findCat, findSub, paths, parse };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.SNRoutes = api;
})(typeof window !== 'undefined' ? window : globalThis);
