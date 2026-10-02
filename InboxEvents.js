.pragma library

// One overlay serves all bar instances. Notify each panel in this QML engine
// after a read action completes, without putting phone contents into IPC.
var panels = []

function subscribe(panel) {
  if (panels.indexOf(panel) === -1) panels.push(panel)
}

function unsubscribe(panel) {
  panels = panels.filter(function(item) { return item !== panel })
}

function conversationRead(deviceId, threadId, timestamp) {
  panels.slice().forEach(function(panel) {
    panel.conversationRead(deviceId, threadId, timestamp)
  })
}
