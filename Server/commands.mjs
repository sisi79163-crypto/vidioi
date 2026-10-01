const numeric = {
  start: [0, 3600], sourceIn: [0, 3600], duration: [0.05, 3600], speed: [0.25, 4],
  lane: [0, 31], volume: [0, 4], x: [-2, 3], y: [-2, 3], scale: [0.05, 8],
  stretch: [0.1, 5], rotation: [-3600, 3600], opacity: [0, 1], fontSize: [8, 400],
  brightness: [-1, 1], contrast: [0, 4], saturation: [0, 4]
};
const styleNumbers = new Set(['x', 'y', 'scale', 'stretch', 'rotation', 'opacity', 'fontSize', 'brightness', 'contrast', 'saturation']);
const textProperties = new Set(['text', 'color', 'motion', 'fontName']);
const animated = new Set(['x', 'y', 'scale', 'stretch', 'rotation', 'opacity']);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const defaults = { x: 0.5, y: 0.75, scale: 1, stretch: 1, rotation: 0, opacity: 1, fontSize: 84,
  fontName: 'Arial-BoldMT', color: '#FFFFFF', motion: 'pop', brightness: 0, contrast: 1, saturation: 1 };
function insist(condition, message) { if (!condition) throw new Error(message); }
function checkNumber(property, value) {
  const range = numeric[property];
  insist(range && Number.isFinite(value) && value >= range[0] && value <= range[1], `Invalid ${property}`);
  if (property === 'lane') insist(Number.isInteger(value), 'Lane must be an integer');
}
function checkText(property, value) {
  insist(typeof value === 'string' && value.length <= 10000, `Invalid ${property}`);
  if (property === 'color') insist(/^#[0-9a-f]{6}$/i.test(value), 'Invalid color');
  if (property === 'motion') insist(['none', 'fade', 'pop', 'slide'].includes(value), 'Invalid motion');
  if (property === 'fontName') insist(value.length <= 200, 'Invalid font name');
}
export function validateProject(project) {
  insist(project && project.version === 1 && uuid.test(project.id), 'Invalid project version or ID');
  insist(typeof project.title === 'string' && project.title.length <= 2000, 'Invalid project title');
  insist(Number.isInteger(project.width) && project.width >= 128 && project.width <= 3840 &&
    Number.isInteger(project.height) && project.height >= 128 && project.height <= 3840 && [24, 25, 30, 60].includes(project.fps), 'Invalid format');
  insist(Array.isArray(project.clips) && project.clips.length <= 500, 'Too many clips');
  const ids = new Set();
  for (const c of project.clips) {
    insist(uuid.test(c.id) && !ids.has(c.id), 'Invalid or duplicate clip ID'); ids.add(c.id);
    insist(['video', 'audio', 'image', 'text'].includes(c.kind) && typeof c.name === 'string', 'Invalid clip');
    if (c.kind !== 'text') insist(typeof c.asset === 'string' && c.asset.length > 0 && !/[\\/]/.test(c.asset) && !c.asset.includes('..'), 'Invalid asset path');
    for (const property of ['start', 'sourceIn', 'duration', 'speed', 'lane', 'volume']) checkNumber(property, c[property]);
    insist(c.start + c.duration <= 3600, 'Project exceeds one hour');
    checkText('text', c.text);
    insist(c.style && typeof c.style === 'object', 'Missing style');
    for (const property of styleNumbers) checkNumber(property, c.style[property]);
    for (const property of ['color', 'motion', 'fontName']) checkText(property, c.style[property]);
    insist(Array.isArray(c.keys) && c.keys.length <= 500, 'Invalid keyframes');
    for (const k of c.keys) {
      insist(uuid.test(k.id) && animated.has(k.property) && Number.isFinite(k.time) && k.time >= 0 && k.time <= c.duration, 'Invalid keyframe');
      checkNumber(k.property, k.value);
    }
  }
  return project;
}
export function validatePlan(plan, project) {
  validateProject(project);
  insist(plan && typeof plan.summary === 'string' && plan.summary.length <= 4000 &&
    Array.isArray(plan.operations) && plan.operations.length <= 100, 'Invalid edit plan');
  const next = structuredClone(project);
  for (const op of plan.operations) {
    insist(op && ['set', 'keyframe', 'addText', 'remove'].includes(op.action), 'Unsupported action');
    if (op.action === 'addText') {
      insist(typeof op.text === 'string' && op.text.length > 0, 'Missing text'); checkText('text', op.text);
      checkNumber('start', op.time); checkNumber('duration', op.number);
      next.clips.push({ id: crypto.randomUUID(), kind: 'text', name: op.text.slice(0, 30), text: op.text,
        start: op.time, sourceIn: 0, duration: op.number, speed: 1, volume: 1,
        lane: Math.min(31, Math.max(0, ...next.clips.map(c => c.lane)) + 1), style: { ...defaults }, keys: [] });
      continue;
    }
    const index = next.clips.findIndex(c => c.id.toLowerCase() === String(op.clipID).toLowerCase());
    insist(index >= 0, 'Unknown clip ID');
    if (op.action === 'remove') { next.clips.splice(index, 1); continue; }
    const c = next.clips[index];
    if (op.action === 'keyframe') {
      insist(animated.has(op.property) && Number.isFinite(op.time) && op.time >= 0 && op.time <= c.duration, 'Invalid keyframe');
      checkNumber(op.property, op.number);
      c.keys = c.keys.filter(k => !(k.property === op.property && Math.abs(k.time - op.time) < 0.000001));
      c.keys.push({ id: crypto.randomUUID(), time: op.time, property: op.property, value: op.number });
    } else if (textProperties.has(op.property)) {
      checkText(op.property, op.text);
      if (op.property === 'text') c.text = op.text; else c.style[op.property] = op.text;
    } else {
      checkNumber(op.property, op.number);
      if (styleNumbers.has(op.property)) c.style[op.property] = op.number; else c[op.property] = op.number;
    }
  }
  validateProject(next);
  return plan;
}
export const planSchema = {
  type: 'object', additionalProperties: false, required: ['summary', 'operations'], properties: {
    summary: { type: 'string' }, operations: { type: 'array', maxItems: 100, items: {
      type: 'object', additionalProperties: false,
      required: ['action', 'clipID', 'property', 'number', 'text', 'time'], properties: {
        action: { type: 'string', enum: ['set', 'keyframe', 'addText', 'remove'] },
        clipID: { type: ['string', 'null'] },
        property: { type: ['string', 'null'], enum: [...Object.keys(numeric), ...textProperties, null] },
        number: { type: ['number', 'null'] }, text: { type: ['string', 'null'] }, time: { type: ['number', 'null'] }
      }
    } }
  }
};
