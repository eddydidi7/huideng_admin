-- LOCAL REVIEW ONLY. Requires existing counter_sync, app_links and app_notices migrations.
-- Do not apply to production before staging role/isolation tests.
begin;
create schema if not exists admin_private;
revoke all on schema admin_private from public, anon, authenticated;
create table admin_private.members (
 user_id uuid primary key references auth.users(id),
 role text not null check(role in ('super_admin','admin','moderator')),
 enabled boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table admin_private.audit_logs (
 id uuid primary key default gen_random_uuid(), actor uuid,
 action text not null, target text, before_data jsonb, after_data jsonb,
 created_at timestamptz not null default now()
);
create table admin_private.requests (
 actor uuid not null, request_id uuid not null, action text not null,
 payload jsonb not null, result jsonb not null,
 created_at timestamptz not null default now(), primary key(actor,request_id)
);
alter table admin_private.members enable row level security;
alter table admin_private.audit_logs enable row level security;
alter table admin_private.requests enable row level security;
revoke all on all tables in schema admin_private from public,anon,authenticated;

alter table public.app_notices
 add column notice_type text not null default 'system' check(notice_type in ('system','practice','article','admin')),
 add column scheduled_at timestamptz,
 add column deleted_at timestamptz,
 add column created_by uuid references auth.users(id),
 add column updated_by uuid references auth.users(id),
 add column version bigint not null default 1;
alter table public.app_links add column version bigint not null default 1;
-- Existing clients read only is_published: keep scheduled/deleted rows false too.
drop policy notices_public_read on public.app_notices;
create policy notices_public_read on public.app_notices for select to anon,authenticated
 using(is_published and deleted_at is null and scheduled_at is null);

create function public.huideng_admin_dispatch(actor uuid, action text, payload jsonb, request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 member admin_private.members%rowtype;
 old_request admin_private.requests%rowtype;
 item public.app_notices%rowtype;
 link public.app_links%rowtype;
 result jsonb; old_data jsonb; changed jsonb;
 target_id uuid; expected bigint; publish_mode text; scheduled timestamptz;
 title_zh text; body_zh text; title_en text; body_en text;
 today timestamptz := date_trunc('day',now() at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai';
 writing boolean := action in ('notices.save','notices.delete','links.save','members.save');
begin
 -- Shared membership lock keeps privilege checks stable for this transaction.
 -- Role changes take an exclusive lock so last-super-admin checks cannot race.
 if action='members.save' then
   perform pg_catalog.pg_advisory_xact_lock(4815162342);
 else
   perform pg_catalog.pg_advisory_xact_lock_shared(4815162342);
 end if;
 select * into member from admin_private.members m where m.user_id=actor and m.enabled;
 if not found then raise exception 'forbidden' using errcode='42501'; end if;
 if action <> 'me' and member.role='moderator' then raise exception 'forbidden' using errcode='42501'; end if;
 if action in ('members.list','members.save','links.save') and member.role <> 'super_admin' then
   raise exception 'forbidden' using errcode='42501';
 end if;
 if writing then
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text || request_id::text,0));
   select * into old_request from admin_private.requests r where r.actor=huideng_admin_dispatch.actor and r.request_id=huideng_admin_dispatch.request_id;
   if found then
     if old_request.action <> action or old_request.payload <> payload then raise exception 'request conflict' using errcode='40001'; end if;
     return old_request.result;
   end if;
 end if;
 case action
 when 'me' then
   select jsonb_build_object('role',member.role,'email',u.email,'id',actor) into result from auth.users u where u.id=actor;
 when 'dashboard' then
   select jsonb_build_object(
    'users',(select count(*)::text from auth.users),
    'new_users',(select count(*)::text from auth.users where created_at>=today),
    'active_counters',(select count(distinct user_id)::text from public.counter_events where occurred_at>=today and occurred_at<today+interval '1 day'),
    'today_count',(select coalesce(sum(delta),0)::text from public.counter_events where occurred_at>=today and occurred_at<today+interval '1 day'),
    'total_count',(select coalesce(sum(delta),0)::text from public.counter_events),
    'notices',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select n.id,n.title_zh,n.is_published,n.scheduled_at from public.app_notices n where n.deleted_at is null order by n.updated_at desc limit 5) x)
   ) into result;
 when 'notices.list' then
   if coalesce((payload->>'offset')::int,0)<0 then raise exception 'invalid offset' using errcode='22023'; end if;
   select jsonb_build_object('items',coalesce(jsonb_agg(x),'[]'::jsonb)) into result from (
     select n.* from public.app_notices n where n.deleted_at is null
      and (coalesce(payload->>'search','')='' or n.title_zh ilike '%'||(payload->>'search')||'%')
     order by updated_at desc,id limit 50 offset coalesce((payload->>'offset')::int,0)
   ) x;
 when 'notices.save' then
   target_id := coalesce((payload->>'id')::uuid, gen_random_uuid());
   select * into item from public.app_notices where id=target_id for update;
   if found then
     if item.deleted_at is not null or item.version is distinct from (payload->>'version')::bigint then raise exception 'stale content' using errcode='40001'; end if;
     old_data := to_jsonb(item);
   elsif payload->>'id' is not null then raise exception 'missing content' using errcode='40001'; end if;
   title_zh := trim(coalesce(payload->>'title_zh',''));
   body_zh := trim(coalesce(payload->>'body_zh',''));
   title_en := coalesce(nullif(trim(payload->>'title_en'),''),title_zh);
   body_en := coalesce(nullif(trim(payload->>'body_en'),''),body_zh);
   publish_mode := payload->>'mode';
   if publish_mode is null or publish_mode not in ('draft','now','scheduled') then raise exception 'invalid mode' using errcode='22023'; end if;
   if title_zh='' or (publish_mode <> 'draft' and body_zh='') then raise exception 'missing content' using errcode='22023'; end if;
   scheduled := case when publish_mode='scheduled' then (payload->>'scheduled_at')::timestamptz else null end;
   if publish_mode='scheduled' and (scheduled is null or scheduled<=now()) then raise exception 'invalid schedule' using errcode='22023'; end if;
   insert into public.app_notices(id,title_zh,title_en,body_zh,body_en,notice_type,is_pinned,is_published,scheduled_at,published_at,created_by,updated_by,version)
   values(target_id,title_zh,title_en,body_zh,body_en,coalesce(payload->>'notice_type','system'),coalesce((payload->>'is_pinned')::boolean,false),publish_mode='now',scheduled,
     case when publish_mode='now' then now() else coalesce(scheduled,now()) end,actor,actor,1)
   on conflict(id) do update set title_zh=excluded.title_zh,title_en=excluded.title_en,body_zh=excluded.body_zh,body_en=excluded.body_en,
     notice_type=excluded.notice_type,is_pinned=excluded.is_pinned,is_published=excluded.is_published,scheduled_at=excluded.scheduled_at,
     published_at=excluded.published_at,updated_by=actor,version=app_notices.version+1
   returning to_jsonb(app_notices.*) into changed;
   result := jsonb_build_object('item',changed);
 when 'notices.delete' then
   target_id := (payload->>'id')::uuid;
   select * into item from public.app_notices where id=target_id for update;
   if not found or item.deleted_at is not null or item.version is distinct from (payload->>'version')::bigint then raise exception 'stale content' using errcode='40001'; end if;
   old_data:=to_jsonb(item);
   update public.app_notices set deleted_at=now(),is_published=false,scheduled_at=null,updated_by=actor,version=version+1 where id=target_id returning to_jsonb(app_notices.*) into changed;
   result := jsonb_build_object('deleted',true);
 when 'links.get' then
   select jsonb_build_object('item',to_jsonb(l)) into result from public.app_links l where id='global';
 when 'links.save' then
   select * into link from public.app_links where id='global' for update;
   if not found or link.version is distinct from (payload->>'version')::bigint then raise exception 'stale content' using errcode='40001'; end if;
   old_data:=to_jsonb(link);
   update public.app_links set calendar_url=payload->>'calendar_url',forum_url=payload->>'forum_url',version=version+1 where id='global' returning to_jsonb(app_links.*) into changed;
   result:=jsonb_build_object('item',changed);
 when 'members.list' then
   select jsonb_build_object('items',coalesce(jsonb_agg(x),'[]'::jsonb)) into result from (
    select m.user_id,m.role,m.enabled,m.updated_at,u.email from admin_private.members m join auth.users u on u.id=m.user_id order by m.created_at limit 100
   ) x;
 when 'members.save' then
   select id into target_id from auth.users where lower(email)=lower(trim(payload->>'email'));
   if target_id is null then raise exception 'account not found' using errcode='22023'; end if;
   select to_jsonb(m) into old_data from admin_private.members m where user_id=target_id;
   if old_data is not null and old_data->>'updated_at' is distinct from payload->>'updated_at' then raise exception 'stale member' using errcode='40001'; end if;
   if target_id=actor then raise exception 'cannot change own role here' using errcode='42501'; end if;
   if old_data->>'role'='super_admin' and (old_data->>'enabled')::boolean and
      (payload->>'role'<>'super_admin' or not (payload->>'enabled')::boolean) and
      (select count(*) from admin_private.members where role='super_admin' and enabled)<=1 then raise exception 'last administrator' using errcode='42501'; end if;
   insert into admin_private.members(user_id,role,enabled) values(target_id,payload->>'role',(payload->>'enabled')::boolean)
    on conflict(user_id) do update set role=excluded.role,enabled=excluded.enabled,updated_at=now()
    returning to_jsonb(members.*) into changed;
   result:=jsonb_build_object('saved',true);
 else raise exception 'unknown action' using errcode='22023';
 end case;
 if writing then
   insert into admin_private.audit_logs(actor,action,target,before_data,after_data) values(actor,action,coalesce(target_id::text,'global'),old_data,changed);
   insert into admin_private.requests(actor,request_id,action,payload,result) values(actor,request_id,action,payload,result);
 end if;
 return coalesce(result,'{}'::jsonb);
end;
$$;
revoke all on function public.huideng_admin_dispatch(uuid,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.huideng_admin_dispatch(uuid,text,jsonb,uuid) to service_role;

create function public.huideng_publish_due_notices() returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer; item record;
begin
 n:=0;
 for item in select * from public.app_notices where deleted_at is null and not is_published and scheduled_at<=now() for update skip locked loop
   update public.app_notices set is_published=true,published_at=scheduled_at,scheduled_at=null,version=version+1 where id=item.id;
   insert into admin_private.audit_logs(action,target,before_data,after_data) values('notices.scheduled_publish',item.id::text,to_jsonb(item),jsonb_build_object('is_published',true));
   n:=n+1;
 end loop;
 return n;
end;
$$;
revoke all on function public.huideng_publish_due_notices() from public,anon,authenticated;
grant execute on function public.huideng_publish_due_notices() to service_role;
commit;
