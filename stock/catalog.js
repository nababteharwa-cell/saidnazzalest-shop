// Sorts Trust items into the shop's categories by the words in their names.
// Used by the stock app when it publishes Trust items to the website.
(function (root) {
  const B = 'الحلويات والخبز', D = 'تزيين الكيك والحفلات', S = 'علب الحلويات والشوكولاتة', G = 'تغليف وهدايا',
        T = 'تيك أواي وتعبئة الطعام', C = 'القهوة والمشروبات', V = 'التقديم والضيافة', K = 'معدات ومستلزمات المطبخ', X = 'خدمات وطباعة';
  const CAT_EN = { [B]: 'Baking & Pastry', [D]: 'Cake & Party Decor', [S]: 'Sweets & Chocolate Boxes', [G]: 'Gift Packaging',
    [T]: 'Takeaway & Food Packaging', [C]: 'Coffee & Drinks', [V]: 'Serving & Hospitality', [K]: 'Equipment & Kitchen', [X]: 'Services & printing' };
  const SUB_EN = {
    'قوالب سيليكون': 'Silicone moulds', 'قوالب شوكولاتة': 'Chocolate moulds', 'قوالب وصواني كيك': 'Cake tins & trays', 'رينجات وقطاعات': 'Rings & cutters',
    'أدوات التحضير والتزيين': 'Prep & decorating tools', 'أكياس صب وأقماع': 'Piping bags & nozzles', 'ورق خبز وجلدات': 'Baking paper & mats',
    'توبرات وعيدان': 'Toppers & picks', 'فلين وتنسيق': 'Foam & arrangements', 'شموع وزينة': 'Candles & decorations', 'ألعاب ومجسمات': 'Toys & figures',
    'علب كيك': 'Cake boxes', 'علب حلويات': 'Dessert boxes', 'علب شوكولاتة': 'Chocolate boxes', 'قواعد كيك ودانتيل': 'Cake boards & doilies', 'كاسات حلويات': 'Dessert cups',
    'أكياس هدايا وتقديم': 'Gift & carrier bags', 'علب هدايا': 'Gift boxes', 'ستيكرات وريبون': 'Stickers & ribbon', 'ورق تغليف وسلوفان': 'Wrapping & cellophane', 'مرطبانات وعبوات': 'Jars & containers',
    'علب وجبات': 'Meal boxes', 'علب بلاستيك وشفاف': 'Plastic & clear containers', 'ألمنيوم وقصدير': 'Aluminium & foil', 'أكياس ومستلزمات': 'Bags & supplies',
    'صحون وصواني سفري': 'Disposable plates & trays', 'أغطية': 'Lids', 'ورق لف ومحارم': 'Wrapping paper & napkins', 'معالق وأطقم سفري': 'Disposable cutlery', 'كفوف ومرايل': 'Gloves & aprons',
    'كاسات ورق وبلاستيك': 'Paper & plastic cups', 'أغطية ومصاصات وحراكات': 'Lids, straws & stirrers', 'حمّالات كاسات': 'Cup carriers', 'أدوات القهوة والباريستا': 'Coffee & barista tools',
    'أباريق ودلال': 'Jugs & pots', 'قناني وعبوات': 'Bottles',
    'صحون وأطباق': 'Plates & dishes', 'جاطات وزبادي': 'Bowls', 'سدور وصواني تقديم': 'Serving trays', 'ستاندات عرض': 'Display stands', 'سلال': 'Baskets',
    'أدوات المائدة': 'Cutlery & tableware', 'كاسات وفناجين': 'Glasses & cups',
    'أجهزة وماكينات': 'Machines', 'طناجر ومقالي': 'Pots & pans', 'سكاكين وأدوات تقطيع': 'Knives & cutting', 'أدوات المطبخ': 'Kitchen tools', 'حفظ وتخزين': 'Storage',
    'تنظيف': 'Cleaning', 'موازين وعيارات': 'Scales & measures', 'عربايات وأثاث': 'Trolleys & furniture', 'ورق كاشير وباركود': 'Till & label rolls', 'متفرقات': 'Other',
    'خدمات طباعة': 'Printing services' };
  const norm = s => String(s || '').toLowerCase().replace(/[ً-ْـ]/g, '').replace(/[أإآٱ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي').replace(/\s+/g, ' ').trim();
  const has = (t, re) => re.test(t);
  const pack = t => /\/\s*\d{2,}/.test(t);
  const DISP = /بلاستيك|شفاف|فلين|بولسترين|ورق|كرفت|كرافت|قصب|كرتون|سفري/;

  function classify(name, inner) {
    const t = norm(name), w = t.split(' ')[0];
    const r = (cat, sub, kind, hide) => ({ cat, sub, kind: kind || 'box', hide: !!hide });
    if (/^(اجور|كلاشي|كلايش)/.test(t)) return r(X, 'خدمات طباعة', 'sticker', true);
    if (!inner && t.split(' ').length === 1 && !/\d/.test(t)) return r(K, 'متفرقات', 'box', true);   // bare names like "علبة" are placeholders
    if (!inner && custom(t)) { const c = classify(t.replace(/مطبوع.*$/, '').replace(/مخصوص/, '').trim() || 'علب', true); return { ...c, hide: true, custom: true }; }
    if (/^(hard cover|modern)/.test(t)) return r(S, 'علب شوكولاتة', 'box');
    if (/^v ?60/.test(t)) return r(C, 'أدوات القهوة والباريستا', 'pitcher');
    if (/^(cake|كيك) ?(marker|cutter|scraper)/.test(t)) return r(B, 'أدوات التحضير والتزيين', 'ring');
    if (/^tag /.test(t)) return r(G, 'ستيكرات وريبون', 'sticker');
    if (/^dry ice|^(ايس بوكس)/.test(t)) return r(K, 'حفظ وتخزين', 'box');
    if (/^(kenya)/.test(t)) return r(V, 'كاسات وفناجين', 'cup');
    if (/^(am )?(همبا|غطاء همبا|فته|كلوب|بيتزا)/.test(t)) return r(T, 'علب وجبات', 'mealbox');
    if (/^(كب كيك|ورق كب كيك)/.test(t)) return r(B, 'ورق خبز وجلدات', 'sticker');
    if (/^(ساين|حماله تحف)/.test(t)) return r(V, 'ستاندات عرض', 'box');
    if (/^(لازق)/.test(t)) return r(G, 'ستيكرات وريبون', 'sticker');
    if (/^(قشاطه|مماسح|ممسحه|رشاشه|دعاسه|هايجين|نشافه)/.test(t)) return r(K, 'تنظيف', 'box');
    if (/^(شنوار|دبيه|كاسارولا|خفاقه|عجانه|حرجايه|مصافي|منقل)/.test(t)) return r(K, /^(خفاقه|عجانه)/.test(t) ? 'أجهزة وماكينات' : 'طناجر ومقالي', 'pan');
    if (/^(حماله|حامل)/.test(t) && !/اكواب|كاسات/.test(t)) return r(K, 'أدوات المطبخ', 'box');
    if (/^(قواعد|قاعده) فلين/.test(t)) return r(D, 'فلين وتنسيق', 'topper');
    if (/^(صندوق)/.test(t)) return r(K, 'حفظ وتخزين', 'box');
    if (has(t, /^(قالب|قوالب)/)) {
      if (has(t, /شوكولا|شكولا/)) return r(B, 'قوالب شوكولاتة', 'mold');
      if (has(t, /سيل?ي?كون|سلكون/)) return r(B, 'قوالب سيليكون', 'mold');
      return r(B, 'قوالب وصواني كيك', 'mold');
    }
    if (has(t, /^(رينغ|رينج|رنغ|قطاعه|قطاعات|مقاطع)/)) return r(B, 'رينجات وقطاعات', 'ring');
    if (has(t, /(كيس|اكياس) صب|^(اقماع|قمع|نوزل|بز )/)) return r(B, 'أكياس صب وأقماع', 'bag');
    if (has(t, /^(قواعد|قاعده|دانتيل)/) && !has(t, /فلين/)) return r(S, 'قواعد كيك ودانتيل', 'plate');
    if (has(t, /^قطع كيك/)) return r(S, 'علب كيك', 'box');
    if (has(t, /^(علب|علبه)/)) {
      if (has(t, /المنيوم|المينيوم/)) return r(T, 'ألمنيوم وقصدير', 'pan');
      if (has(t, /شوكولا|شكولا|تمر|معمول/)) return r(S, 'علب شوكولاتة', 'box');
      if (has(t, /كيك|تشيز|ماكرون|دونات|كوكيز|حلو|بقلاوه|كنافه|بسكوت|تارت|كب كيك|سويس/)) return r(S, has(t, /كيك|تشيز/) ? 'علب كيك' : 'علب حلويات', 'box');
      if (has(t, /هدايا|هديه|كريستال|مخمل|جلد|فاخر|خشب|مغناطيس/)) return r(G, 'علب هدايا', 'box');
      if (has(t, /وجبات|وجبه|بروستد|برغر|برجر|بيتزا|شاورما|سوشي|بطاطا|صوص|تتبيله|ساندويش|زنجر|فلافل|قصب|بولسترين|فلين|كرفت|كرافت|كرتون|مقسم|سلطه|حمص|بوظه|ايس|نودلز|باستا|دينر|هوت دوغ/)) return r(T, 'علب وجبات', 'mealbox');
      return r(T, 'علب بلاستيك وشفاف', 'box');
    }
    if (w === 'غطاء') return has(t, /كاسات|كاسه|قهوه|لينك|كوب|كب |مشروب/) ? r(C, 'أغطية ومصاصات وحراكات', 'cup') : r(T, 'أغطية', 'box');
    if (has(t, /^(حماله|حامل) (اكواب|كاسات)/)) return r(C, 'حمّالات كاسات', 'cup');
    if (has(t, /^(كاسات|كاسه|كب|كوب|اكواب)/) && (has(t, /ورق|بلاستيك|مطبوع|دبل|اونص|بارد|ساخن|حلا|تشيز|بوظه|فيتامين|بطاطا|كرفت|\/\s*\d{2,}/))) {
      if (has(t, /حلا|تشيز|حلويات|بوظه|موس|تيراميسو/)) return r(S, 'كاسات حلويات', 'cup');
      if (has(t, /بطاطا/)) return r(T, 'علب وجبات', 'cup');
      return r(C, 'كاسات ورق وبلاستيك', 'cup');
    }
    if (has(t, /^(مصاص|مصاصات|حراكات|شلمون)/)) return r(C, 'أغطية ومصاصات وحراكات', 'cup');
    if (has(t, /قهوه|اسبريسو|باريستا|تامبر|فرنش|v60|شيكر|سيرب|حليب ستانلس|بيتشر/) || /^pitcher/.test(t)) return r(C, 'أدوات القهوة والباريستا', 'pitcher');
    if (has(t, /^(ابريق|بكرج|دله|دلال|ترمس|ركوه|صبابه)/)) return r(C, 'أباريق ودلال', 'pitcher');
    if (has(t, /^(قناني|قنينه|عبوه|عبوات)/)) return r(C, 'قناني وعبوات', 'jar');
    if (has(t, /^(كاسات|كاسه|كبجايه|فنجان|فناجين|كوب|اكواب|مج |مجات)/)) return r(V, 'كاسات وفناجين', 'cup');
    if (has(t, /^(اكياس|كيس)/)) {
      if (has(t, /يد|مقبض|هدايا|هديه|كرتون|قاعده عريض|كوكيز|كاندي|حلو|روضه|ارنوب|سولفان|سلوفان|شيفون|مخمل|اكريليك|مربط|مطبوع/) && !has(t, /زباله|نفايات|خبز|شاورما|فلافل|ساندويش|خضار|تفريز|حفظ الطعام|سناك/)) return r(G, 'أكياس هدايا وتقديم', 'bag');
      return r(T, 'أكياس ومستلزمات', 'bag');
    }
    if (has(t, /^(صحن|صحون|طبق|اطباق)/)) {
      if (has(t, /المنيوم|المينيوم/)) return r(T, 'ألمنيوم وقصدير', 'pan');
      if (has(t, DISP) || has(t, /مخبوزات|شبك|تارت حراري|امتصاصي/) || pack(t)) return r(T, 'صحون وصواني سفري', 'plate');
      return r(V, 'صحون وأطباق', 'plate');
    }
    if (has(t, /^(صينيه|صواني)/)) {
      if (has(t, /كيك|خبز|خبيز|تيفال|كنافه|بيتزا|تارت|فرن|كوشوك|زينكر|zenker|مخرم|حراري/)) return r(B, 'قوالب وصواني كيك', 'mold');
      if (has(t, /المنيوم|المينيوم/)) return r(T, 'ألمنيوم وقصدير', 'pan');
      if (has(t, DISP) || has(t, /علب|امتصاصي/) || pack(t)) return r(T, 'صحون وصواني سفري', 'plate');
      return r(V, 'سدور وصواني تقديم', 'plate');
    }
    if (has(t, /^(جاط|زبديه|زبادي|زبدية)/)) return (pack(t) && has(t, DISP)) || has(t, /\/\s*\d{3,}/) ? r(T, 'علب بلاستيك وشفاف', 'box') : r(V, 'جاطات وزبادي', 'plate');
    if (w === 'سدر' || w === 'سدور') return has(t, /بلاستيك مدرج|مدرج/) ? r(K, 'حفظ وتخزين', 'box') : r(V, 'سدور وصواني تقديم', 'plate');
    if (w === 'ستاند') return r(V, 'ستاندات عرض', 'box');
    if (w === 'سله') {
      if (has(t, /تخمير/)) return r(B, 'أدوات التحضير والتزيين', 'mold');
      if (has(t, /مهملات|زباله/)) return r(K, 'تنظيف', 'box');
      if (has(t, /بطاطا|قلي|خضار/)) return r(K, 'أدوات المطبخ', 'box');
      return r(V, 'سلال', 'box');
    }
    if (w === 'طقم') {
      if (has(t, /تغليف|سفري|محرمه/)) return r(T, 'معالق وأطقم سفري', 'box');
      if (has(t, /العاب|اميرات|دينصور|ديناصور/)) return r(D, 'ألعاب ومجسمات', 'topper');
      if (has(t, /مرتبان|مرطبان/)) return r(G, 'مرطبانات وعبوات', 'jar');
      if (has(t, /مقاطع|سباتيولا|ديكور|عيار|بز|نوزل|قطاعات/)) return r(B, 'أدوات التحضير والتزيين', 'ring');
      if (has(t, /سكاكين|سكين مطبخ/)) return r(K, 'سكاكين وأدوات تقطيع', 'box');
      if (has(t, /فناجين|كاسات|فنجان|اكواب/)) return r(V, 'كاسات وفناجين', 'cup');
      return r(V, 'أدوات المائدة', 'plate');
    }
    if (has(t, /^(معالق|معلقه|ملعقه|ملاعق|شوك|شوكه)/)) return pack(t) || has(t, /بلاستيك|خشب|مغلف/) ? r(T, 'معالق وأطقم سفري', 'box') : r(V, 'أدوات المائدة', 'plate');
    if (has(t, /^(سكين|سكينه|سكاكين|ساطور|مسن|مقص|قشاره|مبشره|هراسه|مدق|قطاعه بطاطا)/)) return r(K, 'سكاكين وأدوات تقطيع', 'box');
    if (has(t, /^(ماكنه|ماكينه|خلاط|عصاره|ضاغط|سخان|مطحنه|فرن|ميكسر|نافوره|غاز|فرد|شوايه|قلايه|محمصه)/)) return r(K, 'أجهزة وماكينات', 'fountain');
    if (has(t, /^(طنجره|طناجر|مقلي|مقلاه|كسروله|قدر|طاوه|حله)/)) return r(K, 'طناجر ومقالي', 'pan');
    if (has(t, /^(ميزان|شاف|عيار|ثقاله)/)) return r(K, 'موازين وعيارات', 'pitcher');
    if (has(t, /^(سطل|اسفنج|ممسحه|مكنسه|سكواجه|حاويه|قاتله|بخاخ|طفايه|مساحه|منفضه)/)) return r(K, 'تنظيف', 'box');
    if (has(t, /^(مرتبان|مرطبان|برطمان)/)) return pack(t) || has(t, /فلين|عسل|شمع/) ? r(G, 'مرطبانات وعبوات', 'jar') : r(K, 'حفظ وتخزين', 'jar');
    if (has(t, /^(تبر|تبروير|حافظه|حافضه)/)) return r(K, 'حفظ وتخزين', 'box');
    if (has(t, /^(عربايه|ترولي|رف |عجل)/)) return r(K, 'عربايات وأثاث', 'box');
    if (has(t, /^(كفوف|مريول|قبع|كمامه|غطاء شعر)/)) return r(T, 'كفوف ومرايل', 'box');
    if (has(t, /^(ورق|رول)/)) {
      if (has(t, /حراري|كاش|باركود|فيزا|ليبل/) && !has(t, /سيلكون/)) return r(K, 'ورق كاشير وباركود', 'sticker');
      if (has(t, /سولفان|سلوفان|ريبون|بابلز|هدايا|ليزر|تغليف هدايا/)) return r(G, 'ورق تغليف وسلوفان', 'sticker');
      if (has(t, /خبيز|خبز|زبده|شوي|فرن|cook/) && !has(t, /لف|ساندويش/)) return r(B, 'ورق خبز وجلدات', 'sticker');
      if (has(t, /قصدير|المنيوم/)) return r(T, 'ألمنيوم وقصدير', 'pan');
      return r(T, 'ورق لف ومحارم', 'sticker');
    }
    if (has(t, /^(قصدير)/)) return r(T, 'ألمنيوم وقصدير', 'pan');
    if (has(t, /^(محارم|مناديل|فوط|منديل)/)) return r(T, 'ورق لف ومحارم', 'sticker');
    if (has(t, /^(ريبون|ستيكر|ستكر|ليبل|تاج|تاجات|بطاقات|كروت)/)) return r(G, 'ستيكرات وريبون', 'sticker');
    if (has(t, /^(عيدان|توبر|كيك توبر|شرحات)/)) return r(D, 'توبرات وعيدان', 'topper');
    if (has(t, /^(فلين)/)) return r(D, 'فلين وتنسيق', 'topper');
    if (has(t, /^(مجسم|العاب|لعبه|دمى)/)) return r(D, 'ألعاب ومجسمات', 'topper');
    if (has(t, /^(شمع|ديكور|بالون|زينه|تبر|حشوه|ورد|سكر)/)) return r(D, 'شموع وزينة', 'topper');
    if (has(t, /^(جلده|مفارش|مفرش|حصيره)/)) return r(B, 'ورق خبز وجلدات', 'mold');
    if (has(t, /^(مكبس)/)) return has(t, /معمول|كعك|عجين|برغر|تارت|كوكيز|بسكويت|كريمه|كيك|حلو/) ? r(B, 'أدوات التحضير والتزيين', 'mold') : r(K, 'أدوات المطبخ', 'box');
    if (has(t, /^(مشحاف|مجرود|سباتيولا|سبتيولا|فرشاه|مضرب|منخل|شوبك|مطرحه|كلبه|حراكه|متكه|محقان|سكوب|دروبر)/)) return r(B, 'أدوات التحضير والتزيين', 'pitcher');
    if (has(t, /^(كفكير|مصفاه|ملقط|مغرفه|لوح|مملحه|ممسك|فتاحه|مفتاح|اسياخ|سيخ|حجر|مسكه|شبك|مقلب|مفرمه)/)) return r(K, 'أدوات المطبخ', 'pitcher');
    return r(K, 'متفرقات', 'box');
  }
  // printed items made for one customer (a brand name after "مطبوع") are not for public sale
  const GENERIC = new Set(['مع','يد','للمطاعم','اونص','سم','كغم','غم','مل','دبل','شفاف','ابيض','اسود','كرفت','بني','سادة','ساده','رقم','عريض','دائري','مربع','مستطيل','كبير','صغير','وسط','حراري','عدد','لون','الوان','ملون','سلفر','ذهبي','غطاء','بدون','قطع','جيب','x','cm','ml','oz','fu','di','ah','sh','ch','hp','gt','lb','cc','pp','vip','yu','sc','ec','rc','متر','تقريبا','شاورما','فلافل','برغر','بطاطا','ساندويش','فول','حمص']);
  function custom(t) {
    if (/مخصوص/.test(t)) return true;
    const i = t.indexOf('مطبوع'); if (i < 0) return false;
    const rest = t.slice(i + 5).replace(/([a-z])\.(?=[a-z])/g, '$1').replace(/[\d.,*\/()+\-–]+/g, ' ').split(' ').filter(Boolean);
    return rest.some(w => !GENERIC.has(w) && w.length >= 2);
  }
  const unitOf = name => { const m = norm(name).match(/\/\s*(\d+)/); return m ? 'باكيت ' + m[1] : 'حبة'; };
  const ORDER = [B, D, S, G, T, C, V, K, X];
  root.SNCatalog = { classify, unitOf, CAT_EN, SUB_EN, ORDER, norm };
})(typeof window !== 'undefined' ? window : globalThis);
