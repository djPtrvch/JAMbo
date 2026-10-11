// Обмен библиотеки с «Файлами» (iPad и iCloud Drive). Веб-страница не может сама держать папку
// на диске, поэтому: EXPORT — файл через окно «Поделиться» («Сохранить в Файлы» — любая папка
// на iPad или в iCloud Drive; где его нет — обычная загрузка), сэмпл — исходным файлом, папка —
// одним .zip с подпапками, сэмплами и пресетами (.jambopreset). IMPORT — аудиофайлы, .jambopreset
// и .zip (папки архива восстанавливаются внутри открытой папки).

import { importAudioFiles } from './audio/engine';
import { addPreset, addSample, children, createFolder, node, type LibNode } from './library';
import type { Preset } from './state';
import { getSample } from './storage';
import { unzip, zip, type ZipEntry } from './zip';

const PRESET_EXT = '.jambopreset';
const safe = (s: string) => s.replace(/[\\/:*?"<>|]+/g, '_').trim() || 'untitled';
const enc = new TextEncoder();

/** Отдать файл: окно «Поделиться» (выбор папки в «Файлах»), иначе — загрузка. */
export async function saveFile(blob: Blob, name: string) {
  const file = new File([blob], name, { type: blob.type || 'application/octet-stream' });
  const nav = navigator as Navigator & { canShare?: (d: ShareData) => boolean };
  if (nav.canShare?.({ files: [file] })) {
    try { await navigator.share({ files: [file] }); return; } catch (e) {
      // Отмена — ничего не делаем; нет разрешения (жест истёк) — обычная загрузка.
      if ((e as Error)?.name === 'AbortError') return;
    }
  }
  const url = URL.createObjectURL(file);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}

/** Имя файла сэмпла: имя в библиотеке и расширение исходного файла. */
function sampleFileName(n: LibNode, original: string): string {
  const ext = /\.[^.]+$/.exec(original)?.[0] ?? '.wav';
  return safe(n.name.replace(/\.[^.]+$/, '')) + ext;
}

/** Содержимое папки для архива (пути относительно prefix). */
async function collect(folder: LibNode, prefix: string, out: ZipEntry[]) {
  // Папка — отдельной записью (пустые подпапки тоже переносятся).
  out.push({ path: prefix, data: new Uint8Array(0) });
  for (const n of children(folder.id)) {
    if (n.kind === 'folder') await collect(n, `${prefix}${safe(n.name)}/`, out);
    else if (n.kind === 'sample' && n.key) {
      const rec = await getSample(n.key);
      if (rec) out.push({ path: prefix + sampleFileName(n, rec.name), data: new Uint8Array(rec.bytes) });
    } else if (n.kind === 'preset' && n.preset) {
      out.push({ path: `${prefix}${safe(n.name)}${PRESET_EXT}`, data: enc.encode(JSON.stringify({ jambo: 'preset', preset: n.preset })) });
    }
  }
}

/** EXPORT: сэмпл — исходный файл, пресет — .jambopreset, папка — .zip. */
export async function exportNode(id: string) {
  const n = node(id);
  if (!n) return;
  if (n.kind === 'sample' && n.key) {
    const rec = await getSample(n.key);
    if (rec) await saveFile(new Blob([rec.bytes]), sampleFileName(n, rec.name));
  } else if (n.kind === 'preset' && n.preset) {
    await saveFile(new Blob([JSON.stringify({ jambo: 'preset', preset: n.preset })], { type: 'application/json' }), `${safe(n.name)}${PRESET_EXT}`);
  } else if (n.kind === 'folder') {
    const entries: ZipEntry[] = [];
    await collect(n, `${safe(n.name)}/`, entries);
    await saveFile(zip(entries), `${safe(n.name)}.zip`);
  }
}

/** Папка name внутри parent (есть — она, нет — новая). */
function folderIn(parent: string, name: string): string {
  const f = children(parent).find((x) => x.kind === 'folder' && x.name === name);
  return f ? f.id : createFolder(parent, name).id;
}

function readPreset(data: Uint8Array, fallback: string): Preset | null {
  try {
    const j = JSON.parse(new TextDecoder().decode(data));
    const p = j?.preset;
    if (p && typeof p.sound === 'string' && p.params) return { name: p.name || fallback, sound: p.sound, params: p.params };
  } catch { /* не пресет */ }
  return null;
}

/** IMPORT в папку into: аудио, .jambopreset и .zip (с папками). Возвращает число добавленных. */
export async function importInto(into: string, files: File[]): Promise<number> {
  let added = 0;
  const one = async (parent: string, file: File) => {
    const lower = file.name.toLowerCase();
    if (lower.endsWith('.zip')) {
      for (const e of await unzip(file)) {
        if (e.path.endsWith('/')) {
          let dir = parent;
          for (const p of e.path.split('/').filter(Boolean)) dir = folderIn(dir, p);
          continue;
        }
        const parts = e.path.split('/');
        const base = parts.pop()!;
        let dir = parent;
        for (const p of parts) dir = folderIn(dir, p);
        await one(dir, new File([e.data as Uint8Array<ArrayBuffer>], base));
      }
    } else if (lower.endsWith(PRESET_EXT)) {
      const p = readPreset(new Uint8Array(await file.arrayBuffer()), file.name.slice(0, -PRESET_EXT.length));
      if (p) { addPreset(parent, p); added++; }
    } else {
      try {
        for (const f of await importAudioFiles([file])) { addSample(parent, f.key, f.name); added++; }
      } catch { /* не аудио — пропускаем */ }
    }
  };
  for (const f of files) await one(into, f);
  return added;
}
