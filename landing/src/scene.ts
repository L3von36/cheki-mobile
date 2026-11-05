import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';

export type PhoneTheme = 'dark' | 'light';

export type InteractivePhoneScene = {
  setTheme: (value: PhoneTheme) => void;
  setReducedMotion: (value: boolean) => void;
  setScrollProgress: (value: number) => void;
  destroy: () => void;
};

type ScreenState = 0 | 1 | 2;

const darkPalette = {
  screen: '#0b151c',
  panel: '#14252b',
  ink: '#eaf3ef',
  muted: '#819398',
  mint: '#70f3d0',
  violet: '#7b83ff',
  body: '#1b2731',
  rim: '#70f3d0',
};

const lightPalette = {
  screen: '#f7fbf8',
  panel: '#e5f0eb',
  ink: '#122329',
  muted: '#65777a',
  mint: '#087d69',
  violet: '#635cdc',
  body: '#d6e1dc',
  rim: '#087d69',
};

function hexColor(value: string) {
  return new THREE.Color(value);
}

function mixHex(dark: string, light: string, amount: number) {
  return `#${hexColor(dark).lerp(hexColor(light), amount).getHexString()}`;
}

function blendedPalette(amount: number) {
  return {
    screen: mixHex(darkPalette.screen, lightPalette.screen, amount),
    panel: mixHex(darkPalette.panel, lightPalette.panel, amount),
    ink: mixHex(darkPalette.ink, lightPalette.ink, amount),
    muted: mixHex(darkPalette.muted, lightPalette.muted, amount),
    mint: mixHex(darkPalette.mint, lightPalette.mint, amount),
    violet: mixHex(darkPalette.violet, lightPalette.violet, amount),
    body: mixHex(darkPalette.body, lightPalette.body, amount),
    rim: mixHex(darkPalette.rim, lightPalette.rim, amount),
  };
}

function roundedRect(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, radius: number) {
  ctx.beginPath();
  ctx.roundRect(x, y, width, height, radius);
}

function drawScreen(canvas: HTMLCanvasElement, screen: ScreenState, themeMix: number) {
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const palette = blendedPalette(themeMix);
  const isDark = themeMix < 0.5;
  const width = canvas.width;
  const height = canvas.height;
  const scale = width / 560;
  const font = (size: number, weight = 400) => `${weight} ${Math.round(size * scale)}px Arial, sans-serif`;
  const mono = (size: number) => `${Math.round(size * scale)}px monospace`;
  const px = (value: number) => value * scale;

  ctx.fillStyle = palette.screen;
  ctx.fillRect(0, 0, width, height);
  const wash = ctx.createRadialGradient(px(110), px(140), 0, px(110), px(140), px(300));
  wash.addColorStop(0, `rgba(8,125,105,${0.13 - themeMix * 0.03})`);
  wash.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = wash;
  ctx.fillRect(0, 0, width, height);

  ctx.fillStyle = palette.muted;
  ctx.font = mono(10);
  ctx.fillText('9:41', px(30), px(30));
  ctx.fillText('● ● ▮', px(425), px(30));
  ctx.fillStyle = palette.muted;
  ctx.font = mono(11);
  ctx.fillText(screen === 0 ? 'CBE · TELEBIRR · BOA' : screen === 1 ? 'RECEIPT HISTORY' : 'MAHTEM PRO', px(30), px(92));
  ctx.fillStyle = palette.ink;
  ctx.font = font(28, 700);
  ctx.fillText(screen === 0 ? 'Verify a receipt' : screen === 1 ? 'Every check, saved' : 'Own it once', px(30), px(132));
  ctx.strokeStyle = palette.mint;
  ctx.lineWidth = px(1);
  ctx.beginPath();
  ctx.arc(px(478), px(119), px(20), 0, Math.PI * 2);
  ctx.stroke();
  ctx.fillStyle = palette.mint;
  ctx.font = mono(9);
  ctx.fillText('MA', px(466), px(122));

  if (screen === 0) {
    roundedRect(ctx, px(24), px(166), px(512), px(250), px(18));
    ctx.fillStyle = palette.panel;
    ctx.fill();
    ctx.fillStyle = palette.muted;
    ctx.font = mono(11);
    ctx.fillText('RECEIPT CHECK', px(48), px(202));
    ctx.fillStyle = palette.mint;
    ctx.font = font(28, 400);
    ctx.fillText('✓ Verified', px(44), px(254));
    ctx.fillStyle = palette.ink;
    ctx.font = mono(10);
    ctx.fillText('CD8A4K2H9P · CBE · ETB 12,500.00', px(48), px(288));
    for (let pip = 0; pip < 5; pip++) {
      ctx.beginPath();
      ctx.arc(px(56 + pip * 30), px(326), px(6), 0, Math.PI * 2);
      if (pip < 3) {
        ctx.fillStyle = palette.mint;
        ctx.fill();
      } else {
        ctx.strokeStyle = palette.muted;
        ctx.lineWidth = px(1);
        ctx.stroke();
      }
    }
    ctx.fillStyle = palette.muted;
    ctx.font = mono(10);
    ctx.fillText('3 OF 5 FREE', px(212), px(330));
    ctx.strokeStyle = isDark ? 'rgba(255,255,255,.12)' : 'rgba(18,35,41,.12)';
    ctx.beginPath();
    ctx.moveTo(px(48), px(368));
    ctx.lineTo(px(510), px(368));
    ctx.stroke();
    ctx.fillStyle = palette.mint;
    ctx.font = mono(10);
    ctx.fillText('5 free checks · no account needed', px(48), px(400));
    drawCard(ctx, palette, 24, 445, 'NEW CHECK', 'Paste the reference', 'From SMS, PDF or the paper slip');
    drawCard(ctx, palette, 24, 594, 'LATEST RESULT', 'CBE · ETB 12,500', 'Verified · 2m ago');
  } else if (screen === 1) {
    roundedRect(ctx, px(24), px(168), px(512), px(320), px(18));
    ctx.fillStyle = palette.panel;
    ctx.fill();
    ctx.strokeStyle = `${palette.mint}88`;
    ctx.lineWidth = px(2);
    ctx.beginPath();
    ctx.moveTo(px(75), px(375));
    ctx.bezierCurveTo(px(160), px(210), px(280), px(430), px(470), px(235));
    ctx.stroke();
    ctx.strokeStyle = `${palette.violet}bb`;
    ctx.beginPath();
    ctx.moveTo(px(75), px(260));
    ctx.bezierCurveTo(px(180), px(450), px(330), px(180), px(482), px(390));
    ctx.stroke();
    const nodes = [[92, 358], [252, 292], [465, 238], [399, 389]];
    nodes.forEach(([x, y], index) => {
      ctx.fillStyle = index === 2 ? palette.violet : palette.mint;
      ctx.beginPath();
      ctx.arc(px(x), px(y), px(7), 0, Math.PI * 2);
      ctx.fill();
    });
    ctx.fillStyle = palette.muted;
    ctx.font = mono(10);
    ctx.fillText('CHECKS THIS WEEK', px(48), px(202));
    const history = [['CBE · CD8A4K2H9P', 'verified · now'], ['M-Pesa · QPF92K8', 'verified · 1h ago'], ['Telebirr · TB770412', 'not found · 3h ago']];
    history.forEach((row, index) => drawCard(ctx, palette, 24, 522 + index * 118, row[0], row[1], index === 2 ? '✕' : '✓'));
  } else {
    ctx.fillStyle = palette.muted;
    ctx.font = mono(11);
    ctx.fillText('WHAT PRO INCLUDES', px(30), px(184));
    const rows = [['One-time activation', 'ACTIVE', palette.mint, 'unlimited checks · no subscription'], ['Zero-knowledge backup', 'ON', palette.violet, 'encrypted with your password'], ['History on this device', '512 CHECKS', palette.muted, 'syncs to a new phone']] as const;
    rows.forEach((row, index) => {
      const y = 216 + index * 124;
      roundedRect(ctx, px(24), px(y), px(512), px(100), px(16));
      ctx.fillStyle = index === 0 ? palette.panel : `${palette.panel}aa`;
      ctx.fill();
      ctx.fillStyle = row[2];
      ctx.beginPath();
      ctx.arc(px(58), px(y + 50), px(16), 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = index === 0 ? palette.screen : palette.ink;
      ctx.font = font(16, 700);
      ctx.fillText(index === 0 ? '★' : index === 1 ? '▲' : '≡', px(52), px(y + 56));
      ctx.fillStyle = palette.ink;
      ctx.font = font(16, 700);
      ctx.fillText(row[0], px(92), px(y + 43));
      ctx.fillStyle = palette.muted;
      ctx.font = mono(10);
      ctx.fillText(row[3], px(92), px(y + 69));
      ctx.fillStyle = row[2];
      ctx.font = mono(10);
      ctx.fillText(row[1], px(419), px(y + 53));
    });
    ctx.fillStyle = palette.muted;
    ctx.font = mono(11);
    ctx.fillText('CHECKS THIS MONTH', px(30), px(640));
    ctx.fillStyle = palette.mint;
    ctx.font = font(42, 400);
    ctx.fillText('214', px(30), px(690));
  }

  ctx.strokeStyle = isDark ? 'rgba(255,255,255,.12)' : 'rgba(18,35,41,.12)';
  ctx.beginPath();
  ctx.moveTo(px(24), px(1015));
  ctx.lineTo(px(536), px(1015));
  ctx.stroke();
  ctx.fillStyle = palette.mint;
  ctx.font = mono(10);
  ctx.fillText('VERIFY', px(50), px(1060));
  ctx.fillStyle = palette.muted;
  ctx.fillText('HISTORY', px(185), px(1060));
  ctx.fillText('PRO', px(345), px(1060));
  ctx.fillText('MORE', px(466), px(1060));
}

function drawCard(ctx: CanvasRenderingContext2D, palette: typeof darkPalette, x: number, y: number, eyebrow: string, title: string, meta: string) {
  const scale = ctx.canvas.width / 560;
  const px = (value: number) => value * scale;
  roundedRect(ctx, px(x), px(y), px(512), px(100), px(16));
  ctx.fillStyle = palette.panel;
  ctx.fill();
  ctx.fillStyle = palette.muted;
  ctx.font = `${Math.round(10 * scale)}px monospace`;
  ctx.fillText(eyebrow, px(x + 24), px(y + 27));
  ctx.fillStyle = palette.ink;
  ctx.font = `700 ${Math.round(16 * scale)}px Arial, sans-serif`;
  ctx.fillText(title, px(x + 24), px(y + 62));
  ctx.fillStyle = palette.mint;
  ctx.font = `${Math.round(10 * scale)}px monospace`;
  ctx.fillText(meta, px(x + 24), px(y + 83));
}

export function mountInteractivePhone(canvas: HTMLCanvasElement): InteractivePhoneScene {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.1;

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(32, 1, 0.1, 100);
  camera.position.set(0, 0.1, 9.4);

  const phone = new THREE.Group();
  phone.rotation.set(0.05, -0.18, 0.06);
  scene.add(phone);

  const bodyMaterial = new THREE.MeshPhysicalMaterial({ color: darkPalette.body, metalness: 0.72, roughness: 0.24, clearcoat: 0.9, clearcoatRoughness: 0.18 });
  const body = new THREE.Mesh(new RoundedBoxGeometry(3.25, 6.55, 0.38, 8, 0.2), bodyMaterial);
  phone.add(body);

  const screenCanvas = document.createElement('canvas');
  screenCanvas.width = 560;
  screenCanvas.height = 1120;
  drawScreen(screenCanvas, 0, 0);
  const screenTexture = new THREE.CanvasTexture(screenCanvas);
  screenTexture.colorSpace = THREE.SRGBColorSpace;
  screenTexture.anisotropy = renderer.capabilities.getMaxAnisotropy();
  const screenMaterial = new THREE.MeshBasicMaterial({ map: screenTexture, transparent: true, toneMapped: false });
  const screen = new THREE.Mesh(new THREE.PlaneGeometry(2.82, 5.65), screenMaterial);
  screen.position.z = 0.211;
  phone.add(screen);

  const bezelMaterial = new THREE.MeshBasicMaterial({ color: '#05080a' });
  const notch = new THREE.Mesh(new RoundedBoxGeometry(0.75, 0.16, 0.035, 5, 0.07), bezelMaterial);
  notch.position.set(0, 2.58, 0.23);
  phone.add(notch);

  const cameraLens = new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.14, 0.03, 24), new THREE.MeshBasicMaterial({ color: '#142b32' }));
  cameraLens.rotation.x = Math.PI / 2;
  cameraLens.position.set(0.97, 2.59, 0.232);
  phone.add(cameraLens);

  const buttonMaterial = new THREE.MeshStandardMaterial({ color: '#3a4c55', metalness: 0.8, roughness: 0.3 });
  const volume = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.68, 0.12), buttonMaterial);
  volume.position.set(-1.67, 1.2, 0);
  phone.add(volume);
  const power = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.85, 0.12), buttonMaterial);
  power.position.set(1.67, 1.35, 0);
  phone.add(power);

  const ambient = new THREE.AmbientLight('#d6ffff', 0.6);
  scene.add(ambient);
  const key = new THREE.PointLight('#70f3d0', 3.4, 14, 2);
  key.position.set(-4, 3, 5);
  scene.add(key);
  const rim = new THREE.PointLight('#7b83ff', 3.2, 14, 2);
  rim.position.set(4, -1, 4);
  scene.add(rim);
  const backLight = new THREE.PointLight('#70f3d0', 1.5, 9, 2);
  backLight.position.set(0, -4, -3);
  scene.add(backLight);

  let theme: PhoneTheme = 'dark';
  let targetThemeMix = 0;
  let themeMix = 0;
  let renderedThemeMix = 0;
  let reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let scrollProgress = 0;
  let animatedScrollProgress = 0;
  let screenState: ScreenState = 0;
  let startX = 0;
  let dragging = false;
  let frame = 0;
  const clock = new THREE.Clock();
  const targetCamera = new THREE.Vector3(0, 0.1, 9.4);
  const currentCamera = targetCamera.clone();

  function updateScreen(nextScreen: ScreenState) {
    screenState = nextScreen;
    drawScreen(screenCanvas, screenState, themeMix);
    screenTexture.needsUpdate = true;
  }

  function onPointerDown(event: PointerEvent) {
    dragging = true;
    startX = event.clientX;
    canvas.setPointerCapture?.(event.pointerId);
  }

  function onPointerUp(event: PointerEvent) {
    if (!dragging) return;
    dragging = false;
    const delta = event.clientX - startX;
    if (Math.abs(delta) > 35) {
      const direction = delta < 0 ? 1 : -1;
      updateScreen(((screenState + direction + 3) % 3) as ScreenState);
    }
  }

  function onPointerCancel() {
    dragging = false;
  }

  function resize() {
    const rect = canvas.getBoundingClientRect();
    const width = Math.max(rect.width, 1);
    const height = Math.max(rect.height, 1);
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
  }

  function render() {
    const elapsed = clock.getElapsedTime();
    themeMix = THREE.MathUtils.damp(themeMix, targetThemeMix, 4.8, 1 / 60);
    if (Math.abs(themeMix - renderedThemeMix) > 0.002) {
      drawScreen(screenCanvas, screenState, themeMix);
      screenTexture.needsUpdate = true;
      renderedThemeMix = themeMix;
    }
    animatedScrollProgress = THREE.MathUtils.damp(animatedScrollProgress, scrollProgress, reducedMotion ? 8 : 4.5, 1 / 60);
    const smoothScroll = animatedScrollProgress;
    const movement = reducedMotion ? 0 : elapsed;
    phone.rotation.y = -0.18 + Math.sin(movement * 0.7) * 0.035 + smoothScroll * 0.22;
    phone.rotation.x = 0.05 + smoothScroll * -0.16;
    phone.rotation.z = 0.06 + smoothScroll * 0.04;
    phone.position.y = Math.sin(movement * 0.9) * (reducedMotion ? 0.01 : 0.04) - smoothScroll * 0.22;
    targetCamera.z = 9.4 - smoothScroll * 2.05;
    targetCamera.y = 0.1 + smoothScroll * 0.22;
    currentCamera.lerp(targetCamera, reducedMotion ? 0.04 : 0.075);
    camera.position.copy(currentCamera);
    camera.lookAt(0, 0, 0);

    const lightBody = hexColor(lightPalette.body);
    bodyMaterial.color.lerpColors(hexColor(darkPalette.body), lightBody, themeMix);
    bodyMaterial.roughness = THREE.MathUtils.lerp(0.24, 0.5, themeMix);
    bodyMaterial.metalness = THREE.MathUtils.lerp(0.72, 0.2, themeMix);
    ambient.intensity = THREE.MathUtils.lerp(0.6, 1.15, themeMix);
    key.intensity = THREE.MathUtils.lerp(3.4, 2.2, themeMix);
    rim.intensity = THREE.MathUtils.lerp(3.2, 1.4, themeMix);
    backLight.intensity = THREE.MathUtils.lerp(1.5, 0.8, themeMix);
    key.color.lerpColors(hexColor('#70f3d0'), hexColor('#087d69'), themeMix);
    rim.color.lerpColors(hexColor('#7b83ff'), hexColor('#635cdc'), themeMix);

    renderer.render(scene, camera);
    frame = window.requestAnimationFrame(render);
  }

  const resizeObserver = new ResizeObserver(resize);
  resizeObserver.observe(canvas);
  canvas.addEventListener('pointerdown', onPointerDown);
  canvas.addEventListener('pointerup', onPointerUp);
  canvas.addEventListener('pointercancel', onPointerCancel);
  canvas.addEventListener('pointerleave', onPointerCancel);
  resize();
  render();

  return {
    setTheme(value: PhoneTheme) {
      theme = value;
      targetThemeMix = theme === 'light' ? 1 : 0;
    },
    setReducedMotion(value: boolean) {
      reducedMotion = value;
    },
    setScrollProgress(value: number) {
      scrollProgress = THREE.MathUtils.clamp(value, 0, 1);
    },
    destroy() {
      window.cancelAnimationFrame(frame);
      resizeObserver.disconnect();
      canvas.removeEventListener('pointerdown', onPointerDown);
      canvas.removeEventListener('pointerup', onPointerUp);
      canvas.removeEventListener('pointercancel', onPointerCancel);
      canvas.removeEventListener('pointerleave', onPointerCancel);
      scene.traverse((object) => {
        if (object instanceof THREE.Mesh) {
          object.geometry.dispose();
          const material = object.material;
          if (Array.isArray(material)) material.forEach((item) => item.dispose());
          else material.dispose();
        }
      });
      screenTexture.dispose();
      renderer.dispose();
    },
  };
}
