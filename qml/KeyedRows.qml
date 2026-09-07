import QtQuick

// Keep delegate objects, focus and selection when the same evidence is refreshed.
ListModel {
  id: root
  property var rows: []
  property string keyField: "id"
  property int limit: 200
  onRowsChanged: reconcile()
  onKeyFieldChanged: reconcile()
  onLimitChanged: reconcile()
  function reconcile() {
    var seen = {}, next = []
    ;(rows || []).slice(0, limit).forEach(function(row) {
      var key = String(row[root.keyField] || "")
      if (!key || seen[key]) return
      seen[key] = true
      next.push({rowKey:key, rowJson:JSON.stringify(row)})
    })
    for (var i = 0; i < next.length; i++) {
      var found = -1
      for (var j = i; j < count; j++) if (get(j).rowKey === next[i].rowKey) { found = j; break }
      if (found < 0) insert(i, next[i])
      else {
        if (found !== i) move(found, i, 1)
        if (get(i).rowJson !== next[i].rowJson) setProperty(i, "rowJson", next[i].rowJson)
      }
    }
    if (count > next.length) remove(next.length, count - next.length)
  }
}
