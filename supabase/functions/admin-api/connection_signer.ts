export async function signConnectionManifest(input: { origins: unknown; version: number; days: unknown }, project: string, privateKeyBase64: string, now = new Date()) {
  if (!privateKeyBase64) throw new Error('SIGNING_NOT_CONFIGURED');
  const days=Number(input.days);
  if(!Number.isSafeInteger(input.version)||input.version<1||!Number.isInteger(days)||days<1||days>180||!Array.isArray(input.origins)||input.origins.length<1||input.origins.length>4)throw new Error('INVALID_CONFIG');
  const origins=input.origins.map((value: unknown)=>{
    if(typeof value!=='string')throw new Error('INVALID_ORIGIN');
    const url=new URL(value);
    if(url.protocol!=='https:'||url.username||url.password||url.port||url.search||url.hash||url.pathname!=='/'||url.hostname==='localhost'||!/^[-a-z0-9]+(\.[-a-z0-9]+)+$/.test(url.hostname)||/^\d+(\.\d+){3}$/.test(url.hostname))throw new Error('INVALID_ORIGIN');
    return url.origin;
  });
  if(new Set(origins).size!==origins.length)throw new Error('DUPLICATE_ORIGIN');
  const data={schema:1,project,version:input.version,issued_at:now.toISOString(),expires_at:new Date(now.getTime()+days*86400000).toISOString(),origins};
  const bytes=new TextEncoder().encode(JSON.stringify(data));
  const key=await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(privateKeyBase64),c=>c.charCodeAt(0)),{name:'Ed25519'},false,['sign']);
  const signature=new Uint8Array(await crypto.subtle.sign('Ed25519',key,bytes));
  return {payload:btoa(String.fromCharCode(...bytes)),signature:btoa(String.fromCharCode(...signature))};
}
