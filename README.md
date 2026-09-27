# Roblox Web Overlay

Stream a webpage into Roblox as an overlay you can click and type on, like an iframe.

## Run it

1. Install [Node.js](https://nodejs.org).
2. In this folder:

   ```powershell
   npm install
   npm start
   ```

   A **Control** window opens and a local server starts. Keep the Control window running.

3. In the Control window, set the page **URL** (and size/FPS if you want), then click **Generate init.lua** and **Copy**.
4. Run the copied script in your Roblox executor. The page appears as an overlay.

## Overlay controls

- **Left click** — click and interact with the page
- **Right click + drag** — move the overlay
- **F7** — toggle keyboard capture (lets you type on the page)
- **F8** — show / hide the overlay

## Requirements

- [Node.js](https://nodejs.org) for the Electron app
- A Roblox executor with the `Drawing` library, `WebSocket`, and `crypt`

## Files

- `main.js` — Electron app + local WebSocket server
- `renderer/index.html` — the Control window
- `luau/overlay.lua` — draws the frames and forwards input
- `luau/init.lua` — optional in-game settings editor