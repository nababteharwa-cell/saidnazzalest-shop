// Shop pages with real content in the HTML, for Google and for link previews (WhatsApp, Instagram, Facebook).
// Each address gets its own title, description, preview picture, structured data and the visible products;
// the browser script then takes over exactly as before.
//
// Addresses (see routes.js): private link /shop-o6bwd2u8fe/…   public (SHOP_PUBLIC=1 on Vercel) /, /c/…, /p/…, /search
// While SHOP_PUBLIC is not "1": the private pages say "noindex" and the public addresses keep the coming-soon page.
const fs = require('fs');
const path = require('path');
const R = require('../routes.js');
const { catalog } = require('./_catalog');

const PUBLIC = process.env.SHOP_PUBLIC === '1';
const ORIGIN = (process.env.SITE_ORIGIN || 'https://www.saidnazzalest.com').replace(/\/$/, '');
const file = n => fs.readFileSync(path.join(__dirname, '..', n), 'utf8');
let TPL = null, SOON = null;
const tpl = () => TPL || (TPL = file('shop-o6bwd2u8fe.html'));
const soon = () => SOON || (SOON = file('coming-soon.html'));

const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const TAG_EN = { 'عيد': 'Eid', 'رمضان': 'Ramadan', 'تخرج': 'Graduation', 'مواليد وأطفال': 'Baby & kids', 'أعراس وخطوبة': 'Weddings' };
const inStock = v => v.stock == null || v.stock > 0;
const avail = p => p.ask || (p.vars || []).some(inStock);
const imgOf = p => p.img || ((p.vars || []).find(v => v.img) || {}).img || '';
const abs = u => !u ? '' : /^https?:/.test(u) ? u : ORIGIN + '/' + String(u).replace(/^\//, '');
const num = n => (Number.isInteger(+n) ? String(+n) : (+n).toFixed(3));

function build(cat, q) {
  const en = q.lang === 'en';
  const base = q.base === 'private' ? R.PRIVATE : '';
  const P = R.paths(base);
  const L = u => u + (en ? (u.includes('?') ? '&' : '?') + 'lang=en' : '');
  const products = (cat.products || []).filter(p => p.visible !== false);
  const settings = cat.settings || {};
  const T = R.tree(settings, products);
  const nm = p => en ? (p.name_en || p.name) : p.name;
  const cn = c => en ? (c.name_en || c.name) : c.name;
  const store = en ? (settings.store_en || 'Said Nazzal Trading') : (settings.store || 'سعيد نزال التجارية');
  const cur = en ? 'JD' : 'د.أ';
  const priceTxt = p => { if (p.ask) return en ? 'Price on request' : 'السعر عند الطلب'; const ps = p.vars.map(v => +v.price); const mn = Math.min(...ps), mx = Math.max(...ps); return (mn === mx ? '' : (en ? 'From ' : 'من ')) + num(mn) + ' ' + cur; };
  const card = p => `<a class="card" href="${esc(L(P.product(p)))}" data-p="${esc(p.id)}"><div class="thumb">${imgOf(p) ? `<img src="${esc(imgOf(p))}" alt="${esc(nm(p))}" loading="lazy">` : ''}</div><div class="b"><h3>${esc(nm(p))}</h3>${avail(p) ? '' : `<span class="oos">${en ? 'Sold out' : 'نفدت الكمية'}</span>`}<span class="price">${esc(priceTxt(p))}</span></div></a>`;
  const crumbs = items => `<nav class="crumbs" aria-label="${en ? 'Breadcrumb' : 'مسار الصفحة'}">${items.map((x, i) => i < items.length - 1 ? `<a href="${esc(L(x[1]))}">${esc(x[0])}</a><span aria-hidden="true">›</span>` : `<span aria-current="page">${esc(x[0])}</span>`).join('')}</nav>`;
  const banner = settings.banner || {};
  const homeDesc = en ? 'Restaurant, café, pastry and packaging supplies in Amman – Jubeiha, Jordan. Wholesale prices, order online, cash on delivery in Jordan and shipping abroad.'
    : 'مستلزمات المطاعم والكافيهات والحلويات ومواد التغليف في عمّان – الجبيهة. أسعار جملة، اطلب أونلاين والدفع عند الاستلام داخل الأردن، وشحن لخارج الأردن.';
  const r = R.parse(q.p || '');
  let status = 200, title = store + (en ? ' | Restaurant, café & packaging supplies in Amman' : ' | مستلزمات المطاعم والحلويات والتغليف في عمّان');
  let desc = homeDesc, image = abs(banner.imgs && banner.imgs[0] || 'photos/b-store.jpg'), here = P.home(), body = '', ld = [], ogType = 'website';
  const home = [en ? 'Home' : 'الرئيسية', P.home()];
  const crumbLd = items => ({ '@type': 'BreadcrumbList', itemListElement: items.map((x, i) => ({ '@type': 'ListItem', position: i + 1, name: x[0], item: ORIGIN + L(x[1]) })) });
  const listLd = (ps) => ({ '@type': 'ItemList', itemListElement: ps.map((p, i) => ({ '@type': 'ListItem', position: i + 1, url: ORIGIN + L(P.product(p)), name: nm(p) })) });
  const sortAvail = ps => ps.map((p, i) => [p, i]).sort((a, b) => (avail(b[0]) - avail(a[0])) || a[1] - b[1]).map(x => x[0]);
  const listPage = (h1, items, ps, extra) => {
    const first = sortAvail(ps).slice(0, 48);
    body = `${crumbs(items)}<div class="pagehead"><h1>${esc(h1)}</h1><span class="count">${ps.length} ${en ? 'products' : 'منتج'}</span></div>${extra || ''}<div class="grid">${first.map(card).join('')}</div>`;
    ld.push(crumbLd(items), listLd(first));
  };

  if (r.view === 'home') {
    const tiles = T.map(c => { const n = products.filter(p => p.cat === c.name).length; return `<a class="tile" href="${esc(L(P.cat(c)))}"><span class="ti"></span><b>${esc(cn(c))}</b><span class="count">${n} ${en ? 'products' : 'منتج'}</span></a>`; }).join('');
    const feats = T.map(c => { const f = sortAvail(products.filter(p => p.cat === c.name)).slice(0, 6); return f.length ? `<section class="feat"><div class="shophead"><h2>${esc(cn(c))}</h2><a href="${esc(L(P.cat(c)))}">${en ? 'View all' : 'عرض الكل'}</a></div><div class="grid">${f.map(card).join('')}</div></section>` : ''; }).join('');
    const bt = en ? (banner.title_en || banner.title) : banner.title, bs = en ? (banner.sub_en || banner.sub) : banner.sub;
    body = `<section class="hero" style="background-image:url('${esc(banner.imgs && banner.imgs[0] || '')}')"><div class="txt"><h1>${esc(bt || store)}</h1><p>${esc(bs || '')}</p></div></section><section class="segs" id="shop"><div class="shophead"><h2>${en ? 'Shop by business type' : 'تسوّق حسب نوع نشاطك'}</h2></div><div class="segrow">${R.segments(settings).map(sg => `<a class="seg" href="${esc(L(P.seg(sg)))}"><span class="si"><img src="${esc(sg.img || ((T.find(k => k.name === Object.keys(sg.pick)[0]) || {}).img) || '')}" alt="" width="720" height="880" loading="lazy"></span><b>${esc(en ? sg.name_en : sg.name)}</b><span class="sd">${esc(en ? sg.desc_en : sg.desc)}</span><span class="count">${products.filter(p => R.inSeg(sg, p)).length} ${en ? 'products' : 'منتج'}</span></a>`).join('')}</div></section><div class="shophead"><h2>${en ? 'Shop by category' : 'تسوّق حسب القسم'}</h2><a class="count" href="${esc(L(P.all()))}">${en ? 'All products' : 'كل المنتجات'} (${products.length})</a></div><div class="tiles">${tiles}</div>${feats}`;
    ld.push({ '@type': 'WebSite', name: store, url: ORIGIN + L(P.home()), potentialAction: { '@type': 'SearchAction', target: ORIGIN + P.search() + '?q={q}' + (en ? '&lang=en' : ''), 'query-input': 'required name=q' } });
  } else if (r.view === 'all') {
    const tag = q.tag || null; const ps = tag ? products.filter(p => (p.tags || []).includes(tag)) : products;
    if (tag && !ps.length) status = 404;
    const h1 = tag ? (en ? TAG_EN[tag] || tag : tag) : (en ? 'All products' : 'كل المنتجات');
    here = P.all(tag); title = h1 + ' | ' + store;
    desc = (en ? `${h1}: ${ps.length} products – ` : `${h1}: ${ps.length} منتج – `) + homeDesc;
    if (status === 200) listPage(h1, [home, [h1, here]], ps);
  } else if (r.view === 'seg') {
    const sg = R.findSeg(r.segKey, R.segments(settings)); const c = sg && q.c ? R.findCat(T, q.c) : null;
    if (!sg || (q.c && (!c || !sg.pick[c.name]))) status = 404;
    else {
      const sn = en ? sg.name_en : sg.name, sd = en ? sg.desc_en : sg.desc;
      const ps = products.filter(p => R.inSeg(sg, p) && (!c || p.cat === c.name)).map((p, i) => [p, i]).sort((a, b) => R.segRank(sg, a[0]) - R.segRank(sg, b[0]) || a[1] - b[1]).map(x => x[0]);
      here = P.seg(sg, c); const h1 = c ? cn(c) + ' – ' + sn : sn; title = h1 + ' | ' + store;
      desc = en ? `Supplies for ${sg.name_en.toLowerCase()}: ${sd}. ${ps.length} products at ${store}, Amman – Jubeiha. Order online, cash on delivery in Jordan.`
        : `مستلزمات ${sg.name}: ${sd}. ${ps.length} منتج من ${store} في عمّان – الجبيهة. اطلب أونلاين والدفع عند الاستلام.`;
      image = abs(sg.img);
      const chips = `<div class="chips">${Object.keys(sg.pick).map(n => T.find(k => k.name === n)).filter(k => k && products.some(p => p.cat === k.name && R.inSeg(sg, p))).map(k => `<a class="chip" href="${esc(L(P.seg(sg, k)))}">${esc(cn(k))}</a>`).join('')}</div>`;
      listPage(h1, c ? [home, [sn, P.seg(sg)], [cn(c), here]] : [home, [sn, here]], ps, `<p class="segd">${esc(sd)}</p>${chips}`);
    }
  } else if (r.view === 'cat') {
    const c = R.findCat(T, r.catSlug); const sx = c && r.subSlug ? R.findSub(c, r.subSlug) : null;
    if (!c || (r.subSlug && !sx)) { status = 404; }
    else {
      const ps = products.filter(p => p.cat === c.name && (!sx || p.sub === sx.name));
      const h1 = sx ? cn(sx) : cn(c); here = P.cat(c, sx);
      title = h1 + (sx ? ' – ' + cn(c) : '') + ' | ' + store;
      const names = sortAvail(ps).slice(0, 4).map(nm).join(en ? ', ' : '، ');
      desc = en ? `${h1}: ${ps.length} products at ${store}, Amman – Jubeiha. ${names}… Order online, cash on delivery in Jordan.`
        : `${h1}: ${ps.length} منتج من ${store} في عمّان – الجبيهة. ${names}… اطلب أونلاين والدفع عند الاستلام.`;
      const im = imgOf(ps.find(imgOf) || {}); if (c.img || im) image = abs(c.img || im);
      const subs = !sx && c.subs.length > 1 ? `<div class="subs">${c.subs.map(x => `<a class="ochip" href="${esc(L(P.cat(c, x)))}">${esc(cn(x))}</a>`).join('')}</div>` : '';
      listPage(h1, sx ? [home, [cn(c), P.cat(c)], [cn(sx), here]] : [home, [cn(c), here]], ps, subs);
    }
  } else if (r.view === 'search') {
    const s = String(q.q || '').trim(); here = P.search(s); title = (en ? 'Search' : 'بحث') + (s ? ': ' + s : '') + ' | ' + store;
    body = `${crumbs([home, [en ? 'Search' : 'بحث', here]])}<div class="pagehead"><h1>${esc(s ? (en ? `Results for “${s}”` : `نتائج البحث عن «${s}»`) : (en ? 'Search' : 'بحث'))}</h1></div>`;
    ld = null;   // search results are not indexed
  } else if (r.view === 'product') {
    const p = products.find(x => String(x.id) === r.pid);
    if (!p) status = 404;
    else {
      const c = T.find(x => x.name === p.cat); const sx = c && c.subs.find(x => x.name === p.sub);
      here = P.product(p); ogType = 'product';
      const d = (en ? (p.desc_en || p.desc) : p.desc) || '';
      title = nm(p) + ' | ' + store;
      desc = (d ? d + ' – ' : '') + (en ? `${priceTxt(p)} – ${avail(p) ? 'in stock' : 'sold out'}. ${store}, Amman – Jubeiha. Order online.` : `${priceTxt(p)} – ${avail(p) ? 'متوفر' : 'نفدت الكمية'}. ${store}، عمّان – الجبيهة. اطلب أونلاين.`);
      if (imgOf(p)) image = abs(imgOf(p));
      const items = [home]; if (c) items.push([cn(c), P.cat(c)]); if (c && sx) items.push([cn(sx), P.cat(c, sx)]); items.push([nm(p), here]);
      const sizes = p.vars.length > 1 ? `<ul>${p.vars.map(v => `<li>${esc(v.label)}${p.ask ? '' : ' — ' + num(v.price) + ' ' + cur}${inStock(v) ? '' : ' (' + (en ? 'sold out' : 'نفد') + ')'}</li>`).join('')}</ul>` : '';
      body = `${crumbs(items)}<article class="pview"><div class="thumb">${imgOf(p) ? `<img src="${esc(imgOf(p))}" alt="${esc(nm(p))}">` : ''}</div><div><h1>${esc(nm(p))}</h1><p class="price">${esc(priceTxt(p))}</p>${avail(p) ? '' : `<p class="oos">${en ? 'Sold out' : 'نفدت الكمية'}</p>`}${d ? `<p>${esc(d)}</p>` : ''}${p.unit ? `<p class="note">${en ? 'Unit' : 'الوحدة'}: ${esc(p.unit)}</p>` : ''}${sizes}</div></article>`;
      const prices = p.vars.map(v => +v.price).filter(x => x > 0);
      const offer = p.ask || !prices.length ? undefined : (Math.min(...prices) === Math.max(...prices)
        ? { '@type': 'Offer', price: num(prices[0]), priceCurrency: 'JOD', availability: 'https://schema.org/' + (avail(p) ? 'InStock' : 'OutOfStock'), url: ORIGIN + L(here), seller: { '@type': 'Organization', name: store } }
        : { '@type': 'AggregateOffer', lowPrice: num(Math.min(...prices)), highPrice: num(Math.max(...prices)), offerCount: p.vars.length, priceCurrency: 'JOD', availability: 'https://schema.org/' + (avail(p) ? 'InStock' : 'OutOfStock'), url: ORIGIN + L(here) });
      ld.push(crumbLd(items), { '@type': 'Product', name: nm(p), description: d || undefined, image: imgOf(p) ? abs(imgOf(p)) : undefined, sku: (p.vars.find(v => v.sku) || {}).sku || undefined, category: c ? cn(c) : undefined, offers: offer });
    }
  } else status = 404;

  if (status === 404) {
    title = (en ? 'Page not found' : 'الصفحة غير موجودة') + ' | ' + store; ld = null;
    body = `<div class="empty"><h1>${en ? 'Page not found' : 'الصفحة غير موجودة'}</h1><p><a href="${esc(L(P.home()))}">${en ? 'Go to the home page' : 'الصفحة الرئيسية'}</a></p></div>`;
  }
  const qs = here.includes('?') ? '&' : '?';
  const urlAr = ORIGIN + here, urlEn = ORIGIN + here + qs + 'lang=en';
  const canonical = en ? urlEn : urlAr;
  const indexable = PUBLIC && status === 200 && r.view !== 'search';
  const org = { '@type': 'Store', name: store, url: ORIGIN + L(P.home()), logo: abs(banner.logo || 'photos/b-logo.jpg'), image: abs('photos/b-store.jpg'),
    telephone: ['+962770983332', '+962788816611'], address: { '@type': 'PostalAddress', streetAddress: en ? 'Jubeiha – Al-Dawriyat traffic light' : 'الجبيهة – إشارة الدوريات', addressLocality: en ? 'Amman' : 'عمّان', addressCountry: 'JO' },
    sameAs: ['https://www.instagram.com/saidnazzalest/', 'https://www.facebook.com/SaidNazzalEstablishment'], priceRange: '$' };
  const graph = ld ? [org, ...ld] : [org];
  const head = [
    `<link rel="canonical" href="${esc(canonical)}">`,
    `<link rel="alternate" hreflang="ar" href="${esc(urlAr)}"><link rel="alternate" hreflang="en" href="${esc(urlEn)}"><link rel="alternate" hreflang="x-default" href="${esc(urlAr)}">`,
    `<meta property="og:site_name" content="${esc(store)}"><meta property="og:type" content="${ogType}"><meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}"><meta property="og:url" content="${esc(canonical)}"><meta property="og:image" content="${esc(image)}"><meta property="og:locale" content="${en ? 'en_US' : 'ar_JO'}">`,
    `<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${esc(title)}"><meta name="twitter:description" content="${esc(desc)}"><meta name="twitter:image" content="${esc(image)}">`,
    `<script type="application/ld+json">${JSON.stringify({ '@context': 'https://schema.org', '@graph': graph }).replace(/</g, '\\u003c')}</script>`
  ].join('\n');
  let html = tpl()
    .replace('<html lang="ar" dir="rtl">', `<html lang="${en ? 'en' : 'ar'}" dir="${en ? 'ltr' : 'rtl'}">`)
    .replace(/<meta name="robots" content="[^"]*">/, `<meta name="robots" content="${indexable ? 'index,follow,max-image-preview:large' : 'noindex,nofollow'}">`)
    .replace(/<title>[^<]*<\/title>/, `<title>${esc(title)}</title>`)
    .replace(/<meta name="description" content="[^"]*">/, `<meta name="description" content="${esc(desc)}">\n${head}`)
    .replace('<main class="wrap" id="app"></main>', `<main class="wrap" id="app">${body}</main>`);
  return { status, html, indexable };
}

module.exports = async (req, res) => {
  const q = req.query || Object.fromEntries(new URL(req.url, 'http://x').searchParams);
  const send = (code, body, headers) => { res.statusCode = code; Object.entries(headers || {}).forEach(([k, v]) => res.setHeader(k, v)); res.end(body); };
  try {
    const priv = q.base === 'private';
    if (!priv && !PUBLIC) {   // public addresses before launch: the coming-soon page
      return send(q.p ? 404 : 200, soon(), { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=0, s-maxage=300' });
    }
    if (priv && PUBLIC) {     // after launch the private link moves to the public address
      const rest = new URLSearchParams(q); ['base', 'p'].forEach(k => rest.delete(k)); const s = rest.toString();
      return send(301, '', { Location: '/' + (q.p || '') + (s ? '?' + s : ''), 'Cache-Control': 'public, max-age=3600' });
    }
    const out = build(await catalog(), q);
    send(out.status, out.html, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=0, s-maxage=300, stale-while-revalidate=86400',
      ...(out.indexable ? {} : { 'X-Robots-Tag': 'noindex, nofollow' }) });
  } catch (e) {   // database unreachable: the plain page (the browser loads the products itself)
    try { send(200, (q.base === 'private' || PUBLIC) ? tpl() : soon(), { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', ...(PUBLIC ? {} : { 'X-Robots-Tag': 'noindex, nofollow' }) }); }
    catch (x) { send(500, 'error', { 'Cache-Control': 'no-store' }); }
  }
};
module.exports.build = build;
