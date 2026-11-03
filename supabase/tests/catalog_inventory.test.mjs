import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const db = new PGlite();
const owner = randomUUID(), other = randomUUID(), staff = randomUUID();
let business, otherBusiness, branch, destination, otherBranch, product;
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
    '202610210003_staff_access.sql','202610240001_staff_branch_access.sql','202610310001_business_settings.sql',
    '202611030001_catalog_inventory.sql']) {
    await db.exec(await readFile(new URL(`../migrations/${file}`,import.meta.url),'utf8'));
  }
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
  await reject(()=>label('brand','Lost edit',{label_id:id,expected_version:1}),'40001');
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
  await reject(()=>stock('count',20),'40001');assert.equal((await page())[0].quantity,9);
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
  await reject(()=>stock('receive',1),'40001');
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
  await reject(()=>rpc('pos_save_catalog_item',{...args,request_id:randomUUID()}),'40001');
  assert.equal((await history())[0].product_name,'Water');
  await reject(()=>page(branch,{page_size:101}),'22023');await reject(()=>page(otherBranch),'42501');
});
