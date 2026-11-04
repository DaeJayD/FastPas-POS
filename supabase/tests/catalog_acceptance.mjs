import { randomUUID } from 'node:crypto';

// Uses public RPCs only. The caller validates all three Auth identities first.
// IDs are journaled before writes so a lost response still leaves a manifest.
export async function checkCatalogInventory({
  owner, unrelated, staff, anonymous, business, otherBusiness, destination,
  check, denied, rejected, recordFixture,
}) {
  const product = randomUUID();
  const labels = Object.fromEntries(['brand', 'category', 'family'].map(kind => [kind, randomUUID()]));
  const requests = Object.fromEntries([
    'brand', 'category', 'family', 'create', 'receive', 'count', 'transfer',
    'threshold', 'archiveBrand', 'archive', 'restore',
  ].map(operation => [operation, randomUUID()]));
  await recordFixture({ businessId: business.id, branchId: business.branch,
    destinationId: destination, productId: product, labelIds: labels, requestIds: requests });
  const labelArgs = kind => ({ business: business.id, request_id: requests[kind],
    label_id: labels[kind], kind, expected_version: 0, label_name: `Acceptance ${kind}`, enabled: true });
  const item = { id: product, version: 0, name: 'Acceptance tee', sku: `catalog-${product}`,
    price_cents: 1999, active: true, brand_id: labels.brand, category_id: labels.category,
    family_id: labels.family, variant_label: 'Blue', branch_id: business.branch, opening_quantity: 10 };
  const stockArgs = (operation, quantity, stockVersion, extra = {}) => ({
    business: business.id, request_id: requests[operation], change: {
      kind: operation, product_id: product, branch_id: business.branch,
      quantity, stock_version: stockVersion, reason: `Acceptance ${operation}`, ...extra,
    },
  });
  const page = (branch = business.branch, extra = {}) => owner.rpc('pos_catalog_items', {
    business: business.id, branch, search_text: item.sku, ...extra,
  });
  const history = branch => owner.rpc('pos_stock_history', { business: business.id, branch, product });

  for (const [role, api] of [['Anonymous', anonymous], ['Unrelated owner', unrelated], ['Cashier', staff]]) {
    for (const [name, args] of [
      ['pos_save_catalog_label', labelArgs('brand')],
      ['pos_catalog_items', { business: business.id, branch: business.branch }],
      ['pos_save_catalog_item', { business: business.id, request_id: requests.create, item }],
      ['pos_post_stock', stockArgs('receive', 5, 1)],
      ['pos_stock_history', { business: business.id, branch: business.branch }],
    ]) await denied(api, name, args, `${role} cannot call ${name}`);
  }
  for (const [role, api] of [['Anonymous', anonymous], ['Unrelated owner', unrelated]]) {
    await denied(api, 'pos_catalog_labels', { business: business.id }, `${role} cannot read catalog labels`);
  }
  for (const kind of Object.keys(labels)) {
    const args = labelArgs(kind);
    const saved = await owner.rpc('pos_save_catalog_label', args);
    const retry = await owner.rpc('pos_save_catalog_label', args);
    check(saved?.id === labels[kind] && saved.version === 1 && retry?.id === saved.id && retry.version === 1,
      `Owner creates and retries one ${kind}`);
  }
  const memberLabels = await staff.rpc('pos_catalog_labels', { business: business.id });
  check(memberLabels?.business_id === business.id && memberLabels.brands?.some(row => row.id === labels.brand),
    'Member reads scoped classifications without management rights');
  await owner.rpc('pos_save_catalog_item', { business: business.id, request_id: requests.create, item });
  await owner.rpc('pos_save_catalog_item', { business: business.id, request_id: requests.create, item });
  let rows = await page();
  check(rows?.length === 1 && rows[0].id === product && rows[0].name === 'Acceptance tee · Blue' &&
    rows[0].price_cents === 1999 && rows[0].quantity === 10 && rows[0].stock_version === 1,
  'Variant creation retry preserves one SKU and opening stock');
  await denied(owner, 'pos_catalog_items', { business: business.id, branch: otherBusiness.branch },
    'Catalog read rejects a cross-business branch');

  const receive = stockArgs('receive', 5, 1);
  const received = await owner.rpc('pos_post_stock', receive);
  const receiveRetry = await owner.rpc('pos_post_stock', receive);
  check(received?.quantity === 15 && received.stock_version === 2 && receiveRetry?.quantity === 15,
    'Receiving retry adds stock once');
  await denied(owner, 'pos_post_stock', stockArgs('count', 12, 1), 'Stale physical count is rejected', 'PT409', [409]);
  const counted = await owner.rpc('pos_post_stock', stockArgs('count', 12, 2));
  check(counted?.quantity === 12 && counted.stock_version === 3, 'Current physical count records its version');
  const transfer = stockArgs('transfer', 3, 3, { destination_id: destination, destination_version: 0 });
  const transfers = await Promise.allSettled([
    owner.rpc('pos_post_stock', transfer), owner.rpc('pos_post_stock', transfer),
  ]);
  const failed = transfers.find(result => result.status === 'rejected');
  if (failed) throw failed.reason;
  check(transfers.every(result => result.value?.quantity === 9 && result.value?.destination_quantity === 3),
    'Concurrent transfer retries move stock once');
  const [source, target] = await Promise.all([page(), page(destination)]);
  check(source[0]?.quantity === 9 && target[0]?.quantity === 3 && source[0]?.quantity + target[0]?.quantity === 12,
    'Transfer conserves stock across both branches');
  await denied(owner, 'pos_post_stock', { ...transfer, change: { ...transfer.change, quantity: 2 } },
    'Transfer retry with changed details is rejected', '22023', [400]);
  await denied(owner, 'pos_post_stock', { ...transfer, request_id: randomUUID(), change: {
    ...transfer.change, stock_version: source[0].stock_version, destination_id: otherBusiness.branch,
  } }, 'Transfer rejects a cross-business destination');
  const threshold = await owner.rpc('pos_post_stock', stockArgs('threshold', 4, source[0].stock_version));
  check(threshold?.quantity === 9 && (await page())[0]?.low_stock_threshold === 4,
    'Low-stock threshold preserves quantity');
  const [sourceMovements, targetMovements] = await Promise.all([history(business.branch), history(destination)]);
  check(sourceMovements?.length === 4 && targetMovements?.length === 1 &&
    sourceMovements.filter(row => row.kind === 'transfer').length === 1 &&
    targetMovements[0]?.quantity_delta === 3 && sourceMovements.every(row => row.product_name === 'Acceptance tee · Blue'),
  'Ledger retains opening, receiving, count and one transfer per branch');
  for (const [table, body] of [
    ['pos_brands', { active: false }], ['pos_items', { price_cents: 1 }],
    ['pos_item_stock', { quantity: 999 }], ['pos_stock_movements', { reason: 'Denied edit' }],
  ]) {
    await rejected(() => owner.request(`/rest/v1/${table}?business_id=eq.${business.id}`,
      { method: 'PATCH', body }), `Direct ${table} inventory edits are denied`);
  }

  await owner.rpc('pos_save_catalog_label', { ...labelArgs('brand'), request_id: requests.archiveBrand,
    expected_version: 1, enabled: false });
  await owner.rpc('pos_save_catalog_item', { business: business.id, request_id: requests.archive,
    item: { ...item, version: 1, active: false } });
  check((await page()).length === 0 && (await page(business.branch, { include_archived: true }))[0]?.brand_id === labels.brand,
    'Archiving a product retains its existing archived classification');
  await owner.rpc('pos_save_catalog_item', { business: business.id, request_id: requests.restore,
    item: { ...item, version: 2, active: true } });
  rows = await page();
  check(rows[0]?.version === 3 && rows[0]?.quantity === 9 && rows[0]?.stock_version === threshold.stock_version &&
    (await history(business.branch)).length === 4,
  'Restoring a product retains stock, threshold version and movement history');
}
