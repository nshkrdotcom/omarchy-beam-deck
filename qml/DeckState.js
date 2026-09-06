.pragma library

function emptySnapshot() {
  return {type:"snapshot", protocol:1, onboarding:{state:"starting"}, summary:{runtime_count:0, attached_count:0, warning_count:0, critical_count:0},
    host:{logical_cpus:0,runtimes:[],memory:{}}, nodes:[], alerts:[], budget:[], history:[], events:[],
    forecasts:[], incidents:[], crash_triage:[], budget_trial:null, watchlist:{entries:[],error:null},
    flight_recorder:{frame_count:0,timeline:[]}};
}
function terminal(status) { return ["complete","error","canceled"].indexOf(status) >= 0; }
function pruneJobs(jobs, now) {
  var keys=Object.keys(jobs).filter(function(k) { return now-Number(jobs[k].updated_at || 0) < 120000; });
  keys.sort(function(a,b) { return Number(jobs[b].updated_at || 0)-Number(jobs[a].updated_at || 0); });
  var out={}; keys.slice(0,32).forEach(function(k) { out[k]=jobs[k]; }); return out;
}
function acceptJob(jobs, message, now) {
  var id=String(message.request_id || "");
  if (!/^[A-Za-z0-9._:-]{1,64}$/.test(id) || ["queued","started","complete","error","canceled"].indexOf(message.status)<0) return jobs;
  var previous=jobs[id];
  if (previous && terminal(previous.status)) return jobs;
  var next=Object.assign({}, jobs);
  next[id]=Object.assign({}, previous || {}, message, {updated_at:now});
  return pruneJobs(next, now);
}
function jobFor(jobs, id, kind, node) {
  var job=id ? jobs[id] : null;
  if (!job || job.kind!==kind || (node!==undefined && job.node!==node)) return null;
  return job;
}
function cancelInteractive(jobs, now) {
  var next={};
  Object.keys(jobs).forEach(function(k) {
    var job=jobs[k];
    next[k]=["inspect_process","inspect_ets","recorder_frame","compare_frames"].indexOf(job.kind)>=0 && !terminal(job.status)
      ? Object.assign({},job,{status:"canceled",updated_at:now}) : job;
  }); return next;
}
function canMutate(snapshot, historical, running, now, node) {
  if (historical || !running || !snapshot.at_ms || now-snapshot.at_ms>10000 || now<snapshot.at_ms-5000) return false;
  if (node===undefined) return true;
  return (snapshot.nodes || []).some(function(n) { return n.name===node && n.attached; });
}
function canActOnProcess(snapshot, report, historical, running, now) {
  if (!report || !report.at_ms || now-report.at_ms>10000 || now<report.at_ms-5000 || !Number.isInteger(report.creation)) return false;
  if (!canMutate(snapshot,historical,running,now,report.node)) return false;
  return (snapshot.nodes || []).some(function(n) { return n.name===report.node && n.creation===report.creation; });
}
function boundedText(text, max) { return String(text || "").replace(/[\u0000-\u001f\u007f]/g," ").slice(0,max); }
function notificationArgs(message) {
  var urgency=["low","normal","critical"].indexOf(message.urgency)>=0 ? message.urgency : "normal";
  return ["omarchy-notification-send","-u",urgency,boundedText(message.title,120),boundedText(message.body,240)];
}
function bytes(n) {
  if (n===null || n===undefined || !isFinite(Number(n))) return "\u2014";
  n=Number(n); var units=["B","KiB","MiB","GiB","TiB"], index=0;
  while (Math.abs(n)>=1024 && index<units.length-1) { n/=1024; index++; }
  return (index ? n.toFixed(1) : String(Math.round(n)))+" "+units[index];
}
function duration(ms) {
  if (ms===null || ms===undefined || !isFinite(Number(ms))) return "\u2014";
  var seconds=Math.max(0,Math.round(Number(ms)/1000));
  if (seconds<60) return seconds+"s";
  if (seconds<3600) return Math.round(seconds/60)+"m";
  return (seconds/3600).toFixed(1)+"h";
}
function signed(n) { return n===undefined || n===null ? "\u2014" : (n>0?"+":"")+n; }
function time(at) { return at ? new Date(at).toLocaleTimeString() : "\u2014"; }
function filterRows(rows, query) {
  var needle=String(query || "").toLowerCase().slice(0,120);
  return rows.filter(function(r) { return [r.name,r.node,r.label,r.title,r.summary].join(" ").toLowerCase().indexOf(needle)>=0; });
}
function stackFrame(f) { return f ? f.module+"."+f.function+"/"+f.arity+(f.line?" :"+f.line:"") : "unavailable"; }
function processText(p) {
  var lines=["Captured: "+time(p.at_ms),String(p.pid || "" )+"  "+String(p.registered_name || "unregistered"), "Status: "+String(p.status || "unavailable"),
    "Mailbox: "+String(p.mailbox===undefined?"unavailable":p.mailbox)+"   Memory: "+bytes(p.memory_bytes)+"   Reductions: "+String(p.reductions || 0),
    "Current: "+stackFrame(p.current_function),"Initial: "+stackFrame(p.initial_call),"","STACK (no arguments)"];
  (p.stack || []).forEach(function(f,i) { lines.push(String(i+1)+"  "+stackFrame(f)); });
  if (!(p.stack || []).length) lines.push("No stack available.");
  lines.push("","FOCUSED ANCESTRY");
  (p.ancestry || []).forEach(function(a) { lines.push(String(a.name || a.pid || "unavailable")+"  "+String(a.pid || "")+(a.child ? "  "+String(a.child.type || a.child.status || "") : "")); });
  if (!(p.ancestry || []).length) lines.push("No ancestry available.");
  var b=p.binaries || {};
  lines.push("","OFF-HEAP BINARY REFERENCES", String(b.status || "unavailable")+(b.partial?" (partial)":""),
    "Observed bytes: "+bytes(b.referenced_bytes)+"  Entries: "+String(b.sampled_entries || 0)+" / "+String(b.total_entries || 0));
  (b.top || []).forEach(function(r) { lines.push(bytes(r.bytes)+"  references: "+r.references); });
  lines.push("Shared references are not exclusive process ownership.");
  (p.warnings || []).forEach(function(w) { lines.push("Notice: "+w); });
  return lines.join("\n");
}
function diffText(diff) {
  var lines=["Frame comparison  "+time(diff.from_at_ms)+" -> "+time(diff.to_at_ms),""];
  Object.keys(diff.summary_delta || {}).forEach(function(k) { lines.push(k+": "+signed(diff.summary_delta[k])); });
  (diff.nodes || []).forEach(function(n) {
    lines.push("",n.node+"  "+n.change);
    Object.keys(n.delta || {}).forEach(function(k) { lines.push("  "+k+": "+signed(n.delta[k])); });
    Object.keys(n.memory_delta || {}).forEach(function(k) { lines.push("  "+k+" memory delta: "+bytes(n.memory_delta[k])); });
    (n.restart_churn_delta || []).forEach(function(c) { lines.push("  "+c.name+" churn delta: "+signed(c.delta)); });
    lines.push(n.hot_set_comparable?"  Hot entered: "+(n.hot_entered || []).join(", ")+" | left: "+(n.hot_left || []).join(", "):"  Hot-set comparison unavailable (no comparable deep samples).");
  });
  lines.push("","New alerts: "+(diff.new_alerts || []).join(", "),"Resolved alerts: "+(diff.resolved_alerts || []).join(", "));
  return lines.join("\n");
}

function panelShortcut(text) {
  var key=String(text || "").toLowerCase();
  var actions={c:"cockpit",i:"investigate",r:"refresh",g:"live","?":"help"};
  return actions[key] || null;
}
function investigationTabShortcut(text) {
  var key=String(text || "").toLowerCase();
  var tabs={t:"triage",f:"recorder",p:"process",e:"ets",w:"pins",b:"budget"};
  return tabs[key] || null;
}


function recorderIndexById(timeline, id) {
  var rows=timeline || [];
  for (var i=0;i<rows.length;i++) if (String(rows[i].frame_id || "")===String(id || "")) return i;
  return -1;
}
function recorderFrameAtFraction(timeline, fraction) {
  var rows=timeline || [];
  if (!rows.length) return "";
  var f=Math.max(0,Math.min(1,Number(fraction || 0)));
  var index=rows.length===1 ? 0 : Math.round(f*(rows.length-1));
  return String(rows[index].frame_id || "");
}
function recorderOrderedRange(timeline, a, b) {
  var ai=recorderIndexById(timeline,a), bi=recorderIndexById(timeline,b);
  if (ai<0 || bi<0) return {from:"",to:"",from_index:-1,to_index:-1};
  if (ai<=bi) return {from:String(a),to:String(b),from_index:ai,to_index:bi};
  return {from:String(b),to:String(a),from_index:bi,to_index:ai};
}
function recorderRangeAll(timeline) {
  var rows=timeline || [];
  if (!rows.length) return {from:"",to:""};
  return {from:String(rows[0].frame_id || ""),to:String(rows[rows.length-1].frame_id || "")};
}
function recorderRangeLast(timeline, spanMs) {
  var rows=timeline || [];
  if (!rows.length) return {from:"",to:""};
  var target=Math.max(0,Number(spanMs || 0));
  var end=rows.length-1, start=end, elapsed=0;
  for (var i=end;i>0 && elapsed<target;i--) {
    var delta=Number(rows[i].at_ms || 0)-Number(rows[i-1].at_ms || 0);
    if (delta>0) elapsed+=delta;
    start=i-1;
  }
  return {from:String(rows[start].frame_id || ""),to:String(rows[end].frame_id || "")};
}
function recorderSelectionSpanMs(timeline, from, to) {
  var ordered=recorderOrderedRange(timeline,from,to);
  if (ordered.from_index<0) return 0;
  var rows=timeline || [], elapsed=0;
  for (var i=ordered.from_index+1;i<=ordered.to_index;i++) {
    var delta=Number(rows[i].at_ms || 0)-Number(rows[i-1].at_ms || 0);
    if (delta>0) elapsed+=delta;
  }
  return elapsed;
}
function recorderCapturedSpanMs(timeline) {
  var rows=timeline || [];
  if (rows.length<2) return 0;
  return recorderSelectionSpanMs(rows,rows[0].frame_id,rows[rows.length-1].frame_id);
}
