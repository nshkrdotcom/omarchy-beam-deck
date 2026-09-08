import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const file = new URL('../qml/DeckState.js', import.meta.url);
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(file, 'utf8').replace(/^\.pragma library\s*/, ''), context);
const S = context;
const plain = x => JSON.parse(JSON.stringify(x));

test('safe defaults cover every optional 1.1 collection', () => {
  const s = S.emptySnapshot();
  for (const key of ['incidents', 'forecasts', 'crash_triage']) assert.deepEqual(plain(s[key]), []);
  assert.equal(s.flight_recorder.frame_count, 0);
  assert.equal(s.budget_trial, null);
});
test('job updates are immutable and terminal results cannot regress', () => {
  const input = { x: { request_id: 'x', kind: 'inspect_process', status: 'queued', updated_at: 1 } };
  const running = S.acceptJob(input, { request_id: 'x', kind: 'inspect_process', status: 'started' }, 2);
  assert.equal(input.x.status, 'queued');
  const done = S.acceptJob(running, { request_id: 'x', kind: 'inspect_process', status: 'complete', result: { pid: '<0.1.0>' } }, 3);
  assert.equal(S.acceptJob(done, { request_id: 'x', status: 'started' }, 4).x.status, 'complete');
});
test('request identity, kind and node protect a newly selected target', () => {
  const jobs = { old: { request_id: 'old', kind: 'inspect_process', node: 'a@host', status: 'complete' } };
  assert.equal(S.jobFor(jobs, 'new', 'inspect_process', 'b@host'), null);
  assert.equal(S.jobFor(jobs, 'old', 'inspect_ets', 'a@host'), null);
  assert.equal(S.jobFor(jobs, 'old', 'inspect_process', 'b@host'), null);
});
test('job history is count and age bounded', () => {
  const jobs = {};
  for (let i=0; i<100; i++) jobs['j'+i] = {request_id:'j'+i, status:'complete', updated_at:i};
  assert.equal(Object.keys(S.pruneJobs(jobs, 100)).length, 32);
  assert.equal(Object.keys(S.pruneJobs(jobs, 200000)).length, 0);
});
test('historical, disconnected and stale snapshots cannot mutate', () => {
  const s = {at_ms:10000, nodes:[{name:'n', attached:true}]};
  assert.equal(S.canMutate(s, false, true, 12000, 'n'), true);
  assert.equal(S.canMutate(s, true, true, 12000, 'n'), false);
  assert.equal(S.canMutate(s, false, false, 12000, 'n'), false);
  assert.equal(S.canMutate(s, false, true, 50000, 'n'), false);
  assert.equal(S.canMutate(s, false, true, 12000, 'missing'), false);
});
test('notification content remains data in fixed argv', () => {
  const args = plain(S.notificationArgs({urgency:'critical', title:'$(touch /tmp/pwn)', body:'; rm -rf /'}));
  assert.deepEqual(args, ['omarchy-notification-send', '-u', 'critical', '$(touch /tmp/pwn)', '; rm -rf /']);
  assert.equal(S.notificationArgs({urgency:'--help', title:'x', body:'x'})[2], 'normal');
});
test('formatters do not invent zeros for missing data', () => {
  assert.equal(S.bytes(null), '\u2014');
  assert.equal(S.duration(null), '\u2014');
  assert.equal(S.duration(60000), '1m');
  assert.equal(S.signed(-3), '-3');
  assert.equal(S.bytes(1048576), '1.0 MiB');
});
test('returning live invalidates late historical results', () => {
  assert.equal(S.jobFor({x:{kind:'recorder_frame',status:'complete'}}, '', 'recorder_frame'), null);
});
test('search works for node, name and label without mutating input', () => {
  const input=[{node:'api@host',label:'Orders'},{node:'worker@host',name:'Billing'}];
  assert.equal(S.filterRows(input,'billing').length,1);
  assert.equal(input.length,2);
});
test('process reports never stringify unrecognized payload fields', () => {
  const text = S.processText({pid:'<0.1.0>',status:'waiting',messages:['SECRET'],process_state:'SECRET',stack:[]});
  assert.equal(text.includes('SECRET'), false);
  assert.equal(text.includes('<0.1.0>'), true);
});
test('frame diff explicitly labels noncomparable hot sets', () => {
  assert.match(S.diffText({summary_delta:{beam_rss_bytes:42},nodes:[{node:'n',change:'retained',hot_set_comparable:false}]}), /unavailable/);
});
test('canceling the panel preserves noninteractive export jobs', () => {
  const jobs={a:{status:'started',kind:'inspect_process'},b:{status:'started',kind:'export_bundle'}};
  const canceled=S.cancelInteractive(jobs,10);
  assert.equal(canceled.a.status,'canceled');
  assert.equal(canceled.b.status,'started');
});
test('process actions require a fresh captured report from the same VM incarnation', () => {
  const s = {at_ms:10000,nodes:[{name:'a@host',attached:true,creation:8}]};
  const p = {node:'a@host',at_ms:9000,creation:8,pid:'<0.7.0>'};
  assert.equal(S.canActOnProcess(s,p,false,true,12000),true);
  assert.equal(S.canActOnProcess(s,{...p,creation:7},false,true,12000),false);
  assert.equal(S.canActOnProcess(s,p,true,true,12000),false);
  assert.equal(S.canActOnProcess(s,p,false,true,25000),false);
  assert.equal(S.canActOnProcess(s,null,false,true,12000),false);
});

test('panel keyboard shortcuts reserve Omarchy navigation keys and use stable mnemonics', () => {
  assert.equal(S.panelShortcut('c'), 'cockpit');
  assert.equal(S.panelShortcut('I'), 'investigate');
  assert.equal(S.panelShortcut('r'), 'refresh');
  assert.equal(S.panelShortcut('g'), 'live');
  assert.equal(S.panelShortcut('?'), 'help');
  for (const reserved of ['h', 'j', 'k', 'l', 'x']) assert.equal(S.panelShortcut(reserved), null);
});

test('investigation keyboard shortcuts map each workspace without colliding with refresh or navigation', () => {
  assert.equal(S.investigationTabShortcut('t'), 'triage');
  assert.equal(S.investigationTabShortcut('f'), 'recorder');
  assert.equal(S.investigationTabShortcut('p'), 'process');
  assert.equal(S.investigationTabShortcut('e'), 'ets');
  assert.equal(S.investigationTabShortcut('w'), 'pins');
  assert.equal(S.investigationTabShortcut('b'), 'budget');
  for (const reserved of ['r', 'g', 'h', 'j', 'k', 'l', 'x']) assert.equal(S.investigationTabShortcut(reserved), null);
});


test('recorder range navigation is sequence ordered and never depends on wall-clock ordering', () => {
  const timeline = [
    {frame_id:'frame-10', at_ms:10000, beam_rss_bytes:10},
    {frame_id:'frame-11', at_ms:12000, beam_rss_bytes:11},
    {frame_id:'frame-12', at_ms:9000, beam_rss_bytes:12}, // wall clock moved backward
    {frame_id:'frame-13', at_ms:11000, beam_rss_bytes:13}
  ];

  assert.equal(S.recorderFrameAtFraction(timeline, 0), 'frame-10');
  assert.equal(S.recorderFrameAtFraction(timeline, 1), 'frame-13');
  assert.equal(S.recorderFrameAtFraction(timeline, 0.66), 'frame-12');

  assert.deepEqual(
    plain(S.recorderOrderedRange(timeline, 'frame-13', 'frame-11')),
    {from:'frame-11', to:'frame-13', from_index:1, to_index:3}
  );
});

test('recorder presets and selected duration use retained sequence without inventing negative time', () => {
  const timeline = Array.from({length: 40}, (_, i) => ({
    frame_id: `f${i}`,
    at_ms: 100000 + i * 2000,
    beam_rss_bytes: 1000 + i
  }));

  assert.deepEqual(plain(S.recorderRangeAll(timeline)), {from:'f0',to:'f39'});
  assert.deepEqual(plain(S.recorderRangeLast(timeline, 60000)), {from:'f9',to:'f39'});
  assert.equal(S.recorderSelectionSpanMs(timeline, 'f9', 'f39'), 60000);
  assert.equal(S.recorderCapturedSpanMs(timeline), 78000);

  const clockRegression = [
    {frame_id:'a',at_ms:10000},
    {frame_id:'b',at_ms:12000},
    {frame_id:'c',at_ms:7000},
    {frame_id:'d',at_ms:9000}
  ];
  assert.equal(S.recorderSelectionSpanMs(clockRegression, 'a', 'd'), 4000);
});

test('recorder metric series preserves measured positions, gaps, restarts and unknown values', () => {
  const rows=[
    {frame_id:'a',at_ms:5000,sample_mono_ms:1000,nodes:[{name:'n',attached:true,creation:1,run_queue:5}]},
    {frame_id:'b',at_ms:6000,sample_mono_ms:2000,nodes:[{name:'n',attached:false,creation:1}]},
    {frame_id:'c',at_ms:4000,sample_mono_ms:5000,nodes:[{name:'n',attached:true,creation:2,run_queue:0}]}
  ];
  const s=S.recorderSeries(rows,'run_queue','n');
  assert.deepEqual(plain(s.points.map(p=>p.x)),[0,0.25,1]);
  assert.deepEqual(plain(s.points.map(p=>p.value)),[5,null,0]);
  assert.equal(s.points[2].breakBefore,true);
  assert.equal(s.unit,'tasks');
  assert.equal(S.recorderSeries([{frame_id:'z',beam_rss_bytes:Infinity}],'rss','').points[0].value,null);
});

test('baseline retains exact frame/session identity and never rebounds on expiry', () => {
  const b=S.captureBaseline({session_id:'one',flight_recorder:{timeline:[{frame_id:'f1',at_ms:1000}],newest_frame_id:'f1'}},'n');
  assert.equal(b.frame_id,'f1');assert.equal(b.node,'n');
  assert.equal(S.baselineStatus(b,{session_id:'one',flight_recorder:{timeline:[{frame_id:'f2'}]}}),'expired');
  assert.equal(S.baselineStatus(b,{session_id:'two'}),'helper_restarted');
});

test('activity filters allow opened plus closed and restart-focused views without changing rows', () => {
  const rows=[{id:'a',node:'a',domain:'node',kind:'discovered'},{id:'b',node:'a',domain:'node',kind:'unreachable'},{id:'c',node:'b',domain:'process',kind:'registered_replaced'}];
  assert.deepEqual(plain(S.activityRows(rows,'a','all','connections','').map(r=>r.id)),['a','b']);
  assert.deepEqual(plain(S.activityRows(rows,'','all','restarts','').map(r=>r.id)),['c']);
  assert.equal(rows.length,3);
});

test('signed comparison uses bytes and percentage points, and rejects unknown payload keys', () => {
  const text=S.diffText({summary_delta:{beam_rss_bytes:1024,secret_payload:42},nodes:[{node:'n',change:'retained',utilization_delta_pp:12.5,occupancy_delta_pp:{processes:-2},memory_delta:{binary:1024},delta:{run_queue:-3}}]});
  assert.match(text,/\+1.0 KiB/);assert.match(text,/\+12.5 pp/);assert.doesNotMatch(text,/secret_payload/);
  assert.equal(S.signed(NaN),'—');
});

test("provider briefing labels absent and stale acquisition instead of healthy zeros", () => {
  assert.match(S.providerText({},false,20000),/unavailable/i);
  assert.match(S.providerText({at_ms:1000,collection:{poll_interval_ms:2000,status:"partial"},nodes:[{attached:false}]},true,20000),/stale/i);
  assert.match(S.providerText({at_ms:19000,collection:{duration_ms:42,poll_interval_ms:2000,status:"complete"},nodes:[{attached:true}]},true,20000),/42 ms/);
});
test("baseline records node incarnation and measured monotonic spans survive wall-clock reversal", () => {
  const s={session_id:"s",flight_recorder:{newest_frame_id:"frame-2",timeline:[{frame_id:"frame-2",at_ms:20,nodes:[{name:"fixture",creation:4,attached:true}],collection:{status:"complete"}}]}};
  assert.equal(S.captureBaseline(s,"fixture").creation,4);
  const rows=[{frame_id:"a",at_ms:10000,sample_mono_ms:0},{frame_id:"b",at_ms:5000,sample_mono_ms:1000},{frame_id:"c",at_ms:1000,sample_mono_ms:3000}];
  assert.equal(S.recorderCapturedSpanMs(rows),3000);
  assert.equal(S.recorderRangeLast(rows,1500).from,"b");
});
test("scan labels stay compact and missing counters stay unavailable", () => {
  assert.match(S.time(1000),/^\d{2}:\d{2}:\d{2}$/);
  assert.match(S.processText({pid:"<0.1.0>"}),/Reductions: unavailable/);
  assert.equal(S.filterRows([{name:"table",owner:"<0.2.0>"}],"<0.2.0>").length,1);
});
test("captured hot-set sorting is stable, bounded and keeps unknown measurements last", () => {
  const rows=[{pid:"<0.2.0>",mailbox:4},{pid:"<0.1.0>",mailbox:4},{pid:"<0.3.0>",mailbox:null}];
  assert.deepEqual(plain(S.rankedProcesses(rows,"","mailbox")).map(r=>r.pid),["<0.1.0>","<0.2.0>","<0.3.0>"]);
  assert.equal(S.rankedProcesses(rows,"<0.2.0>","mailbox").length,1);
  assert.equal(S.rankedProcesses(Array.from({length:40},(_,i)=>({pid:String(i)})),"","mailbox").length,24);
});

test("small measured chart ranges retain distinct labels and full plotted precision", () => {
  assert.match(S.metricScale(60*1048576,60*1048576+4096,"bytes"),/60.000 MiB.*60.004 MiB.*4.0 KiB/);
  assert.equal(S.metricY(.3,.2,.3,10,122),10);
  assert.equal(S.metricY(.2,.2,.3,10,122),122);
  assert.equal(S.metricY(null,.2,.3,10,122),null);
  assert.equal(S.metricY(7,7,7,10,122),66);
});

test("action receipts describe requests without serializing internal payloads or claiming current probe state", () => {
  const text=S.actionReceipt({action:"deep_events",result:{enabled:true,secret:"PRIVATE_ACTION_CANARY"}});
  assert.match(text,/start accepted/);assert.match(text,/current probe state/);assert.doesNotMatch(text,/PRIVATE_ACTION_CANARY|enabled/);
  assert.equal(S.actionReceipt({action:"watchlist",result:{saved:true}}),"Watchlist saved.");
});

test("interval reports rank measured changes, preserve unavailable units and reject arbitrary fields", () => {
  const report={kind:"process_window",node:"fixture@host",creation:1,from_at_ms:1000,at_ms:2000,span_ms:1000,matched:2,first_only:0,last_only:0,first_scanned:2,last_scanned:2,omitted_rows:0,rows:[
    {key:"a",pid:"<0.1.0>",name:"one",status:"matched",reductions_per_second:null,memory_delta_bytes:-1024,mailbox_delta:null,secret:"REPORT_CANARY"},
    {key:"b",pid:"<0.2.0>",name:"two",status:"matched",reductions_per_second:20,memory_delta_bytes:2048,mailbox_delta:1}]};
  assert.equal(S.intervalRows(report,"","reductions_per_second")[0].pid,"<0.2.0>");
  assert.equal(S.intervalRows(report,"one","memory_delta_bytes").length,1);
  const text=S.intervalText(report);assert.match(text,/20 reductions\/s/);assert.match(text,/-1.0 KiB/);assert.match(text,/unavailable/);assert.doesNotMatch(text,/REPORT_CANARY/);
  assert.equal(S.stackFraction({count:5},{samples:20}),.25);
  assert.equal(S.stackFraction({count:30},{samples:20}),1);
  assert.equal(S.stackFraction({count:NaN},{samples:0}),0);
});

test("panel close cancels interval jobs and refuses late success", () => {
  let jobs={};for(const kind of ["process_window","ets_window","sample_process"]) jobs=S.acceptJob(jobs,{request_id:kind,kind,status:"started"},100);
  jobs=S.cancelInteractive(jobs,200);
  assert.ok(Object.values(jobs).every(j=>j.status==="canceled"));
  jobs=S.acceptJob(jobs,{request_id:"sample_process",kind:"sample_process",status:"complete",result:{secret:"LATE"}},300);
  assert.equal(jobs.sample_process.status,"canceled");assert.equal(jobs.sample_process.result,undefined);
});

test('helper path comes from the component URL without private host manifest fields', () => {
  assert.equal(S.localFilePath('file:///tmp/BEAM%20Deck/bin/beam-deckd'), '/tmp/BEAM Deck/bin/beam-deckd');
  assert.equal(S.localFilePath('https://example.invalid/helper'), '');
  assert.equal(S.localFilePath('file:///tmp/%ZZ'), '');
});
