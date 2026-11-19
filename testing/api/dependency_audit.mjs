// Dependency vulnerability check: sends ONLY public package names and versions from pubspec.lock to the public OSV database.
import { readFileSync, writeFileSync } from 'node:fs';
const lock = readFileSync(new URL('../../pubspec.lock', import.meta.url), 'utf8');
const pkgs = []; let cur = null;
for (const line of lock.split(/\r?\n/)) {
  let m = line.match(/^  ([a-z0-9_]+):$/); if (m) { cur = { name: m[1] }; pkgs.push(cur); continue; }
  m = line.match(/^    version: "?([^"\s]+)"?/); if (m && cur) cur.version = m[1];
  m = line.match(/^    source: (\w+)/); if (m && cur) cur.source = m[1];
  m = line.match(/^    dependency: "?([^"\n]+)"?/); if (m && cur) cur.dep = m[1];
}
const hosted = pkgs.filter(p => p.source === 'hosted' && p.version);
const res = [];
for (let i = 0; i < hosted.length; i += 100) {
  const chunk = hosted.slice(i, i + 100);
  const r = await fetch('https://api.osv.dev/v1/querybatch', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ queries: chunk.map(p => ({ package: { name: p.name, ecosystem: 'Pub' }, version: p.version })) }) });
  const j = await r.json();
  chunk.forEach((p, k) => res.push({ ...p, vulns: (j.results?.[k]?.vulns || []).map(v => v.id) }));
}
const bad = res.filter(x => x.vulns.length);
console.log(`checked ${hosted.length} hosted packages; ${bad.length} with known advisories`);
for (const b of bad) console.log(` - ${b.name} ${b.version} (${b.dep}): ${b.vulns.join(', ')}`);
writeFileSync(new URL('../results/dependency_audit.json', import.meta.url), JSON.stringify({ when: new Date().toISOString(), checked: hosted.length, withAdvisories: bad }, null, 1));
