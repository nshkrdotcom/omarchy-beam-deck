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
function signed(n) { return typeof n !== "number" || !isFinite(n) ? "\u2014" : (n>0?"+":"")+Number(n.toFixed(2)); }
function time(at) { if (!at || finite(at)===null) return "—"; var d=new Date(at); return [d.getHours(),d.getMinutes(),d.getSeconds()].map(function(n){return ("0"+n).slice(-2);}).join(":"); }
function filterRows(rows, query) {
  var needle=String(query || "").toLowerCase().slice(0,120);
  return rows.filter(function(r) { return [r.name,r.node,r.label,r.title,r.summary,r.owner,r.owner_name,r.pid,r.kind,r.subject].join(" ").toLowerCase().indexOf(needle)>=0; });
}
function stackFrame(f) { return f ? f.module+"."+f.function+"/"+f.arity+(f.line?" :"+f.line:"") : "unavailable"; }
function processText(p) {
  var lines=["Captured: "+time(p.at_ms),String(p.pid || "" )+"  "+String(p.registered_name || "unregistered"), "Status: "+String(p.status || "unavailable"),
    "Mailbox: "+String(p.mailbox===undefined?"unavailable":p.mailbox)+"   Memory: "+bytes(p.memory_bytes)+"   Reductions: "+(finite(p.reductions)===null?"unavailable":String(p.reductions)),
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
function signedBytes(n) { return finite(n) === null ? "—" : (n>0?"+":"")+bytes(n); }
function diffText(diff) {
  var lines=["Frame comparison  "+time(diff.from_at_ms)+" -> "+time(diff.to_at_ms),
    "Host BEAM RSS: "+signedBytes((diff.summary_delta || {}).beam_rss_bytes)];
  ["process_count","schedulers_online"].forEach(function(k) { lines.push(k+": "+signed((diff.summary_delta || {})[k])); });
  (diff.nodes || []).slice(0,64).forEach(function(n) {
    lines.push("",n.node+"  "+n.change,"  Scheduler utilization: "+signed(n.utilization_delta_pp)+" pp");
    ["processes","atoms","ports","ets","run_queue","schedulers_online"].forEach(function(k) { lines.push("  "+k+": "+signed((n.delta || {})[k])); });
    ["processes","atoms","ports"].forEach(function(k) { lines.push("  "+k+" capacity: "+signed((n.occupancy_delta_pp || {})[k])+" pp"); });
    ["total","binary","ets","processes","code"].forEach(function(k) { lines.push("  "+k+" memory: "+signedBytes((n.memory_delta || {})[k])); });
    lines.push(n.hot_set_comparable ? "  Sampled hot set entered: "+(n.hot_entered || []).join(", ")+" | left: "+(n.hot_left || []).join(", ") : "  Hot-set comparison unavailable (no distinct comparable deep samples).");
    (n.hot_changes || []).slice(0,24).forEach(function(p) { lines.push("  "+p.pid+": "+signed(p.mailbox_delta)+" messages; "+signedBytes(p.memory_delta_bytes)+"; "+signed(p.reductions_per_second)+" reductions/s"); });
  });
  lines.push("", "pp = percentage points. Reductions are work counters, not CPU percentages.", "A changed workload can explain a delta; this comparison does not demonstrate cause.");
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
    var delta=sampleSpan(rows[i-1],rows[i]);
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
    var delta=sampleSpan(rows[i-1],rows[i]);
    if (delta>0) elapsed+=delta;
  }
  return elapsed;
}
function recorderCapturedSpanMs(timeline) {
  var rows=timeline || [];
  if (rows.length<2) return 0;
  return recorderSelectionSpanMs(rows,rows[0].frame_id,rows[rows.length-1].frame_id);
}

function finite(n) { return typeof n === "number" && isFinite(n) ? n : null; }
function captureBaseline(snapshot, node) {
  var recorder=snapshot.flight_recorder || {}, rows=recorder.timeline || [];
  var point=rows.filter(function(r) { return r.frame_id===recorder.newest_frame_id; })[0];
  return point ? {session_id:snapshot.session_id,frame_id:point.frame_id,at_ms:point.at_ms,node:node || "",quality:point.collection || {},creation:((point.nodes || []).filter(function(n){return n.name===node;})[0] || {}).creation} : null;
}
function baselineStatus(b, snapshot) {
  if (!b) return "none";
  if (b.session_id !== snapshot.session_id) return "helper_restarted";
  var r=snapshot.flight_recorder || {}, rows=r.timeline || [];
  if (recorderIndexById(rows,b.frame_id)>=0) return "retained";
  var seq=function(id) { var m=/^frame-(\d+)$/.exec(id || ""); return m ? Number(m[1]) : null; };
  var n=seq(b.frame_id), a=seq(r.oldest_frame_id), z=seq(r.newest_frame_id);
  return n!==null && a!==null && z!==null && n>=a && n<=z ? "retained" : "expired";
}
function activityRows(rows,node,domain,kind,query) {
  var kinds=kind==="connections" ? ["discovered","attached","unreachable","nodeup","nodedown"] : kind==="restarts" ? ["restarted","registered_replaced"] : null;
  return filterRows((rows || []).filter(function(r) { return (!node || r.node===node) && (!domain || domain==="all" || r.domain===domain) && (!kind || kind==="all" || (kinds ? kinds.indexOf(r.kind)>=0 : r.kind===kind)); }),query).slice(0,200);
}
function recorderMetric(metric) {
  var defs={
    rss:{title:"Host BEAM RSS",unit:"bytes",fields:["rss"],labels:["RSS"]},
    memory:{title:"VM memory",unit:"bytes",fields:["total","processes_memory","binary","ets_memory"],labels:["Total","Processes","Binary","ETS"]},
    run_queue:{title:"Run queue",unit:"tasks",fields:["run_queue"],labels:["Runnable tasks"]},
    scheduler_utilization:{title:"Normal scheduler utilization",unit:"%",fields:["scheduler_utilization"],labels:["Normal schedulers"]},
    capacity:{title:"Hard-capacity occupancy",unit:"%",fields:["process_occupancy","atom_occupancy","port_occupancy"],labels:["Processes","Atoms","Ports"]}
  }; return defs[metric] || defs.rss;
}
function metricValue(row,node,key) {
  if (key==="rss") return finite(row.beam_rss_bytes);
  if (!node || node.attached!==true) return null;
  var memory=node.memory || {};
  if (["total","binary"].indexOf(key)>=0) return finite(memory[key]);
  if (key==="processes_memory") return finite(memory.processes);
  if (key==="ets_memory") return finite(memory.ets);
  if (key==="scheduler_utilization") { var u=finite(node[key]); return u!==null && u>=0 && u<=1 ? u*100 : null; }
  var limits={process_occupancy:["processes","process_limit"],atom_occupancy:["atoms","atom_limit"],port_occupancy:["ports","port_limit"]};
  if (limits[key]) { var pair=limits[key], n=finite(node[pair[0]]), d=finite(node[pair[1]]); return n!==null && d!==null && d>0 ? n/d*100 : null; }
  return finite(node[key]);
}
function recorderSeries(timeline,metric,nodeName) {
  var rows=(timeline || []).slice(0,150), def=recorderMetric(metric), mono=rows.every(function(r){return finite(r.sample_mono_ms)!==null;});
  var positions=rows.map(function(r,i){return mono ? r.sample_mono_ms : i;});
  var span=positions.length>1 ? positions[positions.length-1]-positions[0] : 0;
  var nodes=rows.map(function(r){return (r.nodes || []).filter(function(n){return n.name===nodeName;})[0] || null;});
  var traces=def.fields.map(function(key,t) {
    var points=rows.map(function(r,i) {
      var node=nodes[i], previous=nodes[i-1], value=metricValue(r,node,key);
      var gap=i>0 && mono && positions[i]-positions[i-1]>Math.max(10000,Number((r.collection || {}).poll_interval_ms || 2000)*3);
      var restart=metric!=="rss" && i>0 && (!node || !previous || node.creation!==previous.creation || node.attached!==true || previous.attached!==true);
      if (key==="scheduler_utilization" && (!node || !node.hot_processes_at_ms || r.at_ms-node.hot_processes_at_ms>10000)) value=null;
      return {frame_id:r.frame_id,at_ms:r.at_ms,x:span>0?(positions[i]-positions[0])/span:0.5,value:value,breakBefore:gap || restart,gap:gap,restart:restart};
    });
    return {key:key,label:def.labels[t],style:t===0?"solid":t===1?"dashed":t===2?"dotted":"dash-dot",points:points};
  });
  var values=[]; traces.forEach(function(t){t.points.forEach(function(p){if(p.value!==null)values.push(p.value);});});
  return {title:def.title,unit:def.unit,traces:traces,points:traces[0].points,min:values.length?Math.min.apply(null,values):null,max:values.length?Math.max.apply(null,values):null,positionsMeasured:mono};
}
function metricText(value,unit) { return finite(value)===null ? "unavailable" : unit==="bytes" ? bytes(value) : Number(value.toFixed(1))+" "+unit; }

function metricScale(min,max,unit) {
  if(finite(min)===null || finite(max)===null) return "unavailable";
  var span=max-min;
  if(unit==="bytes" && span>0) {
    var units=["B","KiB","MiB","GiB","TiB"], index=0, divisor=1;
    while(Math.abs(max)/divisor>=1024 && index<units.length-1){index++;divisor*=1024;}
    var precision=Math.max(index?1:0,Math.min(6,Math.ceil(-Math.log(span/divisor)/Math.LN10)));
    return (min/divisor).toFixed(precision)+" "+units[index]+" … "+(max/divisor).toFixed(precision)+" "+units[index]+" (span "+bytes(span)+")";
  }
  return metricText(min,unit)+" … "+metricText(max,unit)+(span===0?" (flat)":" (span "+metricText(span,unit)+")");
}
function metricY(value,min,max,top,bottom) {
  if(finite(value)===null || finite(min)===null || finite(max)===null)return null;
  return min===max?(top+bottom)/2:bottom-(value-min)/(max-min)*(bottom-top);
}

function revealFocus(item) {
  var parent = item.parent;
  while (parent) {
    if (typeof parent.contentY === "number" && parent.contentItem && parent.height > 0) {
      var point = item.mapToItem(parent.contentItem, 0, 0);
      var y = parent.contentY;
      if (point.y < y) y = point.y;
      else if (point.y + item.height > y + parent.height) y = point.y + item.height - parent.height;
      parent.contentY = Math.max(0, Math.min(Math.max(0, parent.contentHeight - parent.height), y));
      return;
    }
    parent = parent.parent;
  }
}

function sampleSpan(a,b) {
  if (finite(a.sample_mono_ms)!==null && finite(b.sample_mono_ms)!==null) return Math.max(0,b.sample_mono_ms-a.sample_mono_ms);
  return Math.max(0,Number(b.at_ms || 0)-Number(a.at_ms || 0));
}
function providerText(snapshot,running,now) {
  if (!running || !snapshot.at_ms) return "Provider unavailable. Last valid evidence is retained; check the helper/toolchain and retry Refresh.";
  var c=snapshot.collection || {}, age=Math.max(0,now-snapshot.at_ms), nodes=snapshot.nodes || [];
  var deep=nodes.filter(function(n){return n.attached===true;}).length;
  return (age>10000?"STALE":"CAPTURE")+" / "+duration(age)+" ago / "+(c.status || "quality unknown")
    +" / "+deep+" of "+nodes.length+" nodes authenticated"
    +"\nCollection "+(finite(c.duration_ms)===null?"unavailable":c.duration_ms+" ms")+"; cadence "+duration(c.poll_interval_ms)+"; deep cadence "+duration(c.deep_interval_ms)+"."
    +(deep<nodes.length?" Distribution unavailable: check the node's reachability, naming and cookie source; do not share cookies.":"")
    +(nodes.length===0?" OS discovery alone cannot show OTP internals. A named distributed node and matching trusted credentials are needed.":"");
}

function rankedProcesses(rows,query,sort) {
  var key=["mailbox","memory_bytes","reductions"].indexOf(sort)>=0?sort:"mailbox";
  return filterRows((rows || []).slice(0,24),query).slice().sort(function(a,b){
    var x=finite(a[key]),y=finite(b[key]);
    if(x===null && y!==null)return 1;
    if(y===null && x!==null)return -1;
    if(x!==y)return y-x;
    return String(a.pid).localeCompare(String(b.pid));
  });
}

function actionReceipt(data) {
  var result=data.result || {};
  if(data.action==="deep_events") return result.enabled?"Deep Events start accepted. Check the node for current probe state.":"Deep Events stop accepted. Check provider status for cleanup confirmation.";
  if(data.action==="watchlist") return result.saved?"Watchlist saved.":"Watchlist update received.";
  return "Action response received; inspect the relevant live control for its current state.";
}
