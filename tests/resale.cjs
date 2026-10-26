// Executes the actual WS helpers after translating their small, fixed subset to JS.
// Native inventory serialization and transfer behavior are represented by mocks;
// this does not replace a game-runtime save/load and buyback test.
'use strict';

const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const crypto = require('crypto');

const helperPath = path.join(__dirname, '..', 'mods', 'modLojasRenovadas7Dias', 'content', 'scripts', 'game', 'npc', 'merchantNPC.ws');
const ws = fs.readFileSync(helperPath, 'utf8');
const sourceHash = crypto.createHash('sha256').update(ws).digest('hex');
const savedFields = ['weeklyResaleEntries', 'weeklyResaleStarted', 'weeklyResaleTime', 'weeklyResaleNotice', 'weeklyResaleCancelledByDeath', 'weeklyResaleMonitorSlot'];

function matchingParen(text, start) {
  let depth = 0;
  for (let i = start; i < text.length; i++) {
    if (text[i] === '(') depth++;
    if (text[i] === ')' && --depth === 0) return i;
  }
  throw new Error('Unclosed cast operand');
}

function translateCasts(body) {
  body = body.replace(/\(float\)/g, '');
  while (body.includes('(int)')) {
    const start = body.lastIndexOf('(int)');
    let operandStart = start + 5;
    while (/\s/.test(body[operandStart])) operandStart++;
    assert.equal(body[operandStart], '(', 'Only parenthesized WS int casts are supported');
    const end = matchingParen(body, operandStart);
    body = body.slice(0, start) + 'Math.trunc(' + body.slice(operandStart, end + 1) + ')' + body.slice(end + 1);
  }
  return body;
}

function initialValue(type) {
  if (type === 'int' || type === 'float') return '0';
  if (type === 'bool') return 'false';
  if (type === 'string') return '""';
  if (type === 'SWeeklyResaleItemData') return '({ quantity: 0, paid: 0, cycle: 0, before: 0 })';
  if (/^array<.+>$/.test(type)) return '[]';
  if (type === 'CInventoryComponent' || type === 'SItemUniqueId') return 'null';
  throw new Error('Unsupported WS local type: ' + type);
}

const selectedNames = new Set(["WeeklyResaleAllowed", "WeeklyReadSale", "WeeklyClearSale", "WeeklyWriteSale", "WeeklyRestoreClock", "WeeklySetMarkedClock", "WeeklyPendingQuantity", "WeeklyQueueNotice", "WeeklyShowReceipt", "WeeklyRecordSale", "WeeklyRecordBuyback", "WeeklyProcessResale", "WeeklyCanRefreshStock"]);
function extractFunctions(source) {
  const signature = /(?:public|private)\s+(?:timer\s+)?function\s+(\w+)\s*\(([^)]*)\)\s*(?::\s*\w+)?\s*\{/g;
  const functions = [];
  let match;
  while ((match = signature.exec(source))) {
    const start = signature.lastIndex;
    let i = start, depth = 1;
    for (; i < source.length && depth; i++) {
      if (source[i] === '{') depth++;
      if (source[i] === '}') depth--;
    }
    assert.equal(depth, 0, 'Balanced function braces');
    functions.push({ name: match[1], parameters: match[2], body: source.slice(start, i - 1) });
    signature.lastIndex = i;
  }
  const selected = functions.filter(fn => selectedNames.has(fn.name));
  assert.equal(selected.length, selectedNames.size, 'Expected all current transaction helpers');
  return selected;
}

const extracted = extractFunctions(ws);
const methodNames = extracted.map(fn => fn.name);

function translateFunction(fn) {
  const params = fn.parameters.trim() ? fn.parameters.split(',').map(p => {
    const match = p.trim().match(/^(\w+)\s*:\s*(\w+)$/);
    assert.ok(match, 'Supported typed parameter: ' + p);
    return { name: match[1], type: match[2] };
  }) : [];
  let body = fn.body;
  body = body.replace(/var\s+([\w,\s]+)\s*:\s*([\w<>]+)\s*;/g, (_, names, type) =>
    names.split(',').map(name => 'let ' + name.trim() + ' = ' + initialValue(type) + ';').join('\n'));
  body = translateCasts(body);
  body = body.replace(/\b(\d+(?:\.\d+)?)f\b/g, '$1');
  body = body.replace(/\.Size\(\)/g, '.length').replace(/\.Clear\(\)/g, '.splice(0)');
  for (const field of savedFields) body = body.replace(new RegExp('\\b' + field + '\\b', 'g'), 'this.' + field);
  for (const name of [...methodNames, 'GetInventory', 'WeeklyHasStockProfile', 'WeeklyCleanLegacy', 'AddTimer', 'RemoveTimer', 'WeeklyIsResaleExcluded', 'WeeklyPrepareResaleExclusion', 'WeeklyBindMonitorSlot', 'WeeklyClearDeathMarkers', 'WeeklyResumeNativeLoot', 'WeeklyMonitorSync', 'IsAlive']) {
    body = body.replace(new RegExp('(?<![.\\w])' + name + '\\s*\\(', 'g'), 'this.' + name + '(');
  }
  // WS int/int division truncates. This is the only such expression here;
  // monetary divisions use explicit float operands before the int cast.
  body = body.replace(/hours\s*=\s*([^;]+);/g, 'hours = Math.trunc($1);');
  assert.ok(!/\bvar\b|\(int\)|\(float\)|\.Size\(|\.Clear\(/.test(body), 'No untranslated WS constructs');
  // WS structs are values: modifying a struct parameter must not mutate caller state.
  const copies = params.filter(p => p.type === 'SWeeklyResaleItemData').map(p => p.name + ' = { ...' + p.name + ' };').join('\n');
  return `${fn.name}(${params.map(p => p.name).join(', ')}) {\n${copies}\n${body}\n}`;
}

const translated = extracted.map(translateFunction).join(',\n');
const makeHelpers = new Function('theGame', 'GetWitcherPlayer', 'GameTimeToSeconds', 'LogChannel', 'EInventoryFunds_Unlimited',
  'return ({\n' + translated + '\n});');

class Inventory {
  constructor(items = [], money = 0) {
    this.items = new Map(items.map(item => [item.id, {
      quantity: 1, name: 'Sword', category: 'weapon', modifiers: {}, tags: [], ...structuredClone(item),
    }]));
    this.money = money;
    this.payments = [];
    this.fundsType = 'average';
    this.removeLimit = Infinity;
  }
  IsIdValid(id) { return this.items.has(id); }
  GetItemQuantity(id) { return this.items.get(id)?.quantity ?? 0; }
  GetItemName(id) { return this.items.get(id).name; }
  GetItemCategory(id) { return this.items.get(id).category; }
  GetItemModifierInt(id, key, fallback) { return this.items.get(id)?.modifiers[key] ?? fallback; }
  SetItemModifierInt(id, key, value) { this.items.get(id).modifiers[key] = value; }
  ItemHasTag(id, tag) { return this.items.get(id).tags.includes(tag); }
  IsItemQuest(id) { return Boolean(this.items.get(id).quest); }
  IsItemMounted(id) { return Boolean(this.items.get(id).mounted); }
  IsItemHeld(id) { return Boolean(this.items.get(id).held); }
  IsItemFists(id) { return Boolean(this.items.get(id).fists); }
  IsRecipeOrSchematic(id) { return Boolean(this.items.get(id).recipe); }
  GetAllItems(out) { out.push(...this.items.keys()); }
  GetFundsType() { return this.fundsType; }
  AddMoney(value) { this.money += value; this.payments.push(value); }
  RemoveItem(id, quantity) {
    const item = this.items.get(id);
    const removed = Math.min(quantity, item.quantity, this.removeLimit);
    item.quantity -= removed;
    if (item.quantity === 0) this.items.delete(id);
    return removed;
  }
  add(id, spec) { this.items.set(id, { quantity: 1, name: 'Sword', category: 'weapon', modifiers: {}, tags: [], ...structuredClone(spec) }); }
  serializeAndRekey() {
    // Deliberately lose every previous unique ID and retain item data only.
    const saved = JSON.parse(JSON.stringify([...this.items.values()]));
    this.items = new Map(saved.map((item, i) => ['loaded-' + i, { ...item, id: 'loaded-' + i }]));
  }
}

function merchant(inventory, start = 1000000) {
  const environment = {
    now: start, menu: false, dialog: false, fading: false, playerPresent: true,
    logs: [], messages: [], timers: new Map(),
  };
  const theGame = {
    WeeklyMonitorWasCancelledByDeath:()=>false, WeeklyMonitorHasManualCancel:()=>false, WeeklyMonitorAcknowledgeCancel:()=>{},
    params: { TAG_DONT_SHOW: 'DontShow' },
    GetGameTime: () => environment.now,
    IsDialogOrCutscenePlaying: () => environment.dialog,
    IsBlackscreenOrFading: () => environment.fading,
    GetGuiManager: () => ({ IsAnyMenu: () => environment.menu }),
  };
  const player = { DisplayHudMessage: message => environment.messages.push(message) };
  const npc = makeHelpers(theGame, () => environment.playerPresent ? player : null, value => value,
    (channel, message) => environment.logs.push({ channel, message }), 'unlimited');
  Object.assign(npc, {
    weeklyResaleEntries: [], weeklyResaleStarted: false, weeklyResaleTime: 0, weeklyResaleNotice: '',
    weeklyResaleCancelledByDeath:false, weeklyResaleMonitorSlot:1,
    WeeklyIsResaleExcluded:()=>false, WeeklyPrepareResaleExclusion:()=>{}, WeeklyBindMonitorSlot:()=>{}, WeeklyClearDeathMarkers:()=>{}, WeeklyResumeNativeLoot:()=>{}, WeeklyMonitorSync:()=>{}, IsAlive:()=>true,
    GetInventory: () => inventory, WeeklyHasStockProfile: () => false, WeeklyCleanLegacy: () => 0,
    AddTimer: (name, delay, repeat) => environment.timers.set(name, { delay, repeat }),
    RemoveTimer: name => environment.timers.delete(name),
  });
  return { npc, environment, inventory };
}

function buyback(harness, id, quantity, customer, customerId, success = true) {
  const { npc, inventory } = harness;
  const snapshot = npc.WeeklyReadSale(id);
  npc.WeeklyClearSale(inventory, id);
  if (!success) {
    npc.WeeklyWriteSale(id, snapshot);
    return snapshot;
  }
  const nativeData = structuredClone(inventory.items.get(id));
  inventory.RemoveItem(id, quantity);
  customer.add(customerId, { ...nativeData, quantity });
  npc.WeeklyRecordBuyback(id, quantity, snapshot, customer, customerId);
  return snapshot;
}

let passed = 0;
function test(name, action) {
  try { action(); passed++; console.log('PASS ' + name); }
  catch (error) { console.error('FAIL ' + name); throw error; }
}

test('sale two, IDs replaced, NPC state reset, buyback one, liquidate only remainder at 168 hours', () => {
  const inv = new Inventory([
    { id: 'natural', name: 'same-model' }, { id: 'sale-a', name: 'same-model' }, { id: 'sale-b', name: 'other-model' },
  ], 50);
  let h = merchant(inv);
  const start = h.environment.now;
  h.npc.WeeklyRecordSale('sale-a', 1, 101);
  h.npc.WeeklyRecordSale('sale-b', 1, 203);
  inv.serializeAndRekey();
  h = merchant(inv, start + 3600); // NPC custom saved state deliberately lost.
  h.npc.weeklyResaleEntries = [{ item: 'natural', itemName: 'same-model', quantity: 1, paid: 999 }];
  const customer = new Inventory();
  buyback(h, 'loaded-1', 1, customer, 'purchased-a');
  assert.equal(customer.GetItemQuantity('purchased-a'), 1);
  assert.equal(customer.GetItemModifierInt('purchased-a', 'LR7Sale', 0), 0);
  h.environment.now = start + 604800;
  h.npc.WeeklyProcessResale();
  assert.ok(inv.IsIdValid('loaded-0'), 'Unmarked original stock with identical name survives');
  assert.ok(!inv.IsIdValid('loaded-2'), 'Remaining recorded sale is removed');
  assert.equal(inv.money, 50 + Math.floor(203 * 1.25));
  assert.equal(h.npc.weeklyResaleEntries.length, 0, 'Stale pre-0.4.2 records are discarded');
  assert.match(h.npc.weeklyResaleNotice, /1 itens revendidos \(\+253 coroas\)/);
});

test('167 hours 59 minutes is pending; exactly 168 hours processes', () => {
  const h = merchant(new Inventory([{ id: 'a' }]));
  const start = h.environment.now;
  h.npc.WeeklyRecordSale('a', 1, 80);
  h.environment.now = start + 604740;
  h.npc.WeeklyProcessResale();
  assert.ok(h.inventory.IsIdValid('a'));
  assert.equal(h.inventory.money, 0);
  assert.match(h.npc.weeklyResaleNotice, /faltam 1 horas/);
  h.environment.now = start + 604800;
  h.npc.WeeklyProcessResale();
  assert.ok(!h.inventory.IsIdValid('a'));
  assert.equal(h.inventory.money, 100);
});

test('natural stack five plus four sales, buyback one, preserve five and liquidate three', () => {
  const h = merchant(new Inventory([{ id: 'merged', quantity: 9, name: 'material' }]));
  const start = h.environment.now;
  h.npc.WeeklyRecordSale('merged', 4, 101);
  const customer = new Inventory();
  const snapshot = buyback(h, 'merged', 1, customer, 'bought');
  assert.deepEqual(snapshot, { quantity: 4, paid: 101, cycle: start, before: 9 });
  assert.equal(h.npc.WeeklyReadSale('merged').quantity, 3);
  assert.equal(h.npc.WeeklyReadSale('merged').paid, 75);
  assert.equal(snapshot.quantity, 4, 'WS struct argument retains caller value');
  h.environment.now += 604800;
  h.npc.WeeklyProcessResale();
  assert.equal(h.inventory.GetItemQuantity('merged'), 5);
  assert.equal(h.inventory.money, Math.floor(75 * 1.25));
  assert.equal(h.inventory.GetItemModifierInt('merged', 'LR7Sale', 0), 0);
  assert.equal(customer.GetItemModifierInt('bought', 'LR7Sale', 0), 0);
});

test('failed native buyback restores original item metadata and later payout', () => {
  const h = merchant(new Inventory([{ id: 'a', quantity: 2 }]));
  h.npc.WeeklyRecordSale('a', 2, 81);
  const before = h.npc.WeeklyReadSale('a');
  const customer = new Inventory();
  buyback(h, 'a', 1, customer, 'failed', false);
  assert.deepEqual(h.npc.WeeklyReadSale('a'), before);
  assert.equal(customer.items.size, 0);
  h.environment.now += 604800;
  h.npc.WeeklyProcessResale();
  assert.equal(h.inventory.money, 101);
});

test('buying unmarked natural stock does not add custom metadata to the player item', () => {
  const h = merchant(new Inventory([{ id: 'natural' }]));
  const customer = new Inventory([{ id: 'purchase', modifiers: { unrelated: 7 } }]);
  const snapshot = h.npc.WeeklyReadSale('natural');
  h.inventory.RemoveItem('natural', 1);
  h.npc.WeeklyRecordBuyback('natural', 1, snapshot, customer, 'purchase');
  assert.deepEqual(customer.items.get('purchase').modifiers, { unrelated: 7 });
  assert.equal(h.inventory.money, 0);
});

test('empty next cycle does not pay again or remove natural stock', () => {
  const h = merchant(new Inventory([{ id: 'a' }, { id: 'natural', quantity: 5 }], 7));
  h.npc.WeeklyRecordSale('a', 1, 100);
  h.environment.now += 604800;
  h.npc.WeeklyProcessResale();
  h.environment.now += 604800;
  h.npc.WeeklyProcessResale();
  assert.equal(h.inventory.money, 132);
  assert.deepEqual(h.inventory.payments, [125]);
  assert.equal(h.inventory.GetItemQuantity('natural'), 5);
});

test('quest, tagged, mounted, held, crowns, fists, Gwent, map and recipe are protected', () => {
  const protectedSpecs = [
    { quest: true }, ...['Quest', 'QuestEP1', 'QuestEP2', 'NoDrop', 'DontShow', 'ThMap'].map(tag => ({ tags: [tag] })),
    { mounted: true }, { held: true }, { name: 'Crowns' }, { fists: true }, { category: 'gwint' }, { recipe: true },
  ];
  const h = merchant(new Inventory(protectedSpecs.map((spec, i) => ({ id: 'protected-' + i, ...spec }))));
  for (const id of h.inventory.items.keys()) {
    assert.equal(h.npc.WeeklyResaleAllowed(id), false);
    h.npc.WeeklyRecordSale(id, 1, 100);
    assert.equal(h.npc.WeeklyReadSale(id).quantity, 0);
    // An item can become protected after it was registered: deletion remains forbidden.
    h.npc.WeeklyWriteSale(id, { quantity: 1, paid: 100, cycle: h.environment.now, before: 1 });
  }
  h.environment.now += 604800;
  h.npc.WeeklyProcessResale();
  assert.equal(h.inventory.items.size, protectedSpecs.length);
  assert.equal(h.inventory.money, 0);
});

test('clock moves backwards: reset marked cycle and wait a full seven days again', () => {
  const h = merchant(new Inventory([{ id: 'a' }]));
  const original = h.environment.now;
  h.npc.WeeklyRecordSale('a', 1, 120);
  h.environment.now = original - 100;
  h.npc.WeeklyProcessResale();
  assert.equal(h.npc.weeklyResaleTime, original - 100);
  assert.equal(h.npc.WeeklyReadSale('a').cycle, original - 100);
  h.environment.now += 604799;
  h.npc.WeeklyProcessResale();
  assert.equal(h.inventory.money, 0);
  h.environment.now++;
  h.npc.WeeklyProcessResale();
  assert.equal(h.inventory.money, 150);
});

test('partial and failed removal count only items actually removed', () => {
  const h = merchant(new Inventory([{ id: 'a', quantity: 4 }]));
  h.npc.WeeklyRecordSale('a', 4, 100);
  h.inventory.removeLimit = 0;
  h.environment.now += 604800;
  h.npc.WeeklyProcessResale();
  assert.equal(h.inventory.money, 0);
  assert.equal(h.npc.WeeklyReadSale('a').quantity, 4);
  h.inventory.removeLimit = 2;
  h.environment.now += 604800;
  h.npc.WeeklyProcessResale();
  assert.equal(h.inventory.GetItemQuantity('a'), 2);
  assert.equal(h.npc.WeeklyReadSale('a').quantity, 2);
  assert.equal(h.npc.WeeklyReadSale('a').paid, 50);
  assert.equal(h.inventory.money, 62);
});

test('receipt waits until menus, dialogue and fading have ended', () => {
  const h = merchant(new Inventory([{ id: 'a' }]));
  h.npc.WeeklyRecordSale('a', 1, 20);
  for (const blocked of ['menu', 'dialog', 'fading']) {
    h.environment[blocked] = true;
    h.npc.WeeklyShowReceipt(1, 0);
    assert.equal(h.environment.messages.length, 0);
    assert.ok(h.environment.timers.has('WeeklyShowReceipt'));
    h.environment[blocked] = false;
  }
  h.npc.WeeklyShowReceipt(1, 0);
  assert.equal(h.environment.messages.length, 1);
  assert.equal(h.npc.weeklyResaleNotice, '');
  assert.ok(!h.environment.timers.has('WeeklyShowReceipt'));
});

console.log(JSON.stringify({ passed, helperPath, sourceHash,
  limitations: [
    'Executes translated helper logic, not the WitcherScript compiler or game runtime.',
    'Mock retains item modifiers through serialization; native persistence must be checked in game.',
    'Mock transfers to a known destination ID; native splitting/merging and GUI call order require separate checks.',
    'Legacy catalog cleanup and native merchant funds refresh are disabled in these isolated tests.',
  ],
}, null, 2));
