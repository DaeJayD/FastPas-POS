import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const db = new PGlite();
const owner = randomUUID(), other = randomUUID(), staff = randomUUID();
let business, otherBusiness, branch, destination, otherBranch, product;
let upgradeFixture;
const scalar = async (sql, args=[]) => Object.values((await db.query(sql,args)).rows[0])[0];
const identity = async (actor=owner, role='authenticated') => {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[actor]);
  await db.exec(`set role ${role}`);
};
const rpc = async (name, args) => {
  assert.match(name,/^pos_[a-z_]+$/);
  const keys=Object.keys(args);
  keys.forEach(key=>assert.match(key,/^[a-z_]+$/));
  return scalar(`select public.${name}(${keys.map((key,i)=>`${key}=>$${i+1}`).join(',')})`,
    keys.map(key=>args[key]!==null&&typeof args[key]==='object'?JSON.stringify(args[key]):args[key]));
};
const reject = (action, code) => assert.rejects(action,error=>error.code===code);
const page = (at=branch, extra={}) => rpc('pos_catalog_items',{business,branch:at,...extra});
const stock = (kind,quantity,extra={},request_id=randomUUID()) => rpc('pos_post_stock',{
  business,request_id,change:{kind,branch_id:branch,product_id:product,quantity,stock_version:1,reason:'Test stock operation',...extra},
});
const label = (kind,name='Test label',extra={}) => rpc('pos_save_catalog_label',{
  business,request_id:randomUUID(),label_id:randomUUID(),kind,expected_version:0,label_name:name,enabled:true,...extra,
});
const history = () => rpc('pos_stock_history',{business,branch,product});
before(async () => {
  await db.exec(`create role anon;create role authenticated;create schema auth;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
    create function auth.uid() returns uuid language sql stable as
      $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
  for(const [id,email] of [[owner,'owner'],[other,'other'],[staff,'staff']]) {
    await db.query('insert into auth.users values($1,$2,now())',[id,`${email}@example.test`]);
  }
  for(const file of ['202610210001_business_workspaces.sql','202610210002_hybrid_cash_sales.sql',
    '202610210003_staff_access.sql','202610240001_staff_branch_access.sql','202610310001_business_settings.sql']) {
    await db.exec(await readFile(new URL(`../migrations/${file}`,import.meta.url),'utf8'));
  }
  await identity();
  const priorBusiness = randomUUID();
  await rpc('pos_create_business',{request_id:priorBusiness,business_name:'Before upgrade',branch_name:'Original'});
  const priorBranch = await scalar('select id from public.pos_branches where business_id=$1',[priorBusiness]);
  const priorProduct = await rpc('pos_add_item',{business:priorBusiness,branch:priorBranch,product_name:'Original item',product_sku:'ORIGINAL',unit_cents:1999,opening_quantity:10});
  const sale = {id:randomUUID(),business_id:priorBusiness,branch_id:priorBranch,device_id:randomUUID(),occurred_at:new Date().toISOString(),cash_cents:3998,
    items:[{product_id:priorProduct,name:'Original item',sku:'ORIGINAL',quantity:2,unit_cents:1999}]};
  await rpc('pos_sync_cash_sale',{sale});
  upgradeFixture={business:priorBusiness,branch:priorBranch,product:priorProduct,sale,
    receipt:(await db.query('select * from public.pos_cash_sales where id=$1',[sale.id])).rows[0]};
  await db.exec('reset role');
  const preflight=await db.query(await readFile(new URL('../catalog_inventory_preflight.sql',import.meta.url),'utf8'));
  assert.equal(preflight.rows[0].phase_4_installed,true);
  assert.equal(preflight.rows[0].phase_5_installed,false);
  await db.exec(await readFile(new URL('../migrations/202611030001_catalog_inventory.sql',import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../migrations/202611040001_conflict_responses.sql',import.meta.url),'utf8'));
  const verification=await db.query(await readFile(new URL('../verify_catalog_inventory.sql',import.meta.url),'utf8'));
  assert.equal(verification.rows.length,9);
  for(const check of verification.rows) assert.equal(check.passed,true,check.check_name);
  const conflicts=await db.query(await readFile(new URL('../verify_conflict_responses.sql',import.meta.url),'utf8'));
  assert.equal(conflicts.rows.length,5);
  for(const check of conflicts.rows) assert.equal(check.passed,true,check.function_name);
  await db.exec(await readFile(new URL('../migrations/202611100001_cash_returns.sql',import.meta.url),'utf8'));
});
after(()=>db.close());
beforeEach(async () => {
  await identity();
  business=randomUUID();otherBusiness=randomUUID();
  await rpc('pos_create_business',{request_id:business,business_name:'Catalog test',branch_name:'Main'});
  branch=await scalar('select id from public.pos_branches where business_id=$1',[business]);
  destination=await rpc('pos_create_branch',{business,request_id:randomUUID(),branch_name:'Second',branch_address:''});
  product=await rpc('pos_add_item',{business,branch,product_name:'Water',product_sku:'WATER',unit_cents:2500,opening_quantity:10});
  await identity(other);
  await rpc('pos_create_business',{request_id:otherBusiness,business_name:'Other',branch_name:'Other'});
  otherBranch=await scalar('select id from public.pos_branches where business_id=$1',[otherBusiness]);
  await identity();
  const code=await rpc('pos_invite_staff',{business,branch,invite_email:'staff@example.test',invite_role:'cashier'});
  await identity(staff);await rpc('pos_accept_invitation',{invite_code:code});await identity();
});

test('upgrading preserves existing stock and receipts and records only a migration snapshot',async()=>{
  const prior=upgradeFixture;
  const receipt=(await db.query('select * from public.pos_cash_sales where id=$1',[prior.sale.id])).rows[0];
  assert.deepEqual(receipt,prior.receipt);
  const rows=await rpc('pos_catalog_items',{business:prior.business,branch:prior.branch});
  assert.equal(rows[0].quantity,8);assert.equal(rows[0].base_name,'Original item');assert.equal(rows[0].stock_version,1);
  const movements=await rpc('pos_stock_history',{business:prior.business,branch:prior.branch,product:prior.product});
  assert.equal(movements.length,1);assert.equal(movements[0].kind,'snapshot');assert.equal(movements[0].after_quantity,8);
  await rpc('pos_sync_cash_sale',{sale:prior.sale});
  const afterRetry=await rpc('pos_catalog_items',{business:prior.business,branch:prior.branch});
  assert.equal(afterRetry[0].quantity,8);
  assert.equal((await rpc('pos_stock_history',{business:prior.business,branch:prior.branch,product:prior.product})).length,1);
});

test('revision conflicts use a non-retryable HTTP conflict without modifying records',async()=>{
  await reject(()=>rpc('pos_update_business',{business,expected_version:0,business_name:'Lost edit',business_address:'',phone_number:'',email_address:'',footer:''}),'PT409');
  await reject(()=>rpc('pos_update_branch',{business,branch,expected_version:0,branch_name:'Lost edit',branch_address:''}),'PT409');
  const brand=await label('brand','Protected brand');
  await reject(()=>label('brand','Lost edit',{label_id:brand.id,expected_version:9}),'PT409');
  await reject(()=>rpc('pos_save_catalog_item',{business,request_id:randomUUID(),item:{id:product,version:9,name:'Lost edit',sku:'WATER',price_cents:2500,active:true}}),'PT409');
  await reject(()=>stock('count',1,{stock_version:9}),'PT409');
  assert.equal((await page())[0].quantity,10);
  assert.equal((await rpc('pos_business_settings',{business})).business.settings_version,1);
});

test('opening stock has an immutable ledger and version; SKU pages preserve existing products',async()=>{
  const items=await page();assert.equal(items.length,1);assert.equal(items[0].quantity,10);assert.equal(items[0].stock_version,1);
  const movements=await history();assert.equal(movements.length,1);assert.equal(movements[0].kind,'opening');
  assert.equal(movements[0].before_quantity,0);assert.equal(movements[0].after_quantity,10);
  await reject(()=>db.query('delete from public.pos_stock_movements'),'42501');
  await reject(()=>db.query('update public.pos_item_stock set quantity=999'),'42501');
});
test('catalog labels are scoped, versioned, archived without deleting references, and retry once',async()=>{
  const id=randomUUID(),request_id=randomUUID();const args={business,request_id,label_id:id,kind:'brand',expected_version:0,label_name:' Acme ',enabled:true};
  const first=await rpc('pos_save_catalog_label',args);assert.deepEqual(await rpc('pos_save_catalog_label',args),first);
  assert.equal((await rpc('pos_catalog_labels',{business})).brands.length,1);
  await reject(()=>rpc('pos_save_catalog_label',{...args,label_name:'Other'}),'22023');
  await label('brand','acme').then(()=>assert.fail('duplicate accepted'),error=>assert.equal(error.code,'23505'));
  assert.equal((await label('brand','Acme',{label_id:id,expected_version:1,enabled:false})).version,2);
  await reject(()=>label('brand','Lost edit',{label_id:id,expected_version:1}),'PT409');
  assert.equal((await rpc('pos_catalog_labels',{business})).brands[0].active,false);
});
test('anonymous, cashier and unrelated owners cannot manage another business inventory',async()=>{
  for(const [actor,role] of [['','anon'],[staff,'authenticated'],[other,'authenticated']]) {
    await identity(actor,role);
    await reject(()=>page(),'42501');await reject(()=>history(),'42501');
    await reject(()=>stock('receive',1),'42501');await reject(()=>label('brand'),'42501');
  }
  await identity(staff);assert.equal((await rpc('pos_catalog_labels',{business})).business_id,business);
  assert.deepEqual((await db.query('select * from public.pos_stock_movements')).rows,[]);
  await identity(other);assert.deepEqual((await db.query('select * from public.pos_brands')).rows,[]);
  await reject(()=>rpc('pos_catalog_labels',{business}),'42501');
  await reject(()=>db.query('select * from fastpas_private.inventory_requests'),'42501');
});
test('receiving is atomic, updates the version, and is idempotent even after another operation',async()=>{
  const id=randomUUID();const first=await stock('receive',5,{},id);assert.equal(first.quantity,15);assert.equal(first.stock_version,2);
  await stock('count',12,{stock_version:2});
  assert.deepEqual(await stock('receive',5,{},id),first);assert.equal((await page())[0].quantity,12);
  await reject(()=>stock('receive',6,{},id),'22023');
  assert.equal((await history()).length,3);
});
test('stale stock counts fail without overwriting a sale; failed cash sales roll back ledger/version',async()=>{
  const sale={id:randomUUID(),business_id:business,branch_id:branch,device_id:randomUUID(),occurred_at:new Date().toISOString(),cash_cents:2500,
    items:[{product_id:product,name:'Water',sku:'WATER',quantity:1,unit_cents:2500}]};
  await rpc('pos_sync_cash_sale',{sale});await rpc('pos_sync_cash_sale',{sale});
  await reject(()=>stock('count',20),'PT409');assert.equal((await page())[0].quantity,9);
  const rows=await history();assert.equal(rows.length,2);assert.equal(rows.find(row=>row.kind==='sale').sale_id,sale.id);
  await reject(()=>rpc('pos_sync_cash_sale',{sale:{...sale,id:randomUUID(),cash_cents:0}}),'22023');
  assert.equal((await history()).length,2);assert.equal((await page())[0].stock_version,2);
});
test('transfers conserve total stock and retry without duplicate movement or deduction',async()=>{
  const id=randomUUID(),extra={destination_id:destination,destination_version:0};
  const first=await stock('transfer',3,extra,id);assert.equal(first.quantity,7);assert.equal(first.destination_quantity,3);
  assert.deepEqual(await stock('transfer',3,extra,id),first);
  assert.equal((await page())[0].quantity+(await page(destination))[0].quantity,10);
  assert.equal((await history()).filter(row=>row.kind==='transfer').length,1);
  const destHistory=await rpc('pos_stock_history',{business,branch:destination,product});assert.equal(destHistory.length,1);assert.equal(destHistory[0].quantity_delta,3);
});
test('failed transfers and invalid counts retain both branch stocks and ledger',async()=>{
  await reject(()=>stock('transfer',11,{destination_id:destination,destination_version:0}),'22023');
  assert.equal((await page())[0].quantity,10);assert.equal((await page(destination))[0].stock_version,0);
  await reject(()=>stock('transfer',1,{destination_id:otherBranch,destination_version:0}),'42501');
  await reject(()=>stock('count',-1),'22023');await reject(()=>stock('receive',0),'22023');
  await reject(()=>stock('count',2,{reason:' '}),'22023');assert.equal((await history()).length,1);
});
test('low-stock thresholds version correctly without inventing a quantity movement',async()=>{
  const result=await stock('threshold',4);assert.equal(result.quantity,10);assert.equal(result.stock_version,2);
  assert.equal((await page())[0].low_stock_threshold,4);assert.equal((await history()).length,1);
  await reject(()=>stock('receive',1),'PT409');
});
test('SKU variants carry full sale names and cannot reference another business classification',async()=>{
  const family=await label('family','T-shirts'),category=await label('category','Clothing');
  const id=randomUUID(),request_id=randomUUID();
  const item={id,version:0,name:'Shirt',sku:'SHIRT-BLUE',price_cents:10000,active:true,brand_id:null,category_id:category.id,
    family_id:family.id,variant_label:'Blue / Large',branch_id:branch,opening_quantity:3};
  const result=await rpc('pos_save_catalog_item',{business,request_id,item});assert.deepEqual(await rpc('pos_save_catalog_item',{business,request_id,item}),result);
  const rows=await page(branch,{search_text:'SHIRT-BLUE'});assert.equal(rows.length,1);assert.equal(rows[0].name,'Shirt · Blue / Large');
  assert.equal(rows[0].quantity,3);assert.equal(rows[0].base_name,'Shirt');
  await reject(()=>rpc('pos_save_catalog_item',{business,request_id:randomUUID(),item:{...item,id:randomUUID(),sku:'DUPLICATE'}}),'23505');
  await identity(other);const foreign=await label('brand','Other',{business:otherBusiness});await identity();
  await reject(()=>rpc('pos_save_catalog_item',{business,request_id:randomUUID(),item:{...item,id:randomUUID(),sku:'INVALID',brand_id:foreign.id}}),'42501');
});
test('catalog edits reject stale versions, archive safely, and retain recorded receipt names',async()=>{
  const args={business,request_id:randomUUID(),item:{id:product,version:1,name:'Renamed water',sku:'WATER',price_cents:3000,active:false,
    brand_id:null,category_id:null,family_id:null,variant_label:''}};
  assert.equal((await rpc('pos_save_catalog_item',args)).version,2);
  assert.deepEqual(await page(),[]);assert.equal((await page(branch,{include_archived:true}))[0].name,'Renamed water');
  await reject(()=>rpc('pos_save_catalog_item',{...args,request_id:randomUUID()}),'PT409');
  assert.equal((await history())[0].product_name,'Water');
  await reject(()=>page(branch,{page_size:101}),'22023');await reject(()=>page(otherBranch),'42501');
});

test('archived classifications can stay on existing products but cannot be newly assigned',async()=>{
  const brand=await label('brand','Original brand');
  const item={id:product,version:1,name:'Water',sku:'WATER',price_cents:2500,active:true,
    brand_id:brand.id,category_id:null,family_id:null,variant_label:''};
  await rpc('pos_save_catalog_item',{business,request_id:randomUUID(),item});
  await label('brand','Original brand',{label_id:brand.id,expected_version:1,enabled:false});
  await rpc('pos_save_catalog_item',{business,request_id:randomUUID(),item:{...item,version:2,price_cents:2600}});
  assert.equal((await page())[0].brand_id,brand.id);
  await reject(()=>rpc('pos_save_catalog_item',{business,request_id:randomUUID(),item:{...item,id:randomUUID(),version:0,sku:'NEW',branch_id:branch,opening_quantity:0}}),'42501');
  assert.equal((await page())[0].price_cents,2600);
});

test('negative stock remains explicit until counted and source shortages cannot be transferred',async()=>{
  const sale={id:randomUUID(),business_id:business,branch_id:branch,device_id:randomUUID(),occurred_at:new Date().toISOString(),cash_cents:30000,
    items:[{product_id:product,name:'Water',sku:'WATER',quantity:12,unit_cents:2500}]};
  await rpc('pos_sync_cash_sale',{sale});
  assert.equal((await page())[0].quantity,-2);
  await reject(()=>stock('transfer',1,{stock_version:2,destination_id:destination,destination_version:0}),'22023');
  assert.equal((await stock('receive',1,{stock_version:2})).quantity,-1);
  assert.equal((await stock('count',4,{stock_version:3,reason:'Physical count after shortage review'})).quantity,4);
  const rows=await history();assert.equal(rows.length,4);
  assert.equal(rows.find(row=>row.kind==='count').before_quantity,-1);
});

const waterLine = () => ({product_id:product,name:'Water',sku:'WATER',quantity:3,unit_cents:2500});
async function syncedSale(items=[waterLine()]) {
  const sale={id:randomUUID(),business_id:business,branch_id:branch,device_id:randomUUID(),
    occurred_at:new Date().toISOString(),cash_cents:items.reduce((sum,item)=>sum+item.quantity*item.unit_cents,0)+10000,items};
  await rpc('pos_sync_cash_sale',{sale});
  return sale.id;
}
const returnScope = sale => ({p_business:business,p_branch:branch,p_sale:sale});
const returnLine = (quantity,restock=true,id=product) => ({product_id:id,quantity,restock});
const returnRequest = (sale,items) => ({...returnScope(sale),p_request:randomUUID(),p_reason:'Customer return',p_items:items});

test('partial returns use the original receipt price and stock only increases for restocked units',async()=>{
  const sale=await syncedSale();
  const original=(await db.query('select * from public.pos_cash_sales where id=$1',[sale])).rows[0];
  await rpc('pos_save_catalog_item',{business,request_id:randomUUID(),
    item:{id:product,version:1,name:'Renamed water',sku:'WATER',price_cents:3000,active:false,
      brand_id:null,category_id:null,family_id:null,variant_label:''}});

  const first=returnRequest(sale,[returnLine(1)]);
  const result=await rpc('pos_record_cash_return',first);
  assert.equal(result.id,first.p_request);
  assert.equal(result.total_cents,2500);
  assert.deepEqual(await rpc('pos_record_cash_return',first),result);
  await reject(()=>rpc('pos_record_cash_return',{...first,p_items:[returnLine(2)]}),'PT409');

  const second=await rpc('pos_record_cash_return',returnRequest(sale,[returnLine(2,false)]));
  assert.equal(second.total_cents,5000);
  assert.deepEqual(await rpc('pos_cash_return_options',returnScope(sale)),[
    {...waterLine(),remaining_quantity:0},
  ]);
  assert.equal((await page(branch,{include_archived:true}))[0].quantity,8);
  const movements=(await history()).filter(row=>row.kind==='return');
  assert.equal(movements.length,1);
  assert.equal(movements[0].quantity_delta,1);
  assert.equal(movements[0].sale_id,sale);
  assert.equal(movements[0].request_id,first.p_request);
  assert.deepEqual((await db.query('select * from public.pos_cash_sales where id=$1',[sale])).rows[0],original);
  await reject(()=>rpc('pos_record_cash_return',returnRequest(sale,[returnLine(1,false)])),'PT409');
});

test('an invalid later return line rolls back the earlier stock movement and leaves the request reusable',async()=>{
  const second=await rpc('pos_add_item',{business,branch,product_name:'Cup',product_sku:'CUP',unit_cents:100,opening_quantity:10});
  const sale=await syncedSale([waterLine(),{product_id:second,name:'Cup',sku:'CUP',quantity:3,unit_cents:100}]);
  const sorted=[product,second].sort();
  const request=returnRequest(sale,[returnLine(1,true,sorted[0]),returnLine(4,true,sorted[1])]);
  await reject(()=>rpc('pos_record_cash_return',request),'PT409');
  assert.deepEqual((await page()).map(row=>row.quantity),[7,7]);
  assert.equal((await history()).filter(row=>row.kind==='return').length,0);
  assert.deepEqual((await rpc('pos_cash_return_options',returnScope(sale))).map(row=>row.remaining_quantity),[3,3]);
  const corrected={...request,p_items:sorted.map(id=>returnLine(1,true,id))};
  const result=await rpc('pos_record_cash_return',corrected);
  assert.equal(result.total_cents,2600);
  assert.deepEqual(await rpc('pos_record_cash_return',{...corrected,p_items:[...corrected.p_items].reverse()}),result);
  assert.deepEqual((await page()).map(row=>row.quantity),[8,8]);
});

test('only owners and managers assigned to the receipt branch can read or record returns',async()=>{
  const sale=await syncedSale();
  const request=returnRequest(sale,[returnLine(1)]);
  for(const [actor,role] of [['','anon'],[staff,'authenticated'],[other,'authenticated']]) {
    await identity(actor,role);
    await reject(()=>rpc('pos_cash_return_options',returnScope(sale)),'42501');
    await reject(()=>rpc('pos_record_cash_return',request),'42501');
  }
  await identity();
  await reject(()=>rpc('pos_record_cash_return',{...request,p_branch:destination}),'22023');
  await reject(()=>rpc('pos_record_cash_return',{...request,p_sale:randomUUID()}),'22023');
  await rpc('pos_change_staff_access',{business,member:staff,new_role:'manager'});
  await identity(staff);
  assert.equal((await rpc('pos_cash_return_options',returnScope(sale)))[0].remaining_quantity,3);
  assert.equal((await rpc('pos_record_cash_return',request)).total_cents,2500);
  await reject(()=>db.query('select * from fastpas_private.cash_returns'),'42501');
  await reject(()=>db.query('delete from fastpas_private.cash_return_lines'),'42501');
  await identity();
  await reject(()=>rpc('pos_record_cash_return',request),'PT409');
  await rpc('pos_set_staff_branches',{business,member:staff,branches:`{${destination}}`});
  await identity(staff);
  await reject(()=>rpc('pos_record_cash_return',request),'42501');
});

test('returns reject invalid quantities, duplicate products, missing disposition and off-receipt products',async()=>{
  const sale=await syncedSale();
  const request=returnRequest(sale,[returnLine(1)]);
  for(const items of [[],[returnLine(1),returnLine(1)],[returnLine(0)],[returnLine(1.5)],[returnLine('1')],
    [{product_id:product,quantity:1}],[returnLine(1,false,randomUUID())]]) {
    await reject(()=>rpc('pos_record_cash_return',{...request,p_items:items}),'22023');
  }
  await reject(()=>rpc('pos_record_cash_return',{...request,p_reason:'\t\n'}),'22023');
  assert.equal((await page())[0].quantity,7);
  assert.equal((await rpc('pos_cash_return_options',returnScope(sale)))[0].remaining_quantity,3);
});
