const CDP_HTTP = process.env.LIFLY_CDP_HTTP ?? 'http://127.0.0.1:9222';
const TARGET_URL = process.env.LIFLY_WEB_URL ?? 'http://127.0.0.1:8211/';
const ASSERTION_PATTERN = /ViewInsets cannot be negative|_viewInsets\.isNonNegative/i;

class Cdp {
  constructor(url) {
    this.url = url;
    this.nextId = 0;
    this.pending = new Map();
    this.events = [];
  }

  async connect() {
    this.ws = new WebSocket(this.url);
    await new Promise((resolve, reject) => {
      this.ws.onopen = resolve;
      this.ws.onerror = reject;
    });
    this.ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.id && this.pending.has(message.id)) {
        const [resolve, reject] = this.pending.get(message.id);
        this.pending.delete(message.id);
        if (message.error) reject(new Error(JSON.stringify(message.error)));
        else resolve(message.result);
        return;
      }
      if (message.method) this.events.push(message);
    };
    return this;
  }

  send(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = ++this.nextId;
      this.pending.set(id, [resolve, reject]);
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    this.ws?.close();
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function eventText(event) {
  if (event.method === 'Runtime.exceptionThrown') {
    const details = event.params?.exceptionDetails;
    return [details?.text, details?.exception?.description].filter(Boolean).join('\n');
  }
  if (event.method === 'Runtime.consoleAPICalled') {
    return (event.params?.args ?? [])
      .map((arg) => arg.value ?? arg.description ?? '')
      .filter(Boolean)
      .join(' ');
  }
  if (event.method === 'Log.entryAdded') {
    return event.params?.entry?.text ?? '';
  }
  return '';
}

async function findLiflyPage() {
  const targets = await fetch(`${CDP_HTTP}/json/list`).then((response) => response.json());
  const page = targets.find(
    (target) => target.type === 'page' && target.url?.startsWith(TARGET_URL),
  );
  if (!page?.webSocketDebuggerUrl) {
    throw new Error(`Lifly page not found at ${TARGET_URL}`);
  }
  return page;
}

const target = await findLiflyPage();
const page = await new Cdp(target.webSocketDebuggerUrl).connect();

try {
  await page.send('Page.enable');
  await page.send('Runtime.enable');
  await page.send('Log.enable');
  await page.send('Page.bringToFront');

  // Establish a known-good desktop baseline before entering mobile emulation.
  await page.send('Emulation.setDeviceMetricsOverride', {
    width: 1280,
    height: 900,
    deviceScaleFactor: 1,
    mobile: false,
  });
  await sleep(500);
  page.events.length = 0;

  const cycles = Number(process.env.LIFLY_VIEW_INSETS_CYCLES ?? '16');
  for (let cycle = 0; cycle < cycles; cycle += 1) {
    await page.send('Emulation.setDeviceMetricsOverride', {
      width: 390,
      height: 844,
      deviceScaleFactor: 3,
      mobile: true,
      screenWidth: 390,
      screenHeight: 844,
    });
    await sleep(180);
    await page.send('Emulation.setDeviceMetricsOverride', {
      width: 1280,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false,
    });
    await sleep(180);
  }

  await page.send('Emulation.setDeviceMetricsOverride', {
    width: 390,
    height: 844,
    deviceScaleFactor: 3,
    mobile: true,
    screenWidth: 390,
    screenHeight: 844,
  });
  await sleep(900);

  const viewport = await page.send('Runtime.evaluate', {
    expression: `({
      width: window.innerWidth,
      height: window.innerHeight,
      dpr: window.devicePixelRatio,
      bodyText: document.body?.innerText?.slice(0, 120) ?? '',
    })`,
    returnByValue: true,
  });

  const captured = page.events
    .map((event) => ({ event, text: eventText(event) }))
    .filter(({ text }) => text.length > 0);
  const assertion = captured.find(({ text }) => ASSERTION_PATTERN.test(text));

  console.log('[mobile-view-insets] cycles', cycles);
  console.log('[mobile-view-insets] viewport', JSON.stringify(viewport.result.value));
  if (assertion) {
    console.error('[mobile-view-insets] FAIL');
    console.error(assertion.text);
    process.exitCode = 1;
  } else {
    console.log('[mobile-view-insets] PASS');
  }
} finally {
  try {
    await page.send('Emulation.setDeviceMetricsOverride', {
      width: 1280,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false,
    });
  } catch (_) {
    // Best-effort browser restoration only.
  }
  page.close();
}
