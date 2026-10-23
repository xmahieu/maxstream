import worker from '../worker.js';
const store = new Map();
const env = { LICENCES: { get: async k => store.get(k) ?? null, put: async (k,v) => store.set(k,v), list: async () => ({keys:[...store.keys()].map(name=>({name}))}) },
  PAYPAL_ENV: 'sandbox', PRICE: '15.00', TRIAL_DAYS: '7', PAYPAL_CLIENT_ID: 'id', PAYPAL_SECRET: 's', ADMIN_KEY: 'adm' };
const orders = {};
globalThis.fetch = async (url, opt={}) => {
  const u = new URL(url);
  const J = (d, s=200) => new Response(JSON.stringify(d), {status:s, headers:{'content-type':'application/json'}});
  if (u.pathname === '/v1/oauth2/token') return J({access_token:'tok'});
  if (u.pathname === '/v2/checkout/orders' && opt.method==='POST') { const b = JSON.parse(opt.body); const id='ORD'+Object.keys(orders).length; orders[id]={id, status:'CREATED', amount:b.purchase_units[0].amount, dev:b.purchase_units[0].custom_id}; return J({id, links:[{rel:'payer-action', href:'https://paypal.example/approve?token='+id}]}); }
  const m = u.pathname.match(/^\/v2\/checkout\/orders\/(\w+)(\/capture)?$/);
  if (m) { const o = orders[m[1]]; if (m[2]) o.status='COMPLETED';
    return J({id:o.id, status:o.status, purchase_units:[{custom_id:o.dev, payments: o.status==='COMPLETED'?{captures:[{id:'CAP', status:'COMPLETED', amount:o.amount}]}:undefined}]}); }
  return J({}, 404);
};
const call = (path, method='GET', body) => worker.fetch(new Request('https://lic.test'+path, {method, body: body?JSON.stringify(body):undefined, headers:{'content-type':'application/json'}}), env);
const dev = 'AA:BB:CC:DD:EE:01';
let r = await (await call('/v1/device','POST',{device:dev, platform:'android'})).json();
console.assert(r.status==='trial' && r.days_left===7, 'trial', r);
// expire trial
const rec = JSON.parse(store.get('dev:'+dev)); rec.first -= 8*86400; store.set('dev:'+dev, JSON.stringify(rec));
r = await (await call('/v1/device','POST',{device:dev})).json();
console.assert(r.status==='expired', 'expired', r);
let resp = await call('/pay?d='+dev);
console.assert(resp.status===302 && resp.headers.get('location').includes('ORD0'), 'redirect');
resp = await call('/paypal/return?token=ORD0');
const page = await resp.text();
console.assert(resp.status===200 && page.includes('activé'), 'return page', resp.status);
r = await (await call('/v1/device','POST',{device:dev})).json();
console.assert(r.status==='paid', 'paid', r);
console.assert((await call('/v1/device','POST',{device:'bad'})).status===400, 'invalid');
console.assert((await call('/admin?key=no&d='+dev)).status===403, 'admin forbidden');
r = await (await call('/admin?key=adm&d=AA:BB:CC:DD:EE:02&action=activate')).json();
console.assert(r.licence.status==='paid', 'admin activate');
// webhook path
const dev3='AA:BB:CC:DD:EE:03';
await call('/pay?d='+dev3); orders['ORD1'].status='APPROVED';
r = await (await call('/paypal/webhook','POST',{event_type:'CHECKOUT.ORDER.APPROVED', resource:{id:'ORD1'}})).json();
console.assert(r.device===dev3, 'webhook', r);
console.log('licence worker tests done');
