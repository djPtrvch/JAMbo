// Хранилище в браузере (IndexedDB): проекты и сэмплы.
// Сэмпл хранится один раз по ключу от его содержимого (s:<хэш>), проекты ссылаются на ключи.
// Проект: { id, name, updated, doc }.

const DB = 'jambo';
const VERSION = 1;

export interface ProjectInfo { id: string; name: string; updated: number }
export interface ProjectRecord extends ProjectInfo { doc: unknown }
export interface SampleRecord { key: string; name: string; bytes: ArrayBuffer }

let dbPromise: Promise<IDBDatabase> | null = null;

function open(): Promise<IDBDatabase> {
  dbPromise ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('projects')) db.createObjectStore('projects', { keyPath: 'id' });
      if (!db.objectStoreNames.contains('samples')) db.createObjectStore('samples', { keyPath: 'key' });
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

async function run<T>(store: string, mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await open();
  return new Promise((resolve, reject) => {
    const req = fn(db.transaction(store, mode).objectStore(store));
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export const putProject = (p: ProjectRecord) => run('projects', 'readwrite', (s) => s.put(p));
export const getProject = (id: string) => run<ProjectRecord | undefined>('projects', 'readonly', (s) => s.get(id));
export const deleteProject = (id: string) => run('projects', 'readwrite', (s) => s.delete(id));

/** Список проектов (без содержимого), новые сверху. */
export async function listProjects(): Promise<ProjectInfo[]> {
  const all = await run<ProjectRecord[]>('projects', 'readonly', (s) => s.getAll());
  return all.map(({ id, name, updated }) => ({ id, name, updated })).sort((a, b) => b.updated - a.updated);
}

export const getSample = (key: string) => run<SampleRecord | undefined>('samples', 'readonly', (s) => s.get(key));

/** Сохранить сэмпл, если его ещё нет. */
export async function putSample(rec: SampleRecord): Promise<void> {
  const has = await run<IDBValidKey | undefined>('samples', 'readonly', (s) => s.getKey(rec.key));
  if (!has) await run('samples', 'readwrite', (s) => s.put(rec));
}

/** Ключ сэмпла по содержимому: одинаковые файлы хранятся один раз. */
export async function sampleKey(bytes: ArrayBuffer): Promise<string> {
  const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return 's:' + Array.from(hash.slice(0, 12), (b) => b.toString(16).padStart(2, '0')).join('');
}

export const newId = () => `p${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

// ---------- Файл проекта (.jambo): экспорт и импорт ----------
// Формат: 'JMB1', длина заголовка (uint32), заголовок JSON { name, doc, samples: [{ key, name, size }] },
// затем байты сэмплов подряд.

const MAGIC = 'JMB1';

export function packProject(name: string, doc: unknown, samples: SampleRecord[]): Blob {
  const header = new TextEncoder().encode(JSON.stringify({
    format: 'jambo', version: 1, name, doc, samples: samples.map((s) => ({ key: s.key, name: s.name, size: s.bytes.byteLength })),
  }));
  const len = new Uint8Array(4);
  new DataView(len.buffer).setUint32(0, header.byteLength);
  return new Blob([MAGIC, len, header, ...samples.map((s) => s.bytes)], { type: 'application/octet-stream' });
}

export async function unpackProject(file: Blob): Promise<{ name: string; doc: unknown; samples: SampleRecord[] }> {
  const buf = await file.arrayBuffer();
  if (new TextDecoder().decode(buf.slice(0, 4)) !== MAGIC) throw new Error('not a JAMbo project');
  const len = new DataView(buf, 4, 4).getUint32(0);
  const header = JSON.parse(new TextDecoder().decode(buf.slice(8, 8 + len)));
  let pos = 8 + len;
  const samples: SampleRecord[] = header.samples.map((s: { key: string; name: string; size: number }) => {
    const bytes = buf.slice(pos, pos + s.size);
    pos += s.size;
    return { key: s.key, name: s.name, bytes };
  });
  return { name: header.name, doc: header.doc, samples };
}
