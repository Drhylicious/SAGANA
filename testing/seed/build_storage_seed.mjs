// Builds testing/seed/06_storage.sql: every statement that touches storage.buckets / storage.objects in the
// repo's SQL scripts, in the order the scripts were first added to git. (The schema dump has no storage schema.)
import { execSync } from 'node:child_process';
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';

const dir = 'supabase_schema';
const files = readdirSync(dir).filter(f => f.endsWith('.sql'));
const added = f => { try { return Number(execSync(`git log --diff-filter=A --follow --format=%at -- ${dir}/${f}`, { encoding: 'utf8' }).trim().split('\n').pop()) || 0; } catch { return 0; } };

function splitStatements(sql) { // split on ; outside of quotes, comments and $tag$ blocks
  const out = []; let cur = ''; let i = 0; let dollar = null;
  while (i < sql.length) {
    const rest = sql.slice(i);
    if (dollar) { if (rest.startsWith(dollar)) { cur += dollar; i += dollar.length; dollar = null; } else { cur += sql[i++]; } continue; }
    let m;
    if (rest.startsWith('--')) { const e = sql.indexOf('\n', i); const end = e < 0 ? sql.length : e; cur += sql.slice(i, end); i = end; continue; }
    if ((m = rest.match(/^\$[A-Za-z_]*\$/))) { dollar = m[0]; cur += dollar; i += dollar.length; continue; }
    if (sql[i] === "'") { let j = i + 1; while (j < sql.length) { if (sql[j] === "'" && sql[j + 1] === "'") j += 2; else if (sql[j] === "'") break; else j++; } cur += sql.slice(i, j + 1); i = j + 1; continue; }
    if (sql[i] === ';') { out.push(cur.trim()); cur = ''; i++; continue; }
    cur += sql[i++];
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}
const rows = [];
for (const f of files) {
  const txt = readFileSync(`${dir}/${f}`, 'utf8').replace(/\r\n/g, '\n');
  if (!/storage\.(buckets|objects)/.test(txt)) continue;
  const stmts = splitStatements(txt).filter(s => /storage\.(buckets|objects)/.test(s.replace(/^(\s*--.*\n)+/, '')) && !/^\s*(--.*)?$/.test(s));
  if (stmts.length) rows.push({ f, t: added(f), stmts });
}
rows.sort((a, b) => a.t - b.t || a.f.localeCompare(b.f));
let out = '-- Storage buckets and policies rebuilt from the repo scripts (LOCAL test DB). Errors are tolerated.\n';
for (const r of rows) { out += `\n-- ===== ${r.f}\n`; for (const s of r.stmts) out += s + ';\n'; }
writeFileSync('testing/seed/06_storage.sql', out);
console.log(rows.map(r => `${r.f} (${r.stmts.length})`).join('\n'));
