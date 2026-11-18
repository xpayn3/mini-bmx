// The bikes built in the builder, kept in this browser (localStorage). Each is a builder config
// (see bikegen.js PRESETS) plus an id.
const KEY = 'customBikes';

export function listBikes() {
  try {
    const a = JSON.parse(localStorage.getItem(KEY) || '[]');
    return Array.isArray(a) ? a.filter(b => b && typeof b.id === 'string') : [];
  } catch (e) { return []; }
}
function write(list) { try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) { /* private mode */ } }

export function saveBike(cfg) {   // returns the id (a new one if the config has none)
  const list = listBikes();
  const id = cfg.id || `b${Date.now().toString(36)}`;
  const entry = { ...cfg, id };
  const i = list.findIndex(b => b.id === id);
  if (i >= 0) list[i] = entry; else list.push(entry);
  write(list);
  return id;
}
export function deleteBike(id) { write(listBikes().filter(b => b.id !== id)); }
export function getBike(id) { return listBikes().find(b => b.id === id) || null; }
export const gameId = (id) => `c_${id}`;          // the bike's id in the game's bike list / URL
export const storeId = (gid) => (gid && gid.startsWith('c_') ? gid.slice(2) : null);
