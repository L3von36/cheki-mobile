import { useEffect, useRef, useState } from 'react';
import type { InteractivePhoneScene } from './scene';

const featureCards = [
  {
    number: '01',
    title: 'Verify anything.',
    copy: 'CBE, Telebirr, BOA, M-Pesa, Dashen, Awash, Wegagen, Amhara, Abay, Zemen, CBE Birr, Siinqee and eBirr — one app checks them all.',
    tag: '13+ banks & wallets',
  },
  {
    number: '02',
    title: 'Reads every format.',
    copy: 'Paste the reference from an SMS, open the bank\u2019s PDF, check a screenshot — or type the printed code straight off a paper slip.',
    tag: 'SMS · PDF · paper',
  },
  {
    number: '03',
    title: 'Private by design.',
    copy: 'Verification needs no account. An optional one encrypts your history with your password — the server can never read it.',
    tag: 'Zero-knowledge backup',
  },
];

const principles = [
  { value: '13+', label: 'banks & wallets supported' },
  { value: '5', label: 'free checks before you pay' },
  { value: '0', label: 'accounts needed to verify' },
];

// Keep in sync with SCREEN_SOURCES in scene.ts.
const DEMO_SCREEN_COUNT = 6;

type DemoTab = 'Overview' | 'Verify' | 'History';

const workflowSteps = [
  { number: '01', title: 'Paste or scan the receipt', copy: 'Take the reference from an SMS, the bank\u2019s PDF, a screenshot, or the printed slip.' },
  { number: '02', title: 'Mahtem asks the bank', copy: 'The app checks the reference directly with the bank that issued it — no middleman, no guessing.' },
  { number: '03', title: 'Keep the proof', copy: 'Every result is saved to your history, ready to show the sender, the shop, or your records.' },
];

function ProductPreview({ tab }: { tab: DemoTab }) {
  return (
    <div className="product-window" aria-label={`${tab} view of the Mahtem app`}>
      <div className="window-topbar"><div className="window-dots"><i /><i /><i /></div><span className="window-title">mahtem / receipts</span><span className="window-status"><b /> checked 12s ago</span></div>
      <div className="window-layout">
        <aside className="window-sidebar"><div className="window-avatar">MA</div><span className="sidebar-line active" /><span className="sidebar-line" /><span className="sidebar-line" /><span className="sidebar-line short" /><div className="sidebar-bottom"><span className="sidebar-line short" /><span className="sidebar-line" /></div></aside>
        <div className="window-content">
          <div className="window-heading"><div><span className="window-eyebrow">Mahtem / {tab}</span><strong>{tab === 'Overview' ? 'This month at a glance' : tab === 'Verify' ? 'Run a check' : 'Every check, saved'}</strong></div><button className="window-action" type="button">+ New check</button></div>
          {tab === 'Overview' && <div className="dashboard-grid"><div className="dash-card dash-card-wide"><div className="dash-card-head"><span>Checks this month</span><b>214</b></div><div className="clarity-chart"><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /><span /></div><small>Last 30 days <em>·</em> 209 verified</small></div><div className="dash-card"><div className="dash-card-head"><span>Free checks</span><b className="violet-text">3</b></div><div className="thread-stack"><i /><i /><i /><i /></div><small>2 of 5 left</small></div><div className="dash-card dash-card-wide"><div className="dash-card-head"><span>Latest result</span><b className="mint-text">Verified</b></div><div className="next-move"><span>✓</span><p>CBE · ETB 12,500.00 · ref CD8A4K2H9P</p></div></div></div>}
          {tab === 'Verify' && <div className="signals-view"><div className="signal-map"><span className="map-orbit map-orbit-a" /><span className="map-orbit map-orbit-b" /><span className="map-core">MA</span><i className="map-node node-a" /><i className="map-node node-b" /><i className="map-node node-c" /></div><div className="signal-list"><div><b>CBE · CD8A4K2H9P</b><span>verified with bank</span><em>now</em></div><div><b>M-Pesa · QPF92K8</b><span>verified with bank</span><em>2m</em></div><div><b>Telebirr · TB770412</b><span>checking…</span><em>7m</em></div></div></div>}
          {tab === 'History' && <div className="decisions-view"><div className="decision-row decision-highlight"><span className="decision-icon">✓</span><div><b>CBE — ETB 12,500.00</b><small>ref CD8A4K2H9P · today</small></div><strong>Verified</strong></div><div className="decision-row"><span className="decision-icon violet-icon">✓</span><div><b>M-Pesa — ETB 3,200.00</b><small>ref QPF92K8 · yesterday</small></div><strong className="violet-text">Verified</strong></div><div className="decision-row"><span className="decision-icon muted-icon">✕</span><div><b>Telebirr — ETB 890.00</b><small>ref TB770412 · 3 days ago</small></div><strong className="muted-text">Not found</strong></div><div className="decision-summary"><span>This month</span><b>214</b><small>checks · 209 verified</small></div></div>}
        </div>
      </div>
    </div>
  );
}

function PhoneSimulator() {
  return (
    <div className="phone-frame" aria-label="Mahtem mobile app preview">
      <div className="phone-speaker" aria-hidden="true" />
      <div className="phone-screen">
        <div className="phone-status"><span>9:41</span><span>● ● ▮</span></div>
        <div className="phone-header"><div><span className="phone-eyebrow">CBE · Telebirr · BOA</span><strong>Verify</strong></div><span className="phone-avatar">MA</span></div>
        <div className="phone-field-card"><div className="phone-card-top"><span>Free checks</span><b>3 left</b></div><div className="phone-mini-chart"><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /><span /></div><small>2 of 5 used this week</small></div>
        <div className="phone-section-title"><span>Latest check</span><b>Done</b></div>
        <div className="phone-next"><span>✓</span><div><strong>CBE receipt verified</strong><small>CD8A4K2H9P · ETB 12,500 · 2m ago</small></div></div>
        <div className="phone-section-title"><span>Earlier today</span><b>02</b></div>
        <div className="phone-thread"><span className="thread-dot mint-thread" /><div><strong>M-Pesa · QPF92K8</strong><small>Verified with bank</small></div><b>now</b></div>
        <div className="phone-thread"><span className="thread-dot violet-thread" /><div><strong>Telebirr · TB770412</strong><small>Not found — ask for a new slip</small></div><b>3h</b></div>
        <div className="phone-tabbar"><span className="active">⌂<small>Verify</small></span><span>◌<small>History</small></span><span>★<small>Pro</small></span><span>⋯<small>More</small></span></div>
      </div>
    </div>
  );
}

function InteractivePhone({ theme, reducedMotion, onScreenChange }: { theme: 'dark' | 'light'; reducedMotion: boolean; onScreenChange: (screen: number) => void }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const sceneRef = useRef<InteractivePhoneScene | null>(null);

  useEffect(() => {
    let cancelled = false;
    import('./scene').then(({ mountInteractivePhone }) => {
      if (!cancelled && canvasRef.current) {
        sceneRef.current = mountInteractivePhone(canvasRef.current, { onScreenChange });
        sceneRef.current.setTheme(theme);
        sceneRef.current.setReducedMotion(reducedMotion);
      }
    });
    const onScroll = () => {
      const range = Math.max(window.innerHeight * 2.2, 1);
      sceneRef.current?.setScrollProgress(window.scrollY / range);
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    return () => {
      cancelled = true;
      window.removeEventListener('scroll', onScroll);
      sceneRef.current?.destroy();
      sceneRef.current = null;
    };
  }, []);

  useEffect(() => {
    sceneRef.current?.setTheme(theme);
  }, [theme]);

  useEffect(() => {
    sceneRef.current?.setReducedMotion(reducedMotion);
  }, [reducedMotion]);

  return <div className="three-phone-scene"><canvas ref={canvasRef} className="three-phone-canvas" aria-label="Interactive 3D Mahtem phone. Swipe left or right to change app screens." role="img" /><span className="three-phone-hint"><i aria-hidden="true">↔</i> Swipe to explore screens</span></div>;
}

function scrollToId(id: string) {
  document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function App() {
  const [reducedMotion, setReducedMotion] = useState(() => window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  const [demoTab, setDemoTab] = useState<DemoTab>('Overview');
  const [heroScreen, setHeroScreen] = useState(0);
  const [theme, setTheme] = useState<'dark' | 'light'>(() => {
    const requestedTheme = new URLSearchParams(window.location.search).get('theme');
    if (requestedTheme === 'light' || requestedTheme === 'dark') return requestedTheme;
    const storedTheme = window.localStorage.getItem('mahtem-theme');
    if (storedTheme === 'light') return 'light';
    return 'dark';
  });

  useEffect(() => {
    document.documentElement.classList.toggle('reduced-motion', reducedMotion);
  }, [reducedMotion]);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    window.localStorage.setItem('mahtem-theme', theme);
  }, [theme]);

  return (
    <div className="site-shell">
      <div className="grain" aria-hidden="true" />
      <header className="site-header">
        <a className="wordmark" href="#top" aria-label="Mahtem home">
          <span className="wordmark-mark" aria-hidden="true"><i /><i /><i /></span>
          <span>Mahtem</span>
        </a>
        <nav className="main-nav" aria-label="Primary navigation">
          <a href="#how-it-works">How it works</a>
          <a href="#system">Why it&apos;s safe</a>
          <a href="#faq">FAQ</a>
        </nav>
        <div className="header-actions">
          <button className="motion-toggle" type="button" onClick={() => setReducedMotion((value) => !value)} aria-pressed={reducedMotion}>
            <span className="motion-dot" aria-hidden="true" />
            {reducedMotion ? 'Still mode' : 'Live mode'}
          </button>
          <button className="theme-toggle" type="button" onClick={() => setTheme((value) => value === 'dark' ? 'light' : 'dark')} aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`} aria-pressed={theme === 'light'}><span aria-hidden="true">{theme === 'dark' ? '☼' : '◐'}</span>{theme === 'dark' ? 'Light mode' : 'Dark mode'}</button>
          <a className="header-cta" href="/v1/dl/arm64">Get the app <span aria-hidden="true">↗</span></a>
        </div>
      </header>

      <main id="top">
        <section className="hero-section" aria-labelledby="hero-title">
          <div className="hero-copy">
            <p className="eyebrow"><span className="eyebrow-line" /> Receipt verification / ማህተም</p>
            <h1 id="hero-title">Paste a receipt. <em>Know the truth in seconds.</em></h1>
            <p className="hero-description">Mahtem (ማህተም — “stamp”) checks Ethiopian bank and wallet receipts straight with the issuing bank — CBE, Telebirr, BOA, M-Pesa and more, right on your phone.</p>
            <div className="hero-actions">
              <a className="button button-primary" href="/v1/dl/arm64">Download for Android <span aria-hidden="true">↓</span></a>
              <button className="button button-quiet" type="button" onClick={() => scrollToId('demo')}><span className="play-icon" aria-hidden="true">▶</span> See it in action</button>
            </div>
            <div className="hero-footnote"><span className="status-pulse" /> First 5 checks free · no account required</div>
          </div>

          <div className="hero-visual hero-phone-visual" aria-label="Mahtem mobile app preview">
            <div className="phone-visual-label"><span>Live demo / mobile</span><strong>Swipe the screens</strong></div>
            <InteractivePhone theme={theme} reducedMotion={reducedMotion} onScreenChange={setHeroScreen} />
            <div className="phone-visual-caption"><span>Verified with the bank</span><i>↗</i><span>CBE · Telebirr · M-Pesa & more</span></div>
          </div>
          <div className="hero-index" aria-hidden="true"><span>{String(heroScreen + 1).padStart(2, '0')}</span><i /><span>{String(DEMO_SCREEN_COUNT).padStart(2, '0')}</span></div>
        </section>

        <section className="signal-strip" id="signal" aria-label="Mahtem at a glance">
          <div className="strip-intro">One app.<br /><em>Every receipt.</em></div>
          <div className="principles">
            {principles.map((principle) => <div className="principle" key={principle.value}><strong>{principle.value}</strong><span>{principle.label}</span></div>)}
          </div>
          <div className="strip-arrow" aria-hidden="true">↘</div>
        </section>

        <section className="how-section section-pad" id="how-it-works" aria-labelledby="how-title">
          <div className="section-kicker"><span>02 / How it works</span><span>From reference to proof</span></div>
          <div className="how-heading"><div><h2 id="how-title">The app does the<br /><em>checking for you.</em></h2><p>Paste the reference. Ask the bank. Keep the proof.</p></div><span className="how-scroll-cue">Scroll to explore <b>↓</b></span></div>
          <div className="workflow-steps">{workflowSteps.map((step, index) => <div className={`workflow-step ${index === 1 ? 'step-active' : ''}`} key={step.number}><span>{step.number}</span><div><h3>{step.title}</h3><p>{step.copy}</p></div><i aria-hidden="true">↗</i></div>)}</div>
          <div className="demo-block" id="demo">
            <div className="demo-copy"><span className="feature-tag">See it in context</span><h3>One app. Three useful views.</h3><p>Start with the overview, run a check, then find any past receipt the moment you need it again.</p><div className="demo-tabs" role="tablist" aria-label="Mahtem product views">{(['Overview', 'Verify', 'History'] as DemoTab[]).map((tab) => <button key={tab} className={demoTab === tab ? 'active' : ''} type="button" role="tab" aria-selected={demoTab === tab} onClick={() => setDemoTab(tab)}>{tab}<span aria-hidden="true">↗</span></button>)}</div></div>
            <ProductPreview tab={demoTab} />
          </div>
          <div className="mobile-showcase"><div className="mobile-showcase-copy"><span className="feature-tag">The stamp, in your pocket</span><h3>Verify at the counter.</h3><p>A customer shows you a screenshot? A landlord sends a PDF? Check it on the spot — the answer comes from the bank itself, not from the sender&apos;s word.</p><a className="button button-primary" href="/v1/dl/arm64">Get the app <span aria-hidden="true">↗</span></a></div><PhoneSimulator /></div>
        </section>

        <section className="story-section section-pad" id="system" aria-labelledby="story-title">
          <div className="section-kicker"><span>02 / Under the hood</span><span>Direct to the issuing bank</span></div>
          <div className="story-heading"><h2 id="story-title">Trust is not<br /><em>assumed.</em></h2><p>Mahtem verifies against the bank&apos;s own confirmation endpoints. What comes back is what the bank says — nothing dressed up in between.</p></div>
          <div className="story-stage story-product-stage">
            <ProductPreview tab="Verify" />
            <div className="story-callout-list"><div className="story-callout"><span>01</span><strong>Direct, always</strong><p>Every check goes to the bank that issued the receipt.</p></div><div className="story-callout"><span>02</span><strong>Zero-knowledge</strong><p>Optional backup is encrypted with your password — we can&apos;t read it.</p></div><div className="story-callout"><span>03</span><strong>አማርኛ & English</strong><p>The whole app speaks both, end to end.</p></div></div>
          </div>
        </section>

        <section className="feature-section section-pad" aria-labelledby="features-title">
          <div className="section-kicker"><span>03 / The details</span><span>Built for how Ethiopia pays</span></div>
          <div className="feature-intro"><h2 id="features-title">Money moves fast.<br />Mahtem <em>keeps up.</em></h2><p>Payments travel through a dozen apps, PDFs and slips of paper. Mahtem gives every one of them the same answer button.</p></div>
          <div className="feature-list">
            {featureCards.map((feature) => <article className="feature-card" key={feature.number}><div className="feature-number">{feature.number}</div><div className="feature-content"><span className="feature-tag">{feature.tag}</span><h3>{feature.title}</h3><p>{feature.copy}</p></div><span className="feature-link" aria-hidden="true">↗</span></article>)}
          </div>
        </section>

        <section className="faq-section section-pad" id="faq" aria-labelledby="faq-title">
          <div className="section-kicker"><span>05 / Before you begin</span><span>Small questions, clear answers</span></div>
          <div className="faq-layout"><div><h2 id="faq-title">Paying for things<br /><em>should be simple.</em></h2><p>Everything you need to know before your first check.</p></div><div className="faq-list"><details open><summary>Which banks and wallets are supported?<span>+</span></summary><p>CBE, Telebirr, BOA, M-Pesa, Dashen, Awash, Wegagen, Amhara, Abay, Zemen, CBE Birr, Siinqee and eBirr — with more added as they open verification endpoints.</p></details><details><summary>How much does it cost?<span>+</span></summary><p>Your first 5 checks are free. After that, a one-time Pro activation unlocks unlimited checks — no subscription, no recurring fee.</p></details><details><summary>Do I need an account?<span>+</span></summary><p>No. Verification works without signing in. An optional account adds encrypted, zero-knowledge backup, so your history follows you to a new phone.</p></details><details><summary>What can I verify with?<span>+</span></summary><p>An SMS reference, the bank&apos;s PDF receipt, a screenshot, or the printed reference on a paper slip — Mahtem reads them all.</p></details><details><summary>Does Mahtem see my banking data?<span>+</span></summary><p>No. A check carries only the receipt reference. Backups are encrypted on your device with a key derived from your password — the server stores ciphertext it cannot open. Details in the privacy note.</p></details></div></div>
        </section>

        <section className="contact-section" id="contact" aria-labelledby="contact-title">
          <div className="contact-glow" aria-hidden="true" />
          <p className="eyebrow"><span className="eyebrow-line" /> Get the app</p>
          <h2 id="contact-title">Stamp it<br /><em>verified.</em></h2>
          <p>Download Mahtem for Android and make every receipt prove itself.</p>
          <div className="hero-actions">
            <a className="button button-light" href="/v1/dl/arm64">Download for Android <span aria-hidden="true">↗</span></a>
            <a className="button button-quiet" href="/v1/dl/universal">Other devices</a>
          </div>
          <div className="contact-meta"><span>mahtem / 2026</span><span>ማህተም — the stamp for Ethiopian payments.</span></div>
        </section>
      </main>

      <footer className="site-footer"><a className="wordmark" href="#top"><span className="wordmark-mark" aria-hidden="true"><i /><i /><i /></span><span>Mahtem</span></a><div className="footer-links"><a href="#how-it-works">How it works</a><a href="#faq">FAQ</a><a href="/privacy.html">Privacy</a><a href="/v1/dl/arm64">Download</a></div><span>Every receipt, proven.</span></footer>
    </div>
  );
}

export default App;
