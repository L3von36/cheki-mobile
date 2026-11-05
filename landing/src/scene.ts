import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import screenHome from './assets/screen-1-home.jpg';
import screenResult from './assets/screen-2-result.jpg';
import screenHistory from './assets/screen-3-history.jpg';
import screenScan from './assets/screen-4-scan.jpg';
import screenPro from './assets/screen-5-pro.jpg';
import screenSettings from './assets/screen-6-settings.jpg';

export type PhoneTheme = 'dark' | 'light';

export type InteractivePhoneScene = {
  setTheme: (value: PhoneTheme) => void;
  setReducedMotion: (value: boolean) => void;
  setScrollProgress: (value: number) => void;
  destroy: () => void;
};

// Real screenshots from the shipping app — one per swipe, in demo order.
const SCREEN_SOURCES = [screenHome, screenResult, screenHistory, screenScan, screenPro, screenSettings];
const SCREEN_COUNT = SCREEN_SOURCES.length;

type ScreenImages = (HTMLImageElement | null)[];

function hexColor(value: string) {
  return new THREE.Color(value);
}

const DARK_BODY = '#1b2731';
const LIGHT_BODY = '#d6e1dc';

// The screen canvas matches the screenshots' native 574x1280 aspect, so the
// texture is a 1:1 fit with nothing cropped.
const SCREEN_CANVAS_WIDTH = 574;
const SCREEN_CANVAS_HEIGHT = 1280;

function drawScreen(canvas: HTMLCanvasElement, screen: number, images: ScreenImages) {
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  ctx.fillStyle = '#0b1218';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  const image = images[screen];
  if (!image || !image.complete || image.naturalWidth === 0) return;
  // Cover-fit so any future screenshot with a slightly different aspect still fills the frame.
  const scale = Math.max(canvas.width / image.naturalWidth, canvas.height / image.naturalHeight);
  const width = image.naturalWidth * scale;
  const height = image.naturalHeight * scale;
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(image, (canvas.width - width) / 2, (canvas.height - height) / 2, width, height);
}

// World-unit bounds of the phone, used to fit it inside the camera frustum.
const PHONE_HEIGHT = 6.55;
const PHONE_WIDTH = 3.5; // body plus the protruding side buttons
const CAMERA_REST_Z = 9.4; // camera distance at scroll 0
const SCREEN_HEIGHT_U = 5.85; // leaves an even ~0.33-unit bezel on all sides
const SCREEN_WIDTH_U = (SCREEN_HEIGHT_U * SCREEN_CANVAS_WIDTH) / SCREEN_CANVAS_HEIGHT;

export function mountInteractivePhone(
  canvas: HTMLCanvasElement,
  options: { onScreenChange?: (screen: number) => void } = {},
): InteractivePhoneScene {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.1;

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(32, 1, 0.1, 100);
  camera.position.set(0, 0.1, CAMERA_REST_Z);

  const phone = new THREE.Group();
  phone.rotation.set(0.05, -0.18, 0.06);
  scene.add(phone);

  const bodyMaterial = new THREE.MeshPhysicalMaterial({ color: DARK_BODY, metalness: 0.72, roughness: 0.24, clearcoat: 0.9, clearcoatRoughness: 0.18 });
  const body = new THREE.Mesh(new RoundedBoxGeometry(3.25, PHONE_HEIGHT, 0.38, 8, 0.2), bodyMaterial);
  phone.add(body);

  const screenCanvas = document.createElement('canvas');
  screenCanvas.width = SCREEN_CANVAS_WIDTH;
  screenCanvas.height = SCREEN_CANVAS_HEIGHT;

  const screenImages: ScreenImages = SCREEN_SOURCES.map((src) => {
    const image = new Image();
    image.onload = () => {
      drawScreen(screenCanvas, screenState, screenImages);
      screenTexture.needsUpdate = true;
    };
    image.src = src;
    return image;
  });

  drawScreen(screenCanvas, 0, screenImages);
  const screenTexture = new THREE.CanvasTexture(screenCanvas);
  screenTexture.colorSpace = THREE.SRGBColorSpace;
  screenTexture.anisotropy = renderer.capabilities.getMaxAnisotropy();
  const screenMaterial = new THREE.MeshBasicMaterial({ map: screenTexture, transparent: true, toneMapped: false });
  const screen = new THREE.Mesh(new THREE.PlaneGeometry(SCREEN_WIDTH_U, SCREEN_HEIGHT_U), screenMaterial);
  screen.position.z = 0.211;
  phone.add(screen);

  // Punch-hole camera over the screenshots' own status bar; the fake notch
  // pill is gone because the real UI carries its own device chrome.
  const bezelMaterial = new THREE.MeshBasicMaterial({ color: '#05080a' });
  const punchHole = new THREE.Mesh(new THREE.CylinderGeometry(0.075, 0.075, 0.03, 24), bezelMaterial);
  punchHole.rotation.x = Math.PI / 2;
  punchHole.position.set(0, SCREEN_HEIGHT_U / 2 - 0.092, 0.222);
  phone.add(punchHole);

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

  let targetThemeMix = 0;
  let themeMix = 0;
  let reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let scrollProgress = 0;
  let animatedScrollProgress = 0;
  let screenState = 0;
  let startX = 0;
  let dragging = false;
  let frame = 0;
  const clock = new THREE.Clock();
  const targetCamera = new THREE.Vector3(0, 0.1, CAMERA_REST_Z);
  const currentCamera = targetCamera.clone();

  function updateScreen(nextScreen: number) {
    screenState = ((nextScreen % SCREEN_COUNT) + SCREEN_COUNT) % SCREEN_COUNT;
    drawScreen(screenCanvas, screenState, screenImages);
    screenTexture.needsUpdate = true;
    options.onScreenChange?.(screenState);
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
      updateScreen(screenState + (delta < 0 ? 1 : -1));
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
    // Scale the phone so it fits the canvas at the resting distance; the
    // scroll-driven push-in is allowed to crop closer by design.
    const frustumHeight = 2 * Math.tan((camera.fov * Math.PI) / 360) * CAMERA_REST_Z;
    const fit = Math.min(
      1,
      (frustumHeight * 0.94) / PHONE_HEIGHT,
      (frustumHeight * camera.aspect * 0.94) / PHONE_WIDTH,
    );
    phone.scale.setScalar(fit);
  }

  function render() {
    const elapsed = clock.getElapsedTime();
    themeMix = THREE.MathUtils.damp(themeMix, targetThemeMix, 4.8, 1 / 60);
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

    const lightBody = hexColor(LIGHT_BODY);
    bodyMaterial.color.lerpColors(hexColor(DARK_BODY), lightBody, themeMix);
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
      targetThemeMix = value === 'light' ? 1 : 0;
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
