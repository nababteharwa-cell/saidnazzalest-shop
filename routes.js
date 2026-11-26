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
  // The shop owner edits the types in the dashboard (settings.types); until then the five above are used.
  const segments = (settings, all) => {
    const L = settings && Array.isArray(settings.types) ? settings.types : SEGMENTS;
    return L.filter(s => s && s.key && s.name && s.pick && (all || !s.hidden))
            .map(s => ({ ...s, img: s.img || (SEGMENTS.some(d => d.key === s.key) ? '/photos/types/' + s.key + '.webp' : '') }));
  };
  // Automatic choice of categories for a type, from words in its name and description.
  // Ready-made sets for common businesses, plus any category or family whose name appears in the words.
  const PRESETS = [
    [/مطعم|مطاعم|وجبات|restaurant|takeaway|fast ?food/i, 'restaurants'],
    [/مقه|كافي|قهوة|كوفي|caf|coffee/i, 'cafes'],
    [/حلويات|حلو|شوكولا|sweet|chocolate|candy/i, 'sweet-shops'],
    [/مخبز|مخابز|كيك|معجنات|bakery|bakeries|cake|pastry/i, 'bakeries'],
    [/تموين|مناسبات|حفلات|أفراح|catering|event|party|wedding/i, 'catering'],
    [/فندق|فنادق|hotel/i, { [V]: '*', [C]: '*', [K]: ['تنظيف', 'عربايات وأثاث', 'أجهزة وماكينات'], [T]: ['ورق لف ومحارم'] }],
    [/مستشفى|مستشفيات|عياد|طبي|hospital|clinic|medical/i, { [T]: ['علب وجبات', 'صحون وصواني سفري', 'معالق وأطقم سفري', 'ورق لف ومحارم', 'كفوف ومرايل', 'أغطية'], [C]: ['كاسات ورق وبلاستيك', 'قناني وعبوات'], [K]: ['تنظيف'] }],
    [/مدرس|مدارس|جامع|كلية|حضان|روض|school|universit|college|nurser/i, { [T]: ['علب وجبات', 'أكياس ومستلزمات', 'معالق وأطقم سفري', 'ورق لف ومحارم'], [C]: ['كاسات ورق وبلاستيك', 'قناني وعبوات'] }],
    [/مكتب|مكاتب|شرك|بنك|بنوك|وزار|office|compan|bank|government/i, { [C]: '*', [V]: ['كاسات وفناجين', 'سدور وصواني تقديم'], [T]: ['ورق لف ومحارم'], [K]: ['تنظيف'] }],
    [/عصير|عصائر|juice|smoothie/i, { [C]: ['كاسات ورق وبلاستيك', 'أغطية ومصاصات وحراكات', 'قناني وعبوات', 'حمّالات كاسات', 'أباريق ودلال'], [T]: ['أكياس ومستلزمات'], [K]: ['أجهزة وماكينات'] }],
    [/شاورما|مشاوي|مشويات|بيتزا|برجر|فلافل|shawarma|pizza|burger|grill|falafel/i, { [T]: '*', [K]: ['أجهزة وماكينات', 'طناجر ومقالي', 'سكاكين وأدوات تقطيع', 'أدوات المطبخ', 'ورق كاشير وباركود'] }],
    [/بوظة|آيس|جيلاتو|ice ?cream|gelato/i, { [S]: ['كاسات حلويات'], [C]: ['كاسات ورق وبلاستيك', 'أغطية ومصاصات وحراكات'], [T]: ['معالق وأطقم سفري', 'أكياس ومستلزمات'] }],
    [/بيت|منزل|منازل|ربات|home|household/i, { [B]: '*', [D]: '*', [K]: ['أدوات المطبخ', 'حفظ وتخزين'] }],
    [/هدايا|هدية|ورد|زهور|gift|flower/i, { [G]: '*', [D]: ['شموع وزينة', 'فلين وتنسيق'] }]
  ];
  const addPick = (to, from) => { for (const [c, v] of Object.entries(from)) {
    if (v === '*' || to[c] === '*') to[c] = '*'; else to[c] = [...new Set([...(to[c] || []), ...v])]; } return to; };
  const suggestPick = (text, cats) => {   // cats = [{name, name_en, subs:[{name, name_en}]}]
    const t = String(text || ''), pick = {};
    PRESETS.forEach(([re, v]) => { if (re.test(t)) addPick(pick, typeof v === 'string' ? SEGMENTS.find(s => s.key === v).pick : v); });
    const low = t.toLowerCase(), has = n => n && n.length > 2 && low.includes(String(n).toLowerCase());
    (cats || []).forEach(c => { if (has(c.name) || has(c.name_en)) addPick(pick, { [c.name]: '*' });
      else (c.subs || []).forEach(x => { if (has(x.name) || has(x.name_en)) addPick(pick, { [c.name]: [x.name] }); }); });
    const known = new Set((cats || []).map(c => c.name));   // only categories that exist in the shop
    if (cats) Object.keys(pick).forEach(c => { if (!known.has(c)) delete pick[c]; });
    return pick;
  };
  const inSeg = (seg, p) => { const v = seg && seg.pick[p.cat]; return v === '*' || (Array.isArray(v) && v.includes(p.sub)); };
  const segRank = (seg, p) => { const k = Object.keys(seg.pick).indexOf(p.cat); return k < 0 ? 99 : k; };   // the type's main categories first
  const findSeg = (k, list) => (list || SEGMENTS).find(s => s.key === decodeURIComponent(k || '')) || null;
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
  const api = { tree, SEGMENTS, segments, suggestPick, inSeg, segRank, findSeg, PRIVATE, slug, catSlug, findCat, findSub, paths, parse };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.SNRoutes = api;
})(typeof window !== 'undefined' ? window : globalThis);
