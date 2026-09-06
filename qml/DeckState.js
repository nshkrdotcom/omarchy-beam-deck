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


function recorderOptions(timeline, selectedFrom, selectedTo, bucketMs, maxItems) {
  var rows = timeline || []
  if (!rows.length) return []

  var stride = Math.max(5000, Number(bucketMs || 30000))
  var limit = Math.max(8, Number(maxItems || 20))
  var chosen = {}

  function add(index) {
    if (index >= 0 && index < rows.length)
      chosen[String(index)] = true
  }

  function count() {
    return Object.keys(chosen).length
  }

  function indexFor(id) {
    if (id === undefined || id === null || String(id) === "")
      return -1

    for (var i = 0; i < rows.length; i++)
      if (String(rows[i].frame_id) === String(id))
        return i

    return -1
  }

  function addEvenly(indices, slots) {
    if (slots <= 0 || !indices.length) return

    var available = []
    var seen = {}

    for (var i = 0; i < indices.length; i++) {
      var key = String(indices[i])
      if (chosen[key] || seen[key]) continue
      seen[key] = true
      available.push(indices[i])
    }

    if (!available.length) return

    if (available.length <= slots) {
      for (var j = 0; j < available.length; j++)
        add(available[j])
      return
    }

    if (slots === 1) {
      add(available[Math.floor(available.length / 2)])
      return
    }

    for (var n = 0; n < slots; n++) {
      var pos = Math.round(n * (available.length - 1) / (slots - 1))
      add(available[pos])
    }
  }

  // The actual retained boundaries and explicit user selections are sacred.
  add(0)
  add(rows.length - 1)
  add(indexFor(selectedFrom))
  add(indexFor(selectedTo))

  // Preserve both sides of meaningful alert/event transitions.
  var transitions = []

  for (var i = 1; i < rows.length; i++) {
    var previous = rows[i - 1]
    var current = rows[i]

    if (
      Number(previous.alert_count || 0) !== Number(current.alert_count || 0) ||
      Number(previous.event_count || 0) !== Number(current.event_count || 0)
    ) {
      transitions.push(i - 1)
      transitions.push(i)
    }
  }

  addEvenly(transitions, limit - count())

  // Human navigation is time-based, not sample-count based. Pick one
  // representative frame from each fixed wall-clock bucket.
  var buckets = []
  var previousBucket = null

  for (var j = 0; j < rows.length; j++) {
    var at = Number(rows[j].at_ms || 0)
    var bucket = Math.floor(at / stride)

    if (bucket !== previousBucket) {
      buckets.push(j)
      previousBucket = bucket
    }
  }

  addEvenly(buckets, limit - count())

  var result = []

  for (var k = 0; k < rows.length; k++) {
    if (!chosen[String(k)]) continue

    var frame = rows[k]
    var alerts = Number(frame.alert_count || 0)
    var events = Number(frame.event_count || 0)

    result.push({
      id: frame.frame_id,
      label:
        time(frame.at_ms)
        + "  |  " + alerts + " alert" + (alerts === 1 ? "" : "s")
        + "  |  " + events + " event" + (events === 1 ? "" : "s")
        + "  |  " + bytes(frame.beam_rss_bytes)
    })
  }

  return result
}
