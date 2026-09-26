const assert = require('node:assert/strict')
const model = require('../Model.js')
const capability = {plugin:'kdeconnect_sms', state:'available', supported:true,loaded:true,enabled:true,permission:'granted'}
const rawDevice = {id:'phone1',name:'Private',type:'phone',paired:true,reachable:true,capabilities:{messaging:capability}}
const status = {...model.defaultStatus(),schemaVersion:1,observedAt:1234,installed:true,
  backend:{name:'kdeconnect',available:true,version:'26.08.1',versionSource:'kdeconnect-cli'},devices:[rawDevice]}
let parsed = model.parseStatus(JSON.stringify(status))
assert.equal(parsed.ok, true)
assert.equal(model.deviceReady(parsed.devices[0]), true)
assert.equal(model.capabilityAvailable(parsed.devices[0], 'messaging'), true)
assert.equal(parsed.devices[0].capabilities.messaging.permission, 'unknown')
assert.equal(model.capabilityAvailable(rawDevice, 'messaging'), false, 'raw wire objects are not validated status')
for (const [field,value,reason] of [['paired',false,'unpaired'],['reachable',false,'offline'],['paired',null,'connection-unknown']]) {
  parsed = model.parseStatus(JSON.stringify({...status,devices:[{...rawDevice,[field]:value}]}))
  assert.equal(model.deviceReady(parsed.devices[0]), false)
  assert.equal(model.capabilityReason(parsed.devices[0], 'messaging'), reason)
}
for (const [field,value,reason] of [['supported',false,'not-supported'],['loaded',false,'plugin-not-loaded'],['enabled',false,'plugin-disabled'],['loaded','true','capability-unknown']]) {
  parsed = model.parseStatus(JSON.stringify({...status,devices:[{...rawDevice,capabilities:{messaging:{...capability,[field]:value}}}]}))
  assert.equal(model.capabilityAvailable(parsed.devices[0], 'messaging'), false)
  assert.equal(model.capabilityReason(parsed.devices[0], 'messaging'), reason)
}
parsed = model.parseStatus(JSON.stringify({...status,backend:{...status.backend,available:false}}))
assert.equal(model.deviceReady(parsed.devices[0]), false)
assert.equal(model.capabilityReason(parsed.devices[0],'messaging'),'backend-unavailable')
assert.equal(model.selectedDeviceId([{...rawDevice,paired:false}],''),'')
assert.equal(model.selectedDeviceId([{...rawDevice,paired:null}],''),'')
assert.equal(model.selectedDeviceId([{...rawDevice,reachable:false}],''),'phone1')
assert.equal(model.parseStatus('broken').schemaVersion,0)
assert.equal(model.parseStatus(JSON.stringify({...status,schemaVersion:2})).ok,false)
assert.equal(model.parseStatus(JSON.stringify({...status,backend:{...status.backend,version:'PRIVATE version'}})).ok,false)

const diagnostic = {...status,devices:[{...rawDevice,label:'device-1',secret:'SECRET',path:'/private'}],extra:'SECRET'}
let safe = model.parseDiagnostics(JSON.stringify(diagnostic))
assert(safe)
assert(!JSON.stringify(safe).includes('Private'))
assert(!JSON.stringify(safe).includes('SECRET'))
assert(!JSON.stringify(safe).includes('phone1'))
assert(!JSON.stringify(safe).includes('/private'))
assert.equal(safe.devices[0].capabilities.messaging.permission,'unknown')
assert.equal(model.parseDiagnostics(JSON.stringify({...diagnostic,devices:[{...rawDevice,label:'PRIVATE'}]})),null)
assert.equal(model.parseDiagnostics(JSON.stringify({...diagnostic,backend:{...status.backend,version:'26.08.1 PRIVATE'}})),null)
assert.equal(model.parseDiagnostics(' '.repeat(65537)),null)
safe = model.parseDiagnostics(JSON.stringify({...diagnostic,ok:false,failureReason:'backend-unavailable',backend:{...status.backend,available:false},devices:[]}))
assert.equal(safe.failureReason,'backend-unavailable')
assert.equal(model.parseDiagnostics(JSON.stringify({...diagnostic,ok:false,failureReason:'PRIVATE'})),null)
console.log('capability model tests passed')
