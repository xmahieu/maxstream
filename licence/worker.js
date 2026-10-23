// MaxStream licence server (Cloudflare Worker + KV).
//
// Each device gets 7 days free from its first launch, then a lifetime licence
// for 15 EUR paid with PayPal. Devices are identified by an anonymous code
// derived from the device ID (shown in the app like a MAC address).
//
// Bindings (Cloudflare dashboard > Worker > Settings):
//   KV namespace  LICENCES
//   Variables     PAYPAL_ENV = "live" | "sandbox"   PRICE = "15.00"   TRIAL_DAYS = "7"
//   Secrets       PAYPAL_CLIENT_ID   PAYPAL_SECRET   ADMIN_KEY
//
// Routes
//   POST /v1/device            {device, platform}  -> licence status
//   GET  /pay?d=DEVICE          creates the PayPal order and redirects to PayPal
//   GET  /paypal/return         PayPal comes back here: capture, activate, thank-you page
//   POST /paypal/webhook        PAYMENT.CAPTURE.COMPLETED backup (verified against the PayPal API)
//   GET  /admin?key=..&d=..&action=activate|revoke|reset|show

const DEVICE_RE = /^[0-9A-F]{2}(:[0-9A-F]{2}){5}$/;

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*' },
  });

const html = (title, body, status = 200) =>
  new Response(
    `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title><style>body{margin:0;background:#0B1220;color:#EAF1FB;font:18px/1.6 system-ui,sans-serif;display:flex;min-height:100vh;align-items:center;justify-content:center}
main{max-width:560px;padding:32px;text-align:center}h1{font-size:28px}code{background:#16213A;padding:4px 10px;border-radius:8px;color:#29B6F6}
.ok{color:#29B6F6;font-size:64px}.ko{color:#E5484D;font-size:64px}</style></head><body><main>${body}</main></body></html>`,
    { status, headers: { 'content-type': 'text/html; charset=utf-8' } },
  );

const now = () => Math.floor(Date.now() / 1000);

async function getRecord(env, device) {
  const raw = await env.LICENCES.get('dev:' + device);
  return raw ? JSON.parse(raw) : null;
}

async function putRecord(env, device, rec) {
  await env.LICENCES.put('dev:' + device, JSON.stringify(rec));
}

function status(env, rec) {
  const trialDays = parseInt(env.TRIAL_DAYS || '7', 10);
  const trialEnds = rec.first + trialDays * 86400;
  const t = now();
  return {
    device: rec.device,
    status: rec.paid ? 'paid' : t < trialEnds ? 'trial' : 'expired',
    trial_ends: trialEnds,
    days_left: rec.paid ? null : Math.max(0, Math.ceil((trialEnds - t) / 86400)),
    now: t,
    price: env.PRICE || '15.00',
    currency: 'EUR',
  };
}

// ------------------------------------------------------------------ PayPal
function paypalBase(env) {
  return env.PAYPAL_ENV === 'sandbox' ? 'https://api-m.sandbox.paypal.com' : 'https://api-m.paypal.com';
}

async function paypalToken(env) {
  const resp = await fetch(paypalBase(env) + '/v1/oauth2/token', {
    method: 'POST',
    headers: {
      authorization: 'Basic ' + btoa(env.PAYPAL_CLIENT_ID + ':' + env.PAYPAL_SECRET),
      'content-type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  });
  if (!resp.ok) throw new Error('PayPal auth failed: ' + resp.status);
  return (await resp.json()).access_token;
}

async function paypal(env, method, path, body) {
  const token = await paypalToken(env);
  const resp = await fetch(paypalBase(env) + path, {
    method,
    headers: { authorization: 'Bearer ' + token, 'content-type': 'application/json', prefer: 'return=representation' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await resp.json().catch(() => ({}));
  if (!resp.ok && resp.status !== 422) throw new Error('PayPal ' + path + ': ' + resp.status + ' ' + JSON.stringify(data).slice(0, 300));
  return data;
}

/** Marks the device paid if the order is a completed 15 EUR capture for it. */
async function activateFromOrder(env, order) {
  const unit = (order.purchase_units || [])[0] || {};
  const device = unit.custom_id || unit.reference_id;
  const capture = ((unit.payments || {}).captures || [])[0];
  const price = env.PRICE || '15.00';
  if (!device || !DEVICE_RE.test(device)) return null;
  if (!capture || capture.status !== 'COMPLETED') return null;
  if (capture.amount.currency_code !== 'EUR' || parseFloat(capture.amount.value) + 0.001 < parseFloat(price)) return null;
  const rec = (await getRecord(env, device)) || { device, first: now(), platform: '' };
  if (!rec.paid) {
    rec.paid = true;
    rec.paid_at = now();
    rec.order = order.id;
    rec.capture = capture.id;
    await putRecord(env, device, rec);
  }
  return device;
}

// ------------------------------------------------------------------ handlers
async function handleDevice(request, env) {
  const body = await request.json().catch(() => ({}));
  const device = String(body.device || '').toUpperCase();
  if (!DEVICE_RE.test(device)) return json({ error: 'invalid device' }, 400);
  let rec = await getRecord(env, device);
  if (!rec) {
    rec = { device, first: now(), platform: String(body.platform || '').slice(0, 20), paid: false };
    await putRecord(env, device, rec);
  }
  return json(status(env, rec));
}

async function handlePay(url, env) {
  const device = (url.searchParams.get('d') || '').toUpperCase();
  if (!DEVICE_RE.test(device)) return html('MaxStream', '<p class="ko">✕</p><h1>Code appareil invalide</h1>', 400);
  const rec = await getRecord(env, device);
  if (rec && rec.paid) {
    return html('MaxStream', `<p class="ok">✓</p><h1>Déjà activé</h1><p>L'appareil <code>${device}</code> a déjà sa licence à vie.</p>`);
  }
  const origin = url.origin;
  const order = await paypal(env, 'POST', '/v2/checkout/orders', {
    intent: 'CAPTURE',
    purchase_units: [
      {
        reference_id: device,
        custom_id: device,
        description: 'MaxStream - licence à vie pour l\'appareil ' + device,
        amount: { currency_code: 'EUR', value: env.PRICE || '15.00' },
      },
    ],
    payment_source: {
      paypal: {
        experience_context: {
          brand_name: 'MaxStream',
          locale: 'fr-FR',
          shipping_preference: 'NO_SHIPPING',
          user_action: 'PAY_NOW',
          return_url: origin + '/paypal/return',
          cancel_url: origin + '/paypal/cancel',
        },
      },
    },
  });
  const link = (order.links || []).find((l) => l.rel === 'payer-action' || l.rel === 'approve');
  if (!link) return html('MaxStream', '<p class="ko">✕</p><h1>PayPal indisponible</h1><p>Réessayez dans un instant.</p>', 502);
  return Response.redirect(link.href, 302);
}

async function handleReturn(url, env) {
  const orderId = url.searchParams.get('token');
  if (!orderId) return html('MaxStream', '<h1>Paiement introuvable</h1>', 400);
  let order = await paypal(env, 'POST', '/v2/checkout/orders/' + encodeURIComponent(orderId) + '/capture', {});
  if (order.name === 'UNPROCESSABLE_ENTITY' || !order.purchase_units) {
    order = await paypal(env, 'GET', '/v2/checkout/orders/' + encodeURIComponent(orderId));
  }
  const device = await activateFromOrder(env, order);
  if (!device) {
    return html('MaxStream', '<p class="ko">✕</p><h1>Paiement non confirmé</h1><p>Si vous avez été débité, contactez maxstreamkodi@gmail.com en indiquant le code de votre appareil.</p>', 402);
  }
  return html('MaxStream', `<p class="ok">✓</p><h1>Merci !</h1><p>L'appareil <code>${device}</code> est activé à vie.</p><p>Retournez dans MaxStream : il se débloque tout seul en quelques secondes.</p>`);
}

async function handleWebhook(request, env) {
  const event = await request.json().catch(() => ({}));
  if (event.event_type !== 'PAYMENT.CAPTURE.COMPLETED' && event.event_type !== 'CHECKOUT.ORDER.APPROVED') return json({ ok: true });
  // never trust the payload: read the order back from PayPal
  const orderId =
    event.event_type === 'CHECKOUT.ORDER.APPROVED'
      ? event.resource && event.resource.id
      : event.resource && event.resource.supplementary_data && event.resource.supplementary_data.related_ids &&
        event.resource.supplementary_data.related_ids.order_id;
  if (!orderId) return json({ ok: true });
  let order = await paypal(env, 'GET', '/v2/checkout/orders/' + encodeURIComponent(orderId));
  if (order.status === 'APPROVED') {
    order = await paypal(env, 'POST', '/v2/checkout/orders/' + encodeURIComponent(orderId) + '/capture', {});
  }
  const device = await activateFromOrder(env, order);
  return json({ ok: true, device });
}

async function handleAdmin(url, env) {
  if (!env.ADMIN_KEY || url.searchParams.get('key') !== env.ADMIN_KEY) return json({ error: 'forbidden' }, 403);
  const device = (url.searchParams.get('d') || '').toUpperCase();
  const action = url.searchParams.get('action') || 'show';
  if (action === 'list') {
    const list = await env.LICENCES.list({ prefix: 'dev:', limit: 1000 });
    return json({ count: list.keys.length, devices: list.keys.map((k) => k.name.slice(4)) });
  }
  if (!DEVICE_RE.test(device)) return json({ error: 'invalid device' }, 400);
  let rec = (await getRecord(env, device)) || { device, first: now(), platform: '', paid: false };
  if (action === 'activate') {
    rec.paid = true;
    rec.paid_at = now();
    rec.order = 'manual';
  } else if (action === 'revoke') {
    rec.paid = false;
  } else if (action === 'reset') {
    rec.first = now();
  }
  if (action !== 'show') await putRecord(env, device, rec);
  return json({ record: rec, licence: status(env, rec) });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (request.method === 'OPTIONS') return json({});
      if (url.pathname === '/v1/device' && request.method === 'POST') return await handleDevice(request, env);
      if (url.pathname === '/pay') return await handlePay(url, env);
      if (url.pathname === '/paypal/return') return await handleReturn(url, env);
      if (url.pathname === '/paypal/cancel')
        return html('MaxStream', '<h1>Paiement annulé</h1><p>Aucun montant n\'a été débité. Vous pouvez réessayer depuis l\'application.</p>');
      if (url.pathname === '/paypal/webhook' && request.method === 'POST') return await handleWebhook(request, env);
      if (url.pathname === '/admin') return await handleAdmin(url, env);
      if (url.pathname === '/') return json({ service: 'MaxStream licences', ok: true });
      return json({ error: 'not found' }, 404);
    } catch (err) {
      return json({ error: String(err && err.message ? err.message : err) }, 500);
    }
  },
};
