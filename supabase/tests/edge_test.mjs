import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {webcrypto} from 'node:crypto';
import assert from 'node:assert/strict';
const source = fs.readFileSync(new URL('../functions/admin-api/index.ts', import.meta.url),'utf8').replace(/^import .*?;\s*/, '');
let handler, role='super_admin', uploadCount=0, uploadError=null, lastActor;
const objects=new Set();
const bucket={
  async upload(path) { uploadCount++; if(!uploadError) objects.add(path.split('/').pop()); return {error:uploadError}; },
  async list(_owner, options) { return {data:[...objects].filter(n=>n===options.search).map(name=>({name})),error:null}; },
  getPublicUrl(path) { return {data:{publicUrl:'https://example.com/'+path}}; },
};
const client={auth:{async getUser(token) { return token==='valid' ? {data:{user:{id:'owner'}},error:null} : {data:{user:null},error:{}}; }},
  async rpc(_name,args) { lastActor=args.actor; return {data:{role},error:role==='user'?{code:'42501'}:null}; },
  storage:{from(name) { assert.equal(name,'app-public-images'); return bucket; }},
};
vm.runInNewContext(stripTypeScriptTypes(source), {createClient:()=>client, Deno:{env:{get:()=> 'configured'},serve:fn=>handler=fn}, Response,Uint8Array,TextDecoder,atob,crypto:webcrypto});
async function call(action,payload={},token='valid') {
 return handler(new Request('https://example.com',{method:'POST',headers:{Authorization:'Bearer '+token},body:JSON.stringify({action,payload,request_id:'11111111-1111-4111-8111-111111111111'})}));
}
const png=Buffer.from([137,80,78,71,13,10,26,10]).toString('base64');
assert.equal((await call('assets.upload',{base64:png},'expired')).status,401);
for(role of ['user','moderator','admin']) assert.equal((await call('assets.upload',{base64:png})).status,403);
assert.equal(uploadCount,0);
role='super_admin';
assert.equal((await call('assets.upload',{base64:Buffer.from('<svg>unsafe</svg>').toString('base64')})).status,400);
assert.equal((await call('assets.upload',{base64:'!invalid'})).status,400);
assert.equal((await call('assets.upload',{base64:'A'.repeat(2796208)})).status,400);
const first=await call('assets.upload',{base64:png,actor:'attacker'});
assert.equal(first.status,200); const url=(await first.json()).data.url;
assert.equal(lastActor,'owner');
uploadError={statusCode:409};
const retry=await call('assets.upload',{base64:png});
assert.equal(retry.status,200); assert.equal((await retry.json()).data.url,url);
uploadError={statusCode:500};
assert.equal((await call('assets.upload',{base64:png})).status,502);
assert.equal((await call('links.get')).status,200);
assert.equal((await call('arbitrary.sql')).status,400);
console.log('PASS: Edge syntax, authentication, roles, image validation, size limits, idempotent upload, error handling, legacy actions.');
