// Local send observation only. KDE Connect command acceptance is not delivery.
// Keep this module usable by both QML and the pure Node tests.
function copy(value) { return Object.assign({}, value) }

function address(value) { return String(value || "").replace(/[+().\s-]/g, "") }

function exactConversation(conversations, number) {
  var matches = (conversations || []).filter(function(item) {
    return item && item.threadId !== null && item.threadId !== undefined
      && Array.isArray(item.addresses) && item.addresses.length === 1
      && address(item.addresses[0]) === address(number)
  })
  return matches.length === 1 ? matches[0] : null
}

function historyOnly(rows) {
  return (rows || []).filter(function(row) { return row && !row.localSend })
}

function fingerprint(row) {
  return JSON.stringify([Number(row.timestamp), String(row.body || ""), row.incoming === false])
}

function create(id, deviceId, conversation, number, body, now, baseline) {
  return {
    id: id, deviceId: deviceId,
    threadId: conversation && conversation.threadId !== null
      && conversation.threadId !== undefined ? String(conversation.threadId) : "",
    conversation: conversation ? copy(conversation) : null,
    number: String(number || ""), body: String(body), timestamp: now,
    state: "submitting", attempts: 0, deadline: 0, confirmationKey: "",
    baselineKnown: Array.isArray(baseline),
    baseline: historyOnly(baseline).filter(function(row) {
      return row.incoming === false && String(row.body || "") === String(body)
    }).map(function(row) { return Number(row.timestamp) })
  }
}

function finish(operation, exitCode, now, timeoutMs) {
  var result = copy(operation)
  // A lost response or nonzero helper exit cannot prove the phone did not send.
  result.state = exitCode === 0 ? "accepted" : "unconfirmed"
  result.deadline = now + timeoutMs
  return result
}

function expire(operations, now) {
  return operations.map(function(operation) {
    if (operation.state !== "accepted" || now < operation.deadline) return operation
    var result = copy(operation)
    result.state = "unconfirmed"
    return result
  })
}

function bindThreads(operations, conversations) {
  return operations.map(function(operation) {
    if (operation.threadId !== "") return operation
    var conversation = exactConversation(conversations, operation.number)
    if (!conversation) return operation
    var result = copy(operation)
    result.threadId = String(conversation.threadId)
    result.conversation = copy(conversation)
    return result
  })
}

function reconcile(operations, deviceId, threadId, history, now) {
  if (now === undefined) now = Date.now()
  var claimed = {}
  operations.forEach(function(operation) {
    if (operation.deviceId === deviceId && operation.threadId === String(threadId)
        && operation.confirmationKey) claimed[operation.confirmationKey] = true
  })
  return operations.map(function(operation) {
    if (operation.deviceId !== deviceId || operation.threadId !== String(threadId)
        || !operation.baselineKnown
        || (operation.state !== "accepted" && operation.state !== "unconfirmed")) return operation
    var match = historyOnly(history).find(function(row) {
      var key = fingerprint(row)
      return row.incoming === false && String(row.body || "") === operation.body
        && Number(row.timestamp) >= operation.timestamp && Number(row.timestamp) <= now && !claimed[key]
        && operation.baseline.indexOf(Number(row.timestamp)) === -1
    })
    if (!match) return operation
    var result = copy(operation)
    result.state = "confirmed-in-history"
    result.confirmationKey = fingerprint(match)
    claimed[result.confirmationKey] = true
    return result
  })
}

function pruneConfirmed(operations, now) {
  if (now === undefined) now = Date.now()
  return operations.filter(function(operation) {
    if (operation.state !== "confirmed-in-history") return true
    var stamp = JSON.parse(operation.confirmationKey)[0]
    if (stamp >= now) return true
    // Keep a claimed row while another same-text send could otherwise claim it.
    return operations.some(function(other) {
      return (other.state === "accepted" || other.state === "unconfirmed")
        && other.deviceId === operation.deviceId && other.threadId === operation.threadId
        && other.body === operation.body && other.timestamp <= stamp
    })
  })
}

function belongs(operation, conversation) {
  if (!conversation) return false
  return operation.threadId !== ""
    ? operation.threadId === String(conversation.threadId)
    : operation.id === conversation.localOperationId
}

function updateThreadPreview(conversations, threadId, history) {
  var rows = historyOnly(history)
  if (rows.length === 0) return conversations
  var newest = rows.reduce(function(left, right) {
    return Number(left.timestamp) >= Number(right.timestamp) ? left : right
  })
  return conversations.map(function(conversation) {
    if (String(conversation.threadId) !== String(threadId)
        || Number(conversation.timestamp) > Number(newest.timestamp)) return conversation
    var result = copy(conversation)
    result.preview = String(newest.body || "")
    result.timestamp = Number(newest.timestamp)
    result.incoming = newest.incoming
    return result
  })
}

function messages(history, conversation, operations) {
  var rows = historyOnly(history).map(function(row) {
    var result = copy(row)
    delete result.sendState
    return result
  })
  operations.filter(function(operation) { return belongs(operation, conversation) }).forEach(function(operation) {
    if (operation.state === "confirmed-in-history") {
      for (var i = 0; i < rows.length; i++) {
        if (fingerprint(rows[i]) === operation.confirmationKey) rows[i].sendState = operation.state
      }
      return
    }
    rows.push({body: operation.body, timestamp: operation.timestamp, incoming: false,
      attachmentCount: 0, attachments: [], localSend: true,
      operationId: operation.id, sendState: operation.state})
  })
  return rows.sort(function(left, right) { return Number(left.timestamp) - Number(right.timestamp) })
}

function conversations(history, operations) {
  var rows = (history || []).filter(function(row) { return !row.localOperationId }).map(copy)
  operations.forEach(function(operation) {
    if (operation.state === "confirmed-in-history") return
    var index = rows.findIndex(function(row) { return belongs(operation, row) })
    var row = index >= 0 ? copy(rows[index]) : operation.conversation ? copy(operation.conversation) : {
      threadId: null, addresses: [operation.number], names: [operation.number], unread: false
    }
    if (Number(row.timestamp || 0) > operation.timestamp) return
    row.preview = operation.body
    row.timestamp = operation.timestamp
    row.incoming = false
    row.unread = false
    row.sendState = operation.state
    if (operation.threadId === "") row.localOperationId = operation.id
    if (index >= 0) rows[index] = row
    else rows.push(row)
  })
  return rows.sort(function(left, right) { return Number(right.timestamp) - Number(left.timestamp) })
}

function label(state) {
  if (state === "submitting") return "Submitting…"
  if (state === "accepted") return "Accepted by KDE Connect · checking phone history"
  if (state === "confirmed-in-history") return "Matching message found in phone history · delivery not verified"
  if (state === "failed") return "Not submitted · edit the message to try again"
  if (state === "unconfirmed") return "Unconfirmed · check your phone before sending again"
  return ""
}

if (typeof module !== "undefined") module.exports = {
  address: address, exactConversation: exactConversation, historyOnly: historyOnly,
  fingerprint: fingerprint, create: create, finish: finish, expire: expire,
  bindThreads: bindThreads, reconcile: reconcile, pruneConfirmed: pruneConfirmed, belongs: belongs,
  messages: messages, conversations: conversations, updateThreadPreview: updateThreadPreview, label: label
}
