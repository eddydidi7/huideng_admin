import { signConnectionManifest } from "./connection_signer.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const actions = new Set(["releases.list", "releases.save", "releases.notify", "usage.list", "usage.detail", "usage.save", "usage.warn", "usage.hide", "usage.ban", "resources.list", "resources.settings", "resources.delete", "jieyuan.get", "jieyuan.save", "jieyuan.level", "jieyuan.moderate", "me", "dashboard", "forum.list", "articles.list", "users.list", "notices.list", "notices.save", "notices.delete", "links.get", "links.save", "members.list", "members.save", "assets.upload", "chat.list", "chat.members", "chat.limit", "chat.remove", "connection.get", "connection.publish"]);
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), {status, headers: {"Content-Type": "application/json", "Cache-Control": "no-store"}});
for (const action of ['catalog', 'get', 'states', 'audit', 'freeze', 'restore']) actions.add(`permissions.${action}`);
// huideng_admin_broadcast (huideng_counter repo, 202609290076_admin_broadcast.sql).
for (const action of ['send', 'list', 'detail', 'levels.get', 'levels.set']) actions.add(`broadcast.${action}`);
Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, {ok: false});
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return reply(401, {ok: false});
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return reply(503, {ok: false});
  const client = createClient(url, key, {auth: {persistSession: false, autoRefreshToken: false}});
  const {data: identity, error: authError} = await client.auth.getUser(auth.slice(7));
  if (authError || !identity.user) return reply(401, {ok: false});
  try {
    // Bound the body before parsing; never accept caller-supplied SQL or actor IDs.
    const reader = req.body?.getReader();
    if (!reader) return reply(400, {ok: false});
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const {value, done} = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 3_000_000) { await reader.cancel(); return reply(413, {ok: false}); }
      chunks.push(value);
    }
    const buffer = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { buffer.set(chunk, offset); offset += chunk.length; }
    const input = JSON.parse(new TextDecoder().decode(buffer));
    if (!actions.has(input.action) || !input.payload || Array.isArray(input.payload) || typeof input.payload !== 'object' ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input.request_id ?? '')) return reply(400, {ok: false});
    if (input.action.startsWith('permissions.')) {
      const action = input.action.slice('permissions.'.length);
      const {data, error} = await client.rpc('admin_feature_permissions', {
        p_actor: identity.user.id, p_action: action,
        p_data: {...input.payload, request_id: input.request_id},
      });
      if (error) {
        const code = String(error.message);
        const status = code === 'FORBIDDEN' ? 403
          : ['VERSION_CONFLICT', 'REQUEST_CONFLICT'].includes(code) ? 409
          : error.code === 'PGRST202' ? 503 : 400;
        return reply(status, {ok: false});
      }
      return reply(200, {ok: true, data: action === 'audit' ? {items: data} : data});
    }
    if (input.action.startsWith('broadcast.')) {
      const action = input.action.slice('broadcast.'.length);
      const {data, error} = await client.rpc('huideng_admin_broadcast', {
        actor: identity.user.id, action, payload: input.payload, request_id: input.request_id,
      });
      if (error) {
        const status = error.code === '42501' ? 403
          : error.code === '40001' ? 409
          : ['22023','22P02','23514','22007','22008','23503'].includes(error.code) ? 400 : 500;
        return reply(status, {ok: false});
      }
      return reply(200, {ok: true, data});
    }
    if(input.action.startsWith('usage.')) {
      const {data,error}=await client.rpc('huideng_admin_usage',{actor:identity.user.id,action:input.action,payload:input.payload,request_id:input.request_id});
      if(error){const code=String(error.message);return reply(code==='FORBIDDEN'?403:code==='CONFIG_CONFLICT'?409:400,{ok:false,error:['FORBIDDEN','CONFIG_CONFLICT','DOWNLOAD_USAGE_UNAVAILABLE','CANNOT_BAN_SELF','USER_NOT_FOUND'].includes(code)?code:'INVALID_REQUEST'});}
      return reply(200,{ok:true,data});
    }
    if(input.action.startsWith('resources.')) {
      const invoke=async(action:string,payload:Record<string,unknown>={})=>{
        const {data,error}=await client.rpc('public_resources_service_v1',{p_actor:identity.user.id,p_action:action,p_data:payload});
        if(error)throw error;return data;
      };
      try {
        if(input.action!=='resources.list')await invoke('admin.'+input.action.slice('resources.'.length),input.payload);
        // Only queued deletions are eligible, after any active upload lease ends.
        const pending=await invoke('admin.cleanup');
        for(const file of pending.files){
          const {error}=await client.storage.from('public-resources').remove([file.object_key]);
          if(!error)await invoke('admin.purged',{id:file.id});
        }
        // Deferred chat attachment retirement. RPC checks every known resource
        // reference and blocks new references before issuing a Storage delete.
        const {data: retired, error: retirementError} = await client.rpc('huideng_chat_cleanup', {actor: identity.user.id, p_action:'claim', p_data:{}});
        if (!retirementError) for (const file of retired?.files ?? []) {
          if (!['chat-files','chat-voice'].includes(file.bucket)) continue;
          const {error: removalError} = await client.storage.from(file.bucket).remove([file.object_key]);
          if (!removalError) await client.rpc('huideng_chat_cleanup', {actor:identity.user.id,p_action:'completed',p_data:file});
        }
        return reply(200,{ok:true,data:input.action==='resources.list'?await invoke('admin.list',input.payload):{saved:true}});
      }catch(error){
        const code=String((error as {message?:string}).message??'');
        return reply(code==='FORBIDDEN'?403:code==='CONFIG_CONFLICT'?409:400,{ok:false});
      }
    }
    if (input.action.startsWith('connection.')) {
      const {data: member,error: denied}=await client.rpc('huideng_admin_dispatch',{actor:identity.user.id,action:'me',payload:{},request_id:input.request_id});
      if(denied||member?.role!=='super_admin')return reply(403,{ok:false});
      const {data: current,error: missing}=await client.from('connection_configs').select('version,envelope').eq('id','global').single();
      if(missing)return reply(503,{ok:false});
      if(input.action==='connection.get')return reply(200,{ok:true,data:{...current,signing_ready:!!Deno.env.get('CONNECTION_SIGNING_PRIVATE_KEY')}});
      if(input.payload.version!==current.version)return reply(409,{ok:false});
      const secret=Deno.env.get('CONNECTION_SIGNING_PRIVATE_KEY');
      if(!secret)return reply(503,{ok:false});
      const envelope=await signConnectionManifest({origins:input.payload.origins,version:current.version+1,days:input.payload.days},url,secret);
      const {data,error}=await client.rpc('publish_connection_config',{actor:identity.user.id,expected_version:current.version,signed_envelope:envelope});
      if(error)return reply(error.code==='40001'?409:500,{ok:false});
      return reply(200,{ok:true,data});
    }
    if (input.action === 'assets.upload') {
      const {data: member, error: denied} = await client.rpc('huideng_admin_dispatch', {
        actor: identity.user.id, action: 'me', payload: {}, request_id: input.request_id,
      });
      if (denied || member?.role !== 'super_admin') return reply(403, {ok: false});
      const encoded = input.payload.base64;
      if (typeof encoded !== 'string' || encoded.length > 2796204) return reply(400, {ok: false});
      const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
      if (!bytes.length || bytes.length > 2097152) return reply(400, {ok: false});
      const png = bytes.length >= 8 && [137,80,78,71,13,10,26,10].every((b,i)=>bytes[i]===b);
      const jpg = bytes.length >= 3 && bytes[0]===255 && bytes[1]===216 && bytes[2]===255;
      const webp = bytes.length >= 12 && new TextDecoder().decode(bytes.slice(0,4))==='RIFF' && new TextDecoder().decode(bytes.slice(8,12))==='WEBP';
      const ext = png ? 'png' : jpg ? 'jpg' : webp ? 'webp' : null;
      if (!ext) return reply(400, {ok: false});
      const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))).map(b=>b.toString(16).padStart(2,'0')).join('');
      const path = `${identity.user.id}/${hash}.${ext}`;
      const bucket = client.storage.from('app-public-images');
      const {error: uploadError} = await bucket.upload(path, bytes, {contentType: png ? 'image/png' : jpg ? 'image/jpeg' : 'image/webp', upsert: false});
      if (uploadError && !['409','400'].includes(String(uploadError.statusCode))) return reply(502, {ok: false});
      // A content-addressed path can only contain this image. Confirm an existing object on retry.
      if (uploadError) {
        const {data: existing, error: missing} = await bucket.list(identity.user.id, {search: `${hash}.${ext}`, limit: 1});
        if (missing || !existing?.some(o=>o.name===`${hash}.${ext}`)) return reply(502, {ok: false});
      }
      return reply(200, {ok: true, data: {url: bucket.getPublicUrl(path).data.publicUrl}});
    }
    const {data, error} = await client.rpc(input.action.startsWith("releases.") ? "huideng_admin_releases" : input.action.startsWith("jieyuan.") ? "huideng_admin_jieyuan" : ["forum.list", "articles.list", "users.list"].includes(input.action) ? "huideng_admin_catalog" : input.action.startsWith("chat.") ? "huideng_admin_chat" : "huideng_admin_dispatch", {
      actor: identity.user.id, action: input.action, payload: input.payload, request_id: input.request_id,
    });
    if (error) {
      const status = error.code === '42501' ? 403 : error.code === '40001' ? 409 :
        ['22023','22P02','23514','22007','22008','23503'].includes(error.code) ? 400 : 500;
      return reply(status, {ok: false});
    }
    return reply(200, {ok: true, data});
  } catch (_) { return reply(400, {ok: false}); }
});


