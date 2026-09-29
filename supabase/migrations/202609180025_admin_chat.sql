begin;
create or replace function public.huideng_admin_chat(actor uuid, action text, payload jsonb, request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.chat_rooms; target uuid; before_value jsonb; changed jsonb; answer jsonb; old_request admin_private.requests; n integer;
begin
 if not exists(select 1 from admin_private.members m where m.user_id=actor and m.enabled and m.role='super_admin') then raise exception 'Forbidden' using errcode='42501'; end if;
 if action='chat.list' then
  select jsonb_build_object('items',coalesce(jsonb_agg(x),'[]'::jsonb)) into answer from (
   select c.id,c.title,c.member_limit,c.owner_id,(select count(*) from public.chat_members m where m.room_id=c.id and m.left_at is null) member_count
   from public.chat_rooms c where c.kind='group' and (coalesce(payload->>'query','')='' or strpos(lower(c.title),lower(payload->>'query'))>0)
   order by c.id limit 50 offset greatest(0,coalesce((payload->>'offset')::int,0))) x; return answer;
 end if;
 select * into r from public.chat_rooms where id=(payload->>'room_id')::uuid and kind='group' for update;
 if not found then raise exception 'Group missing' using errcode='22023'; end if;
 if action='chat.members' then
  select jsonb_build_object('items',coalesce(jsonb_agg(x),'[]'::jsonb)) into answer from (
   select m.user_id,p.nickname,p.personal_number::text personal_number from public.chat_members m join public.chat_profiles p on p.user_id=m.user_id
   where m.room_id=r.id and m.left_at is null order by m.user_id limit 100 offset greatest(0,coalesce((payload->>'offset')::int,0))) x; return answer;
 end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||request_id::text,24));
 select * into old_request from admin_private.requests q where q.actor=huideng_admin_chat.actor and q.request_id=huideng_admin_chat.request_id;
 if found then
  if old_request.action<>action or old_request.payload<>payload then raise exception 'Request conflict' using errcode='40001'; end if;
  return old_request.result;
 end if;
 if action='chat.limit' then
  n:=(payload->>'member_limit')::int;
  if n is null or n<0 then raise exception 'Invalid limit' using errcode='22023'; end if;
  if (payload->>'previous_limit')::int is distinct from r.member_limit then raise exception 'Stale limit' using errcode='40001'; end if;
  before_value:=jsonb_build_object('member_limit',r.member_limit);
  update public.chat_rooms set member_limit=n where id=r.id;
  changed:=jsonb_build_object('member_limit',n);
 elsif action='chat.remove' then
  target:=(payload->>'user_id')::uuid;
  if target is null or target=r.owner_id then raise exception 'Cannot remove owner' using errcode='22023'; end if;
  select to_jsonb(m) into before_value from public.chat_members m where m.room_id=r.id and m.user_id=target;
  update public.chat_members set left_at=coalesce(left_at,now()) where room_id=r.id and user_id=target returning to_jsonb(chat_members) into changed;
  if not found then raise exception 'Member missing' using errcode='22023'; end if;
 else raise exception 'Unknown action' using errcode='22023'; end if;
 answer:=jsonb_build_object('ok',true);
 insert into admin_private.audit_logs(actor,action,target,before_data,after_data) values(actor,action,r.id::text,before_value,changed);
 insert into admin_private.requests(actor,request_id,action,payload,result) values(actor,request_id,action,payload,answer);
 return answer;
end $$;
revoke all on function public.huideng_admin_chat(uuid,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.huideng_admin_chat(uuid,text,jsonb,uuid) to service_role;
commit;
