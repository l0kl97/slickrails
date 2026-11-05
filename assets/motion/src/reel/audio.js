/* Showreel soundtrack — rendered offline in the page (OfflineAudioContext), 120 BPM, A minor.
 * Sound follows picture: every cut, gate slam, test flip and green light is a cue from the scenes.
 * Deterministic: noise comes from the seeded PRNG, nothing depends on wall-clock time. */
var REEL;

async function renderSoundtrack(cues, dur, bpm) {
  const SR = 48000, B = 60 / bpm;
  const ctx = new OfflineAudioContext(2, Math.round(SR * dur), SR);
  const R = rng(1210);

  const bus = ctx.createGain();
  bus.gain.setValueAtTime(0.9, 0);
  bus.gain.setValueAtTime(0.9, dur - 0.5);
  bus.gain.linearRampToValueAtTime(0, dur);
  const comp = ctx.createDynamicsCompressor();
  comp.threshold.value = -16; comp.ratio.value = 4; comp.attack.value = 0.003; comp.release.value = 0.15;
  bus.connect(comp).connect(ctx.destination);

  // music sits under a sidechain-style duck on every kick
  const music = ctx.createGain();
  music.connect(bus);
  const nbuf = ctx.createBuffer(1, SR * 2, SR);
  const nd = nbuf.getChannelData(0);
  for (let i = 0; i < nd.length; i++) nd[i] = R() * 2 - 1;

  const hz = (midi) => 440 * Math.pow(2, (midi - 69) / 12);
  const env = (g, t, a, peak, dec) => {
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(peak, t + a);
    g.gain.exponentialRampToValueAtTime(0.0001, t + a + dec);
  };
  const pan = (p, dest) => { const s = ctx.createStereoPanner(); s.pan.value = p; s.connect(dest); return s; };
  function osc(t, type, f0, f1, a, peak, dec, dest = bus, p = 0) {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type; o.frequency.setValueAtTime(f0, t);
    if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(f1, t + a + dec * 0.6);
    env(g, t, a, peak, dec);
    o.connect(g).connect(pan(p, dest));
    o.start(t); o.stop(t + a + dec + 0.05);
  }
  function noise(t, { type = 'highpass', f = 8000, f1 = f, q = 0.7, a = 0.001, peak = 0.2, dec = 0.05, dest = bus, p = 0 }) {
    const s = ctx.createBufferSource(), fl = ctx.createBiquadFilter(), g = ctx.createGain();
    s.buffer = nbuf; fl.type = type; fl.Q.value = q;
    fl.frequency.setValueAtTime(f, t);
    if (f1 !== f) fl.frequency.exponentialRampToValueAtTime(f1, t + a + dec);
    env(g, t, a, peak, dec);
    s.connect(fl).connect(g).connect(pan(p, dest));
    s.start(t, R() * 0.9); s.stop(t + a + dec + 0.05);
  }
  const duck = (t) => {
    music.gain.setValueAtTime(1, t);
    music.gain.linearRampToValueAtTime(0.45, t + 0.01);
    music.gain.linearRampToValueAtTime(1, t + 0.22);
  };

  const kick = (t, v = 1) => { osc(t, 'sine', 150, 42, 0.002, 0.95 * v, 0.34); duck(t); };
  const hat = (t, v = 1, p = 0.25) => noise(t, { f: 8500, peak: 0.07 * v, dec: 0.04, p });
  const clap = (t) => { for (const d of [0, 0.011, 0.023]) noise(t + d, { type: 'bandpass', f: 1700, q: 1.2, peak: 0.22, dec: 0.12 }); };
  const boom = (t) => { osc(t, 'sine', 70, 28, 0.003, 0.9, 1.1); noise(t, { type: 'lowpass', f: 1800, f1: 120, peak: 0.35, dec: 0.5 }); duck(t); };
  const slam = (t, p = 0) => {
    osc(t, 'square', 92, 46, 0.001, 0.18, 0.18, bus, p);          // body
    noise(t, { type: 'bandpass', f: 2600, q: 2, peak: 0.32, dec: 0.07, p }); // latch
    osc(t + 0.004, 'triangle', 1480, 1400, 0.001, 0.07, 0.16, bus, p);  // metal ring
    kick(t, 0.7);
  };
  const flip = (t, n) => osc(t, 'triangle', hz(76 + n * 3), hz(76 + n * 3), 0.002, 0.06, 0.09, music, n ? 0.3 : -0.3);
  const chime = (t, midi, v = 1) => {
    osc(t, 'sine', hz(midi), hz(midi), 0.004, 0.13 * v, 0.9, music);
    osc(t, 'sine', hz(midi + 12), hz(midi + 12), 0.004, 0.04 * v, 0.5, music);
  };

  // harmony: Am – F – C – G, one chord per bar (2 s)
  const CHORDS = [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]];
  const ROOTS = [33, 29, 36, 31];
  for (let bar = 0; bar * 4 * B < dur; bar++) {
    const t0 = bar * 4 * B, ch = CHORDS[bar % 4];
    const outroBar = t0 >= 13 - 1e-6;
    for (const m of outroBar ? [57, 60, 64, 71] : ch) {
      for (const det of [-7, 7]) {
        const o = ctx.createOscillator(), f = ctx.createBiquadFilter(), g = ctx.createGain();
        o.type = 'sawtooth'; o.frequency.value = hz(m); o.detune.value = det;
        f.type = 'lowpass'; f.frequency.setValueAtTime(t0 < 4 ? 700 : 1300, t0); f.Q.value = 0.5;
        const len = outroBar ? dur - t0 : 4 * B;
        g.gain.setValueAtTime(0.0001, t0);
        g.gain.linearRampToValueAtTime(0.022, t0 + 0.25);
        g.gain.setValueAtTime(0.022, t0 + len - 0.12);
        g.gain.linearRampToValueAtTime(0.0001, t0 + len);
        o.connect(f).connect(g).connect(pan(det > 0 ? 0.35 : -0.35, music));
        o.start(t0); o.stop(t0 + len + 0.05);
      }
    }
  }
  // bass: quarter notes from the first cut, eighths from the grid
  for (let t = 1.0; t < 13 - 1e-6; t += B / 2) {
    const eighthOff = Math.abs((t / B) % 1 - 0.5) < 1e-6;
    if (t < 4 && eighthOff) continue;
    const root = ROOTS[Math.floor(t / (4 * B)) % 4];
    const o = ctx.createOscillator(), f = ctx.createBiquadFilter(), g = ctx.createGain();
    o.type = 'sawtooth'; o.frequency.value = hz(root + 12);
    f.type = 'lowpass'; f.Q.value = 5;
    f.frequency.setValueAtTime(900, t); f.frequency.exponentialRampToValueAtTime(140, t + 0.18);
    env(g, t, 0.004, 0.16, 0.2);
    o.connect(f).connect(g).connect(music);
    o.start(t); o.stop(t + 0.3);
  }
  // drums: kick on every beat 1–13, hats + clap from the grid
  for (let t = 1.0; t < 13 - 1e-6; t += B) {
    kick(t, t < 4 ? 0.8 : 1);
    if (t >= 4) {
      hat(t + B / 2, 1, 0.25);
      if (Math.round((t - 4) / B) % 2 === 1) clap(t);
    } else hat(t + B / 2, 0.5, -0.2);
  }
  for (let t = 9.0; t < 13 - 1e-6; t += B / 4) hat(t, 0.35, -0.3); // tension 16ths under the agent scene
  noise(3.0, { type: 'bandpass', f: 300, f1: 7000, q: 1.5, a: 0.95, peak: 0.12, dec: 0.04 }); // into the grid
  noise(12.0, { type: 'bandpass', f: 300, f1: 6000, q: 1.5, a: 0.95, peak: 0.1, dec: 0.04 });  // into the outro

  const SCALE = [69, 72, 76, 79, 81, 84];
  let chimeN = 0;
  for (const c of cues) {
    if (c.type === 'riser') noise(c.t, { type: 'bandpass', f: 400, f1: 6000, q: 2, a: c.len * 0.95, peak: 0.16, dec: 0.04 });
    else if (c.type === 'tick') osc(c.t, 'sine', 2200, 2200, 0.001, 0.08, 0.03);
    else if (c.type === 'cut') boom(c.t);
    else if (c.type === 'slam') slam(c.t, (R() - 0.5) * 0.6);
    else if (c.type === 'flip') flip(c.t, c.n || 0);
    else if (c.type === 'chime') chime(c.t, SCALE[chimeN++ % SCALE.length]);
    else if (c.type === 'snap') noise(c.t, { type: 'bandpass', f: 900, f1: 3500, q: 1, a: 0.2, peak: 0.08, dec: 0.25 });
    else if (c.type === 'station') chime(c.t, [81, 84, 88][c.n], 1.3);
    else if (c.type === 'lock') { osc(c.t, 'sine', hz(45), hz(45), 0.01, 0.4, 1.4); }
  }

  const buf = await ctx.startRendering();
  return wavBase64(buf);
}

// 16-bit PCM stereo WAV, base64 (so Playwright can carry it out of the page).
function wavBase64(buf) {
  const n = buf.length, ch = buf.numberOfChannels, sr = buf.sampleRate;
  const bytes = new Uint8Array(44 + n * ch * 2), v = new DataView(bytes.buffer);
  const str = (o, s) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); };
  str(0, 'RIFF'); v.setUint32(4, 36 + n * ch * 2, true); str(8, 'WAVE'); str(12, 'fmt ');
  v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, ch, true);
  v.setUint32(24, sr, true); v.setUint32(28, sr * ch * 2, true); v.setUint16(32, ch * 2, true); v.setUint16(34, 16, true);
  str(36, 'data'); v.setUint32(40, n * ch * 2, true);
  const data = [...Array(ch)].map((_, c) => buf.getChannelData(c));
  let o = 44, peak = 0;
  for (let i = 0; i < n; i++) for (let c = 0; c < ch; c++) peak = Math.max(peak, Math.abs(data[c][i]));
  const gain = peak > 0.89 ? 0.89 / peak : 1; // normalise to -1 dBFS ceiling, never clip
  for (let i = 0; i < n; i++) for (let c = 0; c < ch; c++, o += 2) v.setInt16(o, Math.round(clamp(data[c][i] * gain, -1, 1) * 32767), true);
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}
