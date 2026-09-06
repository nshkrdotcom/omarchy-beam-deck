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
