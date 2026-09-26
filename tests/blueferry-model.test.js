const assert = require("node:assert/strict")
const model = require("../BlueFerryModel.js")
const data = {version:1,ok:true,operation:"status",endpoint:model.endpoint(),backendOwner:":1.20",apiVersion:2,
  connection:"ready",storage:"ready",storagePolicy:"encrypted",backendRelease:"1.2.3-1",map:true,pbap:true,ancs:false,
  canReadHistory:true,history:{coverage:"observed-only",truncated:true},items:[]}
function parse(value=data,operation=value.operation,owner=operation==="status"?"":":1.20") {
  return model.result({ok:true,data:value,exitCode:0},operation,owner)
}
assert.equal(parse().canReadHistory,true)
assert.deepEqual(model.endpoint(),{provider:"blueferry",instanceId:"local",deviceId:"local-history",accountId:null})
assert.equal(parse({...data,connection:"offline"}).canReadHistory,true,"retained history remains readable offline")
for (const storage of ["locked","disabled","error","unknown"]) {
  const value={...data,storage,canReadHistory:false}
  assert.equal(parse(value).canReadHistory,false)
  assert.equal(parse({...value,canReadHistory:true}).ok,false,"unreadable storage must not authorize reads")
}
for (const value of [null,[],{}, {...data,version:2},{...data,apiVersion:"2"},{...data,apiVersion:1},
  {...data,endpoint:{...data.endpoint,deviceId:"some-phone"}},{...data,backendOwner:"io.weirdware.BlueFerry"},
  {...data,map:1},{...data,canReadHistory:"true"},{...data,history:{coverage:"full",truncated:false}},
  {...data,backendRelease:"<b>untrusted</b>"},{...data,storage:"unexpected"},{...data,items:[{}]}])
  assert.equal(parse(value,"status").ok,false)
assert.equal(parse({...data,operation:"threads"},"threads",":1.19").code,"backend_changed")
assert.equal(parse({...data,operation:"threads"},"threads","").ok,false)
const thread={threadId:'group:雪/📱["opaque"]',names:["Family"],addresses:["alice@example.test"],preview:"Hello",
  timestamp:1,unread:true,incoming:true,isGroup:true,messagesTruncated:true,attachments:[],attachmentCount:0}
const threads={...data,operation:"threads",items:[thread]}
assert.deepEqual(parse(threads).items,[thread])
assert.equal(parse({...threads,items:[thread,thread]}).ok,false,"duplicate thread IDs rejected")
const nearLimit={...thread,threadId:"📱".repeat(1024)}
assert.equal(parse({...threads,items:[nearLimit]}).ok,true,"bounds count Unicode points like the helper")
for (const bad of [{...thread,threadId:"x".repeat(1025)},{...thread,threadId:"__proto__",names:"bad"},
  {...thread,names:["a","b"]},{...thread,names:["雪".repeat(86)]},{...thread,addresses:["a".repeat(321)]},
  {...thread,timestamp:-1},{...thread,timestamp:1.2},{...thread,incoming:1},{...thread,messagesTruncated:undefined},
  {...thread,preview:"😀".repeat(2049)},{...thread,threadId:"\ud800"},{...thread,attachmentCount:1}])
  assert.equal(parse({...threads,items:[bad]}).ok,false)
const message={body:"  Unicode 😀\n<b>plain text</b>  ",timestamp:2,incoming:true,sender:"Alice",bodyTruncated:true,attachments:[],attachmentCount:0}
const messages={...data,operation:"messages",items:[message]}
assert.deepEqual(parse(messages).items,[message])
for (const bad of [{...message,body:"x\u0000"},{...message,body:"\ud800"},{...message,body:"😀".repeat(2049)},
  {...message,sender:"x".repeat(257)},{...message,bodyTruncated:undefined},{...message,attachments:["file:///secret"]}])
  assert.equal(parse({...messages,items:[bad]}).ok,false)
const contacts={...data,operation:"contacts",items:[{name:"Alice",number:"alice@example.test"}]}
assert.equal(parse(contacts).items[0].number,"alice@example.test")
assert.equal(parse({...contacts,items:[{name:"Alice",number:""}]}).ok,false)
assert.equal(parse({...contacts,items:Array(201).fill(contacts.items[0])}).ok,false)
for (const code of ["backend_unavailable","storage_unavailable","rate_limited","thread_unavailable"])
  assert.equal(model.result({ok:true,exitCode:1,data:{version:1,ok:false,operation:"threads",code}},"threads",":1.20").code,code)
assert.equal(model.result({ok:false,code:"request_timeout",text:"backend-private"},"status","").code,"request_timeout")
assert.equal(model.result({ok:true,exitCode:1,data:{version:1,ok:false,operation:"messages",code:"read_failed"}},"threads",":1.20").code,"invalid_response")
assert.equal(model.result({ok:true,exitCode:1,data:{version:1,ok:false,operation:"status",code:"<script>private"}},"status","").code,"invalid_response")
assert.equal(model.result({ok:true,exitCode:1,data},"status","").ok,false)
assert.equal(model.errorText("__proto__"),model.errorText("invalid_response"))
const clean=parse({...threads,body:"secret",items:[{...thread,private:"secret"}]})
assert.equal(JSON.stringify(clean).includes("secret"),false)
clean.items[0].names[0]="Changed"
assert.equal(thread.names[0],"Family")
console.log("BlueFerry model tests passed")
