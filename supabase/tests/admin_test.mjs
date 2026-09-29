process.on('unhandledRejection', e => {console.error(e.code,e.message,e.internalQuery??'');process.exit(1);});
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const {PGlite}=await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const adminRoot=fileURLToPath(new URL('../..',import.meta.url));
const clientRoot=path.resolve(adminRoot,'../huideng_counter');
import fs from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth; create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table auth.users(id uuid primary key,email text,created_at timestamptz default now());
 create table public.counter_events(user_id uuid,delta bigint,occurred_at timestamptz);
 insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-000000000001','super@example.com'),
 ('00000000-0000-4000-8000-000000000002','admin@example.com'),
 ('00000000-0000-4000-8000-000000000003','mod@example.com'),
 ('00000000-0000-4000-8000-000000000004','user@example.com');`);
for(const name of ['202609150003_app_links.sql','202609150004_app_notices.sql'])await db.exec(fs.readFileSync(path.join(clientRoot,'supabase/migrations',name),'utf8'));
await db.exec(fs.readFileSync(path.join(adminRoot,'supabase/migrations/202609150005_admin_phase1.sql'),'utf8'));
await db.exec(fs.readFileSync(path.join(adminRoot,'supabase/migrations/202609160007_sunrise_link.sql'),'utf8'));
await db.exec(fs.readFileSync(path.join(adminRoot,'supabase/migrations/202609160008_public_content.sql'),'utf8'));
await db.exec(`insert into admin_private.members(user_id,role) values
 ('00000000-0000-4000-8000-000000000001','super_admin'),
 ('00000000-0000-4000-8000-000000000002','admin'),
 ('00000000-0000-4000-8000-000000000003','moderator');`);
const ids=['','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000004'];
let seq=0;
async function call(user,action,payload={},request){return (await db.query('select public.huideng_admin_dispatch($1,$2,$3,$4) as result',[ids[user],action,JSON.stringify(payload),request??`11111111-1111-4111-8111-${String(++seq).padStart(12,'0')}`])).rows[0].result;}
async function rejects(fn,code){try{await fn();assert.fail('expected refusal');}catch(e){assert.equal(e.code,code);}}
await rejects(()=>call(4,'me'),'42501');
await rejects(()=>call(3,'notices.list'),'42501');
assert.equal((await call(3,'me')).role,'moderator');
assert.equal((await call(1,'dashboard')).users,'4');
const payload={title_zh:'测试',body_zh:'正文',mode:'draft',notice_type:'system'};
const request='22222222-1111-4111-8111-000000000001';
const draft=(await call(2,'notices.save',payload,request)).item;
assert.equal((await call(2,'notices.save',payload,request)).item.id,draft.id);
await rejects(()=>call(2,'notices.save',{...payload,title_zh:'不同'},request),'40001');
assert.equal((await call(2,'notices.list')).items.length,1);
await db.exec('set role anon');
assert.equal((await db.query('select * from public.app_notices')).rows.length,0);
await rejects(()=>db.query("select public.huideng_admin_dispatch($1,'me','{}',gen_random_uuid())",[ids[1]]),'42501');
await db.exec('reset role');
const published=(await call(2,'notices.save',{...payload,id:draft.id,version:draft.version,mode:'now'})).item;
await rejects(()=>call(2,'notices.save',{...payload,id:draft.id,version:draft.version}),'40001');
await db.exec('set role anon');assert.equal((await db.query('select * from public.app_notices')).rows.length,1);await db.exec('reset role');
await call(2,'notices.delete',{id:published.id,version:published.version});
assert.equal((await call(2,'notices.list')).items.length,0);
await rejects(()=>call(2,'links.save',{version:1,calendar_url:'https://example.com',forum_url:'https://example.com'}),'42501');
const links=(await call(1,'links.get')).item;
await call(1,'links.save',{version:links.version,calendar_url:'https://example.com',forum_url:'https://example.com'});
await rejects(()=>call(1,'links.save',{version:links.version,calendar_url:'https://example.com',forum_url:'https://example.com'}),'40001');
let solarLinks=(await call(1,'links.get')).item;
assert.equal(solarLinks.sunrise_url,'https://www.daysfromdate.com/zh-cn/sunrise/cn?utm_source=chatgpt.com');
for(const bad of ['http://example.com','javascript:alert(1)','https://user:pass@example.com','https://example.com/ bad']) {
 await rejects(()=>call(1,'links.save',{...solarLinks,sunrise_url:bad}),'23514');
}
await rejects(()=>call(4,'links.save',{...solarLinks,sunrise_url:'https://example.com/sun'}),'42501');
await call(1,'links.save',{...solarLinks,sunrise_url:'https://example.com/sun'});
assert.equal((await call(1,'links.get')).item.sunrise_url,'https://example.com/sun');
await db.exec('set role anon');
assert.equal((await db.query("select sunrise_url from public.app_links where id='global'")).rows[0].sunrise_url,'https://example.com/sun');
await rejects(()=>db.query("update public.app_links set sunrise_url='https://bad.example'"),'42501');
await db.exec('reset role');
const base=(await call(1,'links.get')).item;
const publicNote={id:'44444444-1111-4111-8111-000000000001',body:'公开正文',created_at:new Date().toISOString(),updated_at:new Date().toISOString()};
await call(1,'links.save',{...base,offering_url:'https://example.com/offering',published_notes:[publicNote],about_content:{email:'contact@example.com',qq:'123',text_zh:'介绍',text_en:'About',images:['https://example.com/a.png']}});
const extended=(await call(1,'links.get')).item;
await rejects(()=>call(3,'links.save',{...extended,published_notes:[]}),'42501');
await rejects(()=>call(1,'links.save',{...extended,published_notes:[publicNote,publicNote]}),'23514');
await rejects(()=>call(1,'links.save',{...extended,about_content:{...extended.about_content,images:['javascript:alert(1)']}}),'23514');
await call(1,'links.save',{version:extended.version,calendar_url:extended.calendar_url,forum_url:extended.forum_url});
const preserved=(await call(1,'links.get')).item;
assert.deepEqual(preserved.published_notes,[publicNote]); assert.deepEqual(preserved.about_content,extended.about_content); assert.equal(preserved.offering_url,extended.offering_url);
await db.exec('set role anon'); assert.equal((await db.query('select published_notes from public.app_links')).rows[0].published_notes[0].body,'公开正文'); await db.exec('reset role');
console.log('PASS: public notes isolation, validation, roles, legacy settings preservation and public reading.');
const scheduled=(await call(2,'notices.save',{...payload,mode:'scheduled',scheduled_at:new Date(Date.now()+86400000).toISOString()})).item;
assert.equal(scheduled.is_published,false);
await db.query("update public.app_notices set scheduled_at=now()-interval '1 minute' where id=$1",[scheduled.id]);
assert.equal((await db.query('select public.huideng_publish_due_notices() as n')).rows[0].n,1);
assert.equal((await db.query('select public.huideng_publish_due_notices() as n')).rows[0].n,0);
await call(1,'members.save',{email:'user@example.com',role:'admin',enabled:true});
assert.equal((await call(4,'me')).role,'admin');
await rejects(()=>call(2,'members.save',{email:'mod@example.com',role:'super_admin',enabled:true}),'42501');
await rejects(()=>call(1,'members.save',{email:'super@example.com',role:'admin',enabled:true}),'40001');
assert.ok((await db.query('select count(*)::int as n from admin_private.audit_logs')).rows[0].n>=5);
await db.query('update admin_private.members set enabled=false where user_id=$1',[ids[2]]);
await rejects(()=>call(2,'notices.list'),'42501');
console.log('PASS: migrations, ordinary-user denial, role checks, drafts, publication, idempotency, stale-write rejection, soft delete, scheduling, links and membership.');
await db.close();
