// Parse JavaScript bodies embedded in QML. This is NOT a QML type/import validator.
import fs from 'node:fs';
import vm from 'node:vm';
let count = 0;
function bodyEnd(text, start) {
  let depth=0, quote=null, escaped=false, line=false, block=false;
  for (let i=start;i<text.length;i++) {
    const c=text[i], n=text[i+1];
    if (line) { if(c==='\n') line=false; continue; }
    if (block) { if(c==='*' && n==='/') {block=false;i++;} continue; }
    if (quote) {
      if(escaped) {escaped=false;continue;}
      if(c==='\\') {escaped=true;continue;}
      if(c===quote) quote=null;
      continue;
    }
    if(c==='/' && n==='/') {line=true;i++;continue;}
    if(c==='/' && n==='*') {block=true;i++;continue;}
    if(c==='"' || c==="'" || c==='`') {quote=c;continue;}
    if(c==='{') depth++;
    if(c==='}' && --depth===0) return i;
  }
  throw new Error('Unclosed JavaScript body');
}
for (const file of process.argv.slice(2)) {
  const text=fs.readFileSync(file,'utf8');
  const functions=/\bfunction\s*(?:[A-Za-z_$][\w$]*\s*)?\([^)]*\)\s*(?::\s*\w+\s*)?\{/g;
  for (let m; (m=functions.exec(text));) {
    const start=functions.lastIndex-1, end=bodyEnd(text,start);
    const header=m[0].replace(/\)\s*:\s*\w+\s*\{$/,') {');
    new vm.Script('('+header+text.slice(start+1,end+1)+')',{filename:file});
    count++;
    functions.lastIndex=end+1;
  }
  const handlers=/\bon[A-Z][A-Za-z]+\s*:\s*\{/g;
  for (let m; (m=handlers.exec(text));) {
    const start=handlers.lastIndex-1, end=bodyEnd(text,start);
    new vm.Script('(function(){'+text.slice(start+1,end)+'})',{filename:file});
    count++;
    handlers.lastIndex=end+1;
  }
}
console.log(`QML embedded JavaScript bodies parsed: ${count} (type/import/render checks still require Quickshell)`);
