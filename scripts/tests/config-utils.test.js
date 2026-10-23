'use strict';
// Unit tests for contents/ui/js/configUtils.js, a QML ".pragma library"
// file: loaded here without its pragma line.
// Run: node --test scripts/tests/*.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const src = fs.readFileSync(path.join(__dirname, '../../contents/ui/js/configUtils.js'), 'utf8')
  .replace(/^\.pragma library$/m, '');
const U = {};
vm.runInNewContext(src, U);

test('colorFromText: hex colors as copied from color pickers and editors', () => {
  assert.equal(U.colorFromText('#1E64FF'), '#1e64ff');
  assert.equal(U.colorFromText('1e64ff'), '#1e64ff');
  assert.equal(U.colorFromText('  #ffdc00\n'), '#ffdc00');
  assert.equal(U.colorFromText('#f80'), '#ff8800');
});

test('colorFromText: anything else is no color', () => {
  assert.equal(U.colorFromText(''), '');
  assert.equal(U.colorFromText(null), '');
  assert.equal(U.colorFromText('#12345'), '');
  assert.equal(U.colorFromText('#gg0000'), '');
  assert.equal(U.colorFromText('wind 38 km/h'), '');
  assert.equal(U.colorFromText('#ff000080'), '');
});
