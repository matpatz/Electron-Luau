const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  back: () => ipcRenderer.send('back'),
  forward: () => ipcRenderer.send('forward'),
  reload: () => ipcRenderer.send('reload'),
  quit: () => ipcRenderer.send('quit'),
  onStatus: (cb) => ipcRenderer.on('status', (_event, status) => cb(status)),
});
