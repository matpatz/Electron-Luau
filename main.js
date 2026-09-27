const { app, BrowserWindow, ipcMain } = require('electron');
const { WebSocketServer } = require('ws');
const path = require('path');

const DEFAULT_PORT = 8842;

let pageWindow = null;
let controlWindow = null;
let wss = null;
const clients = new Set();
let frameTimer = null;

// Frame config — sent by the Roblox client over the WebSocket.
let frameConfig = {
  url: 'https://example.com',
  width: 640,
  height: 360,
  fps: 10,
  jpegQuality: 55,
};

// --------------------------- status push ----------------------------
function pushStatus() {
  if (!controlWindow || controlWindow.isDestroyed()) return;
  controlWindow.webContents.send('status', {
    url: frameConfig.url,
    w: frameConfig.width,
    h: frameConfig.height,
    fps: frameConfig.fps,
    quality: frameConfig.jpegQuality,
    port: DEFAULT_PORT,
    pageLoaded: pageWindow ? !pageWindow.webContents.isLoading() : false,
    clients: clients.size,
  });
}

// ------------------------- frame capture ----------------------------
function broadcast(data) {
  for (const c of clients) {
    try {
      if (c.readyState === 1) c.send(data);
    } catch (_) { /* ignore */ }
  }
}

async function captureFrame() {
  if (!pageWindow || pageWindow.isDestroyed()) return;
  if (pageWindow.webContents.isLoading()) return;
  if (clients.size === 0) return; // nobody watching -> skip work
  try {
    let image = await pageWindow.webContents.capturePage({
      x: 0,
      y: 0,
      width: frameConfig.width,
      height: frameConfig.height,
    });
    const size = image.getSize();
    if (size.width !== frameConfig.width || size.height !== frameConfig.height) {
      image = image.resize({ width: frameConfig.width, height: frameConfig.height });
    }
    const jpeg = image.toJPEG(frameConfig.jpegQuality);
    broadcast(JSON.stringify({
      type: 'frame',
      w: frameConfig.width,
      h: frameConfig.height,
      b64: jpeg.toString('base64'),
    }));
  } catch (e) {
    console.error('[capture] failed:', e.message);
  }
}

function startCaptureLoop() {
  if (frameTimer) clearInterval(frameTimer);
  frameTimer = setInterval(captureFrame, Math.round(1000 / frameConfig.fps));
}

// ------------------------- input forwarding -------------------------
// Input is delivered via the Chrome DevTools Protocol (Input.dispatch*).
// Unlike webContents.sendInputEvent, CDP works on a hidden BrowserWindow and
// does not require the window to be focused (which would steal focus from Roblox).

const SHIFT_SYMBOLS = {
  '1': '!', '2': '@', '3': '#', '4': '$', '5': '%',
  '6': '^', '7': '&', '8': '*', '9': '(', '0': ')',
  '-': '_', '=': '+', '[': '{', ']': '}', '\\': '|',
  ';': ':', "'": '"', ',': '<', '.': '>', '/': '?', '`': '~',
};

const SPECIAL_KEYS = {
  Return:    { key: 'Enter',      code: 'Enter',      vk: 0x0d },
  Space:     { key: ' ',          code: 'Space',      vk: 0x20, text: ' ' },
  Backspace: { key: 'Backspace',  code: 'Backspace',  vk: 0x08 },
  Delete:    { key: 'Delete',     code: 'Delete',     vk: 0x2e },
  Tab:       { key: 'Tab',        code: 'Tab',        vk: 0x09 },
  Escape:    { key: 'Escape',     code: 'Escape',     vk: 0x1b },
  Up:        { key: 'ArrowUp',    code: 'ArrowUp',    vk: 0x26 },
  Down:      { key: 'ArrowDown',  code: 'ArrowDown',  vk: 0x28 },
  Left:      { key: 'ArrowLeft',  code: 'ArrowLeft',  vk: 0x25 },
  Right:     { key: 'ArrowRight', code: 'ArrowRight', vk: 0x27 },
  Home:      { key: 'Home',       code: 'Home',       vk: 0x24 },
  End:       { key: 'End',        code: 'End',        vk: 0x23 },
  PageUp:    { key: 'PageUp',     code: 'PageUp',     vk: 0x21 },
  PageDown:  { key: 'PageDown',   code: 'PageDown',   vk: 0x22 },
  Insert:    { key: 'Insert',     code: 'Insert',     vk: 0x2d },
  CapsLock:  { key: 'CapsLock',   code: 'CapsLock',   vk: 0x14 },
};
for (let i = 1; i <= 12; i++) SPECIAL_KEYS['F' + i] = { key: 'F' + i, code: 'F' + i, vk: 0x6f + i };

const PUNCT_CODES = {
  '-': 'Minus', '=': 'Equal', '[': 'BracketLeft', ']': 'BracketRight',
  '\\': 'Backslash', ';': 'Semicolon', "'": 'Quote', ',': 'Comma',
  '.': 'Period', '/': 'Slash', '`': 'Backquote',
};

// key = base key name sent by the Roblox overlay ("A", "0", "-", "Space", …).
function keyInfo(key, shift) {
  if (SPECIAL_KEYS[key]) {
    const s = SPECIAL_KEYS[key];
    return { key: s.key, code: s.code, vk: s.vk, text: s.text ?? null };
  }
  if (/^[A-Z]$/.test(key)) {
    const ch = shift ? key : key.toLowerCase();
    return { key: ch, code: 'Key' + key, vk: key.charCodeAt(0), text: ch };
  }
  if (/^[0-9]$/.test(key)) {
    const ch = shift ? SHIFT_SYMBOLS[key] : key;
    return { key: ch, code: 'Digit' + key, vk: 0x30 + parseInt(key, 10), text: ch };
  }
  if (PUNCT_CODES[key]) {
    const ch = shift ? (SHIFT_SYMBOLS[key] || key) : key;
    return { key: ch, code: PUNCT_CODES[key], vk: 0, text: ch };
  }
  return null;
}

function cdp(method, params) {
  if (!pageWindow || pageWindow.isDestroyed()) return;
  const dbg = pageWindow.webContents.debugger;
  if (!dbg.isAttached()) return;
  dbg.sendCommand(method, params).catch((e) => {
    if (e && /(detached|not attached|session closed)/i.test(e.message || '')) return;
    console.error('[input]', method, 'failed:', e && e.message);
  });
}

function modBits(shift, ctrl, alt, meta) {
  let bits = 0;
  if (alt) bits |= 1;
  if (ctrl) bits |= 2;
  if (meta) bits |= 4;
  if (shift) bits |= 8;
  return bits;
}

function forwardInput(msg) {
  if (!pageWindow || pageWindow.isDestroyed()) return;
  const { kind, x, y, button, key, ch, shift, ctrl, alt, meta } = msg;
  const modifiers = modBits(shift, ctrl, alt, meta);
  const px = Math.round(x || 0);
  const py = Math.round(y || 0);

  switch (kind) {
    case 'mousemove':
      cdp('Input.dispatchMouseEvent', { type: 'mouseMoved', x: px, y: py });
      break;
    case 'mousedown':
      cdp('Input.dispatchMouseEvent', {
        type: 'mousePressed', x: px, y: py, button: button || 'left', clickCount: 1,
      });
      break;
    case 'mouseup':
      cdp('Input.dispatchMouseEvent', {
        type: 'mouseReleased', x: px, y: py, button: button || 'left', clickCount: 1,
      });
      break;
    case 'mousewheel':
      cdp('Input.dispatchMouseEvent', {
        type: 'mouseWheel', x: px, y: py,
        deltaX: msg.deltaX || 0, deltaY: msg.deltaY || 0,
      });
      break;
    case 'keydown': {
      const info = keyInfo(key, shift);
      if (!info) break;
      cdp('Input.dispatchKeyEvent', {
        type: 'keyDown', key: info.key, code: info.code,
        windowsVirtualKeyCode: info.vk, nativeVirtualKeyCode: info.vk, modifiers,
      });
      if (info.text) cdp('Input.dispatchKeyEvent', { type: 'char', text: info.text });
      break;
    }
    case 'keyup': {
      const info = keyInfo(key, shift);
      if (!info) break;
      cdp('Input.dispatchKeyEvent', {
        type: 'keyUp', key: info.key, code: info.code,
        windowsVirtualKeyCode: info.vk, nativeVirtualKeyCode: info.vk, modifiers,
      });
      break;
    }
    case 'char':
      if (ch) cdp('Input.dispatchKeyEvent', { type: 'char', text: ch });
      break;
    default:
      break;
  }
}

// --------------------------- page window ---------------------------
function createPageWindow() {
  if (pageWindow && !pageWindow.isDestroyed()) {
    pageWindow.destroy();
    pageWindow = null;
  }

  pageWindow = new BrowserWindow({
    show: false,
    width: frameConfig.width,
    height: frameConfig.height,
    useContentSize: true,
    webPreferences: {
      backgroundThrottling: false,
      paintWhenInitiallyHidden: true,
      nodeIntegration: false,
      contextIsolation: true,
    },
  });
  pageWindow.webContents.setFrameRate(frameConfig.fps);
  try {
    pageWindow.webContents.debugger.attach('1.3');
  } catch (e) {
    console.error('[page] debugger attach failed:', e.message);
  }
  pageWindow.webContents.on('did-finish-load', () => {
    console.log('[page] loaded', frameConfig.url);
    pushStatus();
  });
  pageWindow.webContents.on('did-fail-load', (_e, code, desc) => {
    console.error('[page] failed to load:', code, desc);
  });
  pageWindow.loadURL(frameConfig.url);
  pageWindow.on('closed', () => { pageWindow = null; });
}

function applyConfig(c) {
  if (!c || typeof c !== 'object') return frameConfig;
  if (typeof c.Url === 'string' && c.Url) frameConfig.url = c.Url;
  if (Number.isFinite(c.Width) && c.Width > 0) frameConfig.width = Math.round(c.Width);
  if (Number.isFinite(c.Height) && c.Height > 0) frameConfig.height = Math.round(c.Height);
  if (Number.isFinite(c.Fps) && c.Fps > 0) frameConfig.fps = Math.round(c.Fps);
  if (Number.isFinite(c.Quality) && c.Quality >= 1 && c.Quality <= 100) frameConfig.jpegQuality = Math.round(c.Quality);

  createPageWindow();
  startCaptureLoop();
  console.log('[config] applied', JSON.stringify(frameConfig));
  pushStatus();
  return frameConfig;
}

// ------------------------- websocket server -------------------------
function handleMessage(socket, raw) {
  let msg;
  try { msg = JSON.parse(raw); } catch (_) { return; }
  if (!msg) return;

  if (msg.type === 'configure') {
    const cfg = applyConfig(msg.config);
    try {
      socket.send(JSON.stringify({ type: 'configured', w: cfg.width, h: cfg.height, fps: cfg.fps }));
    } catch (_) { /* ignore */ }
    return;
  }

  if (msg.type === 'input') {
    forwardInput(msg);
  }
}

function startServer() {
  wss = new WebSocketServer({ host: '127.0.0.1', port: DEFAULT_PORT });

  wss.on('listening', () => {
    console.log(`[ws] listening on ws://127.0.0.1:${DEFAULT_PORT}`);
    pushStatus();
  });

  wss.on('connection', (socket) => {
    clients.add(socket);
    console.log(`[ws] client connected (${clients.size} total)`);
    socket.send(JSON.stringify({ type: 'hello' }));
    pushStatus();

    socket.on('message', (data) => handleMessage(socket, data.toString()));
    socket.on('close', () => {
      clients.delete(socket);
      console.log(`[ws] client left (${clients.size} total)`);
      pushStatus();
    });
    socket.on('error', (e) => console.error('[ws] client error:', e.message));
  });

  wss.on('error', (e) => {
    console.error('[ws] server error:', e.message);
    if (e.code === 'EADDRINUSE') {
      console.error(`[ws] port ${DEFAULT_PORT} is already in use.`);
    }
  });
}

// --------------------------- create windows ---------------------------
function createControlWindow() {
  controlWindow = new BrowserWindow({
    width: 640,
    height: 760,
    title: 'Roblox Web Overlay — Control',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  controlWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  controlWindow.on('closed', () => { controlWindow = null; });
}

// ------------------------------ ipc ------------------------------
ipcMain.on('back', () => { if (pageWindow && pageWindow.webContents.canGoBack()) pageWindow.webContents.goBack(); });
ipcMain.on('forward', () => { if (pageWindow && pageWindow.webContents.canGoForward()) pageWindow.webContents.goForward(); });
ipcMain.on('reload', () => { if (pageWindow) pageWindow.reload(); });
ipcMain.on('quit', () => app.quit());
setInterval(pushStatus, 1000);

// ---------------------------- lifecycle ----------------------------
app.whenReady().then(() => {
  createControlWindow();
  startServer();
});

app.on('window-all-closed', () => app.quit());
