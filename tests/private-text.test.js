const assert = require('node:assert/strict');
const text = require('../PrivateText.js');
const body = '  exact\ntext 😀  ';
assert.equal(JSON.parse(text.serialize({version:1,body})).body, body);
assert.equal(text.byteLength('😀'), 4);
assert.equal(text.serialize({body:'😀'.repeat(2049)}), '');
assert.equal(text.serialize({body:'\ud800'}), '');
assert.equal(text.serialize({body:'a\0b'}), '');
const result = (value, code) => text.outcome(JSON.stringify(value), code);
assert.equal(result({version:1,ok:true,state:'accepted',code:'accepted'}, 0).state, 'accepted');
assert.equal(result({version:1,ok:true,state:'accepted',code:'accepted'}, 1).state, 'unconfirmed');
assert.equal(result({version:1,ok:false,state:'not-submitted',code:'dependency',statusText:'SECRET'}, 1).text,
  'Install python-dbus to send text and messages');
assert.equal(result({version:2,ok:false,state:'not-submitted',code:'dependency'}, 1).state, 'unconfirmed');
assert.equal(result({version:1,ok:false,state:'not-submitted',code:'toString'}, 1).state, 'unconfirmed');
assert.equal(text.outcome('x'.repeat(4097),0).state, 'unconfirmed');
assert.equal(text.outcome('',0).state, 'unconfirmed');
console.log('private text model tests passed');
