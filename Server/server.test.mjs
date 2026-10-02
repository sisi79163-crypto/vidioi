import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createGateway } from './server.mjs';
import { validatePlan, validateProject } from './commands.mjs';

const id = '10000000-0000-4000-8000-000000000001';
const clipID = '10000000-0000-4000-8000-000000000002';
function project() { return { version: 1, id, title: 'Test', width: 1080, height: 1920, fps: 30, clips: [{
  id: clipID, kind: 'text', name: 'عنوان', text: 'عنوان', start: 0, sourceIn: 0, duration: 4, speed: 1, lane: 1, volume: 1,
  style: { x: .5, y: .75, scale: 1, stretch: 1, rotation: 0, opacity: 1, fontSize: 84, fontName: 'Arial-BoldMT', color: '#FFFFFF', motion: 'pop', brightness: 0, contrast: 1, saturation: 1 }, keys: []
}] }; }
function plan(operations) { return { summary: 'تعديلات', operations }; }
function op(fields) { return { action: 'set', clipID, property: 'scale', number: 1.3, text: null, time: null, ...fields }; }
test('valid numeric, text, animation and new text operations', () => {
  const p = project();
  const result = plan([op({}), op({ property: 'color', number: null, text: '#FF3434' }),
    op({ action: 'keyframe', property: 'scale', time: 1, number: 2 }),
    op({ action: 'addText', clipID: null, property: null, time: 5, number: 2, text: 'نهاية' })]);
  assert.equal(validatePlan(result, p), result);
  assert.equal(p.clips.length, 1); assert.equal(p.clips[0].style.scale, 1);
});
test('rejects missing IDs, nonfinite values and arbitrary properties', () => {
  for (const fields of [{ clipID: crypto.randomUUID() }, { number: Infinity }, { number: 0 }, { property: '__proto__' }, { property: 'asset', text: '/tmp/file' }, { property: 'lane', number: 1.5 }]) {
    assert.throws(() => validatePlan(plan([op(fields)]), project()));
  }
});
test('commands are checked against sequential resulting state', () => {
  assert.throws(() => validatePlan(plan([op({ action: 'remove' }), op({})]), project()), /Unknown clip/);
  assert.throws(() => validatePlan(plan([op({ action: 'keyframe', time: 3, number: 2 }), op({ property: 'duration', number: 2 })]), project()), /keyframe/);
});
test('rejects keyframes outside clip, asset traversal and duplicate clip IDs', () => {
  assert.throws(() => validatePlan(plan([op({ action: 'keyframe', time: 5 })]), project()));
  const p = project(); p.clips[0].kind = 'video'; p.clips[0].asset = '../secret.mp4';
  assert.throws(() => validateProject(p), /asset path/);
  const q = project(); q.clips.push(structuredClone(q.clips[0])); assert.throws(() => validateProject(q), /duplicate/);
});
test('limits command count and text size', () => {
  assert.throws(() => validatePlan(plan(Array.from({ length: 101 }, () => op({}))), project()));
  assert.throws(() => validatePlan(plan([op({ property: 'text', text: 'a'.repeat(10001) })]), project()));
});
async function gateway(t, provider = async () => plan([op({})]), options = {}) {
  const token = 'test-token-with-enough-characters';
  const server = createGateway({ token, provider, ...options });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const url = `http://127.0.0.1:${server.address().port}`;
  const request = (body = { prompt: 'كبّر النص', project: project() }, headers = {}) => fetch(url + '/v1/edit', {
    method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json', ...headers }, body: JSON.stringify(body)
  });
  return { request, url };
}
test('gateway returns valid plan and does not require live API in tests', async t => {
  const { request } = await gateway(t); const r = await request();
  assert.equal(r.status, 200); assert.equal((await r.json()).operations[0].number, 1.3);
});
test('gateway rejects unauthorized requests before provider', async t => {
  let called = false; const { request } = await gateway(t, async () => { called = true; });
  const r = await request(undefined, { authorization: 'Bearer bad' }); assert.equal(r.status, 401); assert.equal(called, false);
});
test('gateway rejects invalid content type and project', async t => {
  const { request } = await gateway(t);
  assert.equal((await request(undefined, { 'content-type': 'text/plain' })).status, 415);
  assert.equal((await request({ prompt: 'x', project: {} })).status, 400);
});
test('gateway rejects unsafe model output without exposing provider errors', async t => {
  const { request } = await gateway(t, async () => plan([op({ property: 'asset', text: '/secret' })]));
  const r = await request(); assert.equal(r.status, 502); assert.ok(!(await r.text()).includes('/secret'));
});
test('rate limiting bounds repeated spending', async t => {
  const { request } = await gateway(t, undefined, { perMinute: 1 });
  assert.equal((await request()).status, 200); assert.equal((await request()).status, 429);
});
test('gateway fails closed without a usable token', () => {
  assert.throws(() => createGateway({ token: '' })); assert.throws(() => createGateway({ token: 'short' }));
});

test('status endpoint is authenticated and never returns secrets', async t => {
  const { url } = await gateway(t, undefined, { key: 'not-a-real-api-key' });
  assert.equal((await fetch(url + '/v1/status')).status, 401);
  const r = await fetch(url + '/v1/status', { headers: { authorization: 'Bearer test-token-with-enough-characters' } });
  assert.equal(r.status, 200);
  const body = await r.text();
  assert.equal(JSON.parse(body).aiConfigured, true);
  assert.equal(body.includes('not-a-real-api-key'), false);
});
