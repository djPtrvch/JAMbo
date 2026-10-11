// WAV (PCM 24 бит) из AudioBuffer: отредактированные сэмплы хранятся и сохраняются в «Файлы» в этом виде.

export function encodeWav(buf: AudioBuffer): ArrayBuffer {
  const chans = buf.numberOfChannels;
  const n = buf.length;
  const bytes = 3;
  const dataLen = n * chans * bytes;
  const out = new ArrayBuffer(44 + dataLen);
  const v = new DataView(out);
  const str = (o: number, s: string) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
  str(0, 'RIFF');
  v.setUint32(4, 36 + dataLen, true);
  str(8, 'WAVE');
  str(12, 'fmt ');
  v.setUint32(16, 16, true);
  v.setUint16(20, 1, true);
  v.setUint16(22, chans, true);
  v.setUint32(24, buf.sampleRate, true);
  v.setUint32(28, buf.sampleRate * chans * bytes, true);
  v.setUint16(32, chans * bytes, true);
  v.setUint16(34, bytes * 8, true);
  str(36, 'data');
  v.setUint32(40, dataLen, true);
  const data = Array.from({ length: chans }, (_, c) => buf.getChannelData(c));
  let o = 44;
  for (let i = 0; i < n; i++) {
    for (let c = 0; c < chans; c++) {
      const s = Math.max(-1, Math.min(1, data[c][i]));
      const x = Math.round(s < 0 ? s * 0x800000 : s * 0x7fffff);
      v.setUint8(o, x & 0xff);
      v.setUint8(o + 1, (x >> 8) & 0xff);
      v.setUint8(o + 2, (x >> 16) & 0xff);
      o += 3;
    }
  }
  return out;
}
