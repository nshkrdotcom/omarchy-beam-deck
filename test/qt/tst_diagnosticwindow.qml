import QtQuick
import QtTest
import qs.Commons
import "../../qml" as Deck
TestCase {
  id:suite; visible:true; name:"IntervalDiagnostics"; when:windowShown
  width:900; height:1400
  Component { id:factory; Deck.DiagnosticWindow { width:800; canStart:true; canInspect:true } }
  function all(item) { var out=[item];for(var i=0;i<item.children.length;i++)out=out.concat(all(item.children[i]));return out }
  function report(rows) { return {kind:"process_window",node:"fixture@host",creation:1,from_at_ms:1000,at_ms:2000,span_ms:1000,partial:false,first_scanned:rows.length,last_scanned:rows.length,matched:rows.length,first_only:0,last_only:0,omitted_rows:0,rows:rows} }
  function test_large_survey_pages_and_local_filter() {
    failOnWarning(/TypeError|ReferenceError/)
    var rows=[];for(var i=0;i<60;i++)rows.push({key:String(i),pid:"<0."+(i+1)+".0>",name:"worker-"+i,status:"matched",memory_delta_bytes:i,reductions_per_second:i,mailbox_delta:i})
    var card=createTemporaryObject(factory,suite,{job:{status:"complete",result:report(rows)}});wait(20)
    compare(all(card).filter(function(x){return x.text==="Inspect PID" && x.clicked}).length,5,"five measured rows per page")
    var next=all(card).filter(function(x){return x.text==="Next rows" && x.clicked})[0];verify(next);next.clicked();wait(10)
    compare(card.page,1)
    var field=all(card).filter(function(x){return x.placeholderText==="Filter measured names or PIDs"})[0]
    field.forceActiveFocus();"worker-59".split("").forEach(function(c){keyClick(c)})
    compare(card.page,0);compare(all(card).filter(function(x){return x.text==="Inspect PID" && x.clicked}).length,1)
  }
  function test_stack_frequency_uses_all_sample_count_and_expands_real_frames() {
    failOnWarning(/TypeError|ReferenceError/)
    var result={kind:"sample_process",node:"fixture@host",pid:"<0.1.0>",creation:1,from_at_ms:1000,at_ms:2000,span_ms:1000,samples:20,requested_samples:20,missed_samples:0,partial:false,statuses:[{status:"waiting",count:20}],stacks:[{key:"s",count:5,frames:[{module:"fixture",function:"loop",arity:0},{module:"gen_server",function:"loop",arity:7}]}]}
    var card=createTemporaryObject(factory,suite,{width:440,kind:"sample_process",job:{status:"complete",result:result}});wait(20)
    var bar=all(card).filter(function(x){return x.objectName==="stackFrequencyBar"})[0];verify(bar)
    fuzzyCompare(bar.width/bar.parent.width,.25,.001)
    var show=all(card).filter(function(x){return x.text==="Show stack" && x.clicked})[0];verify(show);show.clicked();wait(10)
    verify(all(card).some(function(x){return x.visible && x.text==="fixture.loop/0\ngen_server.loop/7"}))
  }
}
