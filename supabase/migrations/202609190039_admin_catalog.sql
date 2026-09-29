begin;
create or replace function public.huideng_admin_catalog(actor uuid, action text, payload jsonb, request_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,admin_private as $$
declare member admin_private.members; answer jsonb; skip integer; query text;
begin
 select * into member from admin_private.members m where m.user_id=actor and m.enabled for share;
 if not found or member.role not in ('super_admin','admin','moderator') then raise exception 'Forbidden' using errcode='42501'; end if;
 if action not in ('forum.list','articles.list','users.list') or action is null then raise exception 'Unknown action' using errcode='22023'; end if;
 if member.role='moderator' and action<>'forum.list' then raise exception 'Forbidden' using errcode='42501'; end if;
 skip:=greatest(0,coalesce((payload->>'offset')::integer,0));
 query:=lower(left(coalesce(payload->>'search',''),200));
 if action='users.list' then
  select jsonb_build_object('items',coalesce(jsonb_agg(x),'[]'::jsonb)) into answer from (
   select u.id,u.email,u.created_at,coalesce(u.is_anonymous,false) is_anonymous,
    p.nickname,p.personal_number::text personal_number,
    case when u.banned_until>now() then '已停用' else '正常' end account_status
   from auth.users u left join public.chat_profiles p on p.user_id=u.id
   where query='' or strpos(lower(coalesce(u.email,'')||' '||coalesce(p.nickname,'')||' '||coalesce(p.personal_number::text,'')||' '||u.id::text),query)>0
   order by u.created_at desc,u.id limit 51 offset skip
  ) x;
 else
  select jsonb_build_object('items',coalesce(jsonb_agg(x),'[]'::jsonb)) into answer from (
   select p.id,p.title,p.body,p.author_name,p.author_user_id,p.created_at,p.updated_at,
    p.post_kind,p.category_id,p.visibility,p.access_level,p.like_count,p.reply_count
   from public.forum_posts p
   where p.deleted_at is null and p.access_level in ('public','link_only')
    and (action='forum.list' or p.post_kind='article')
    and (query='' or strpos(lower(coalesce(p.title,'')||' '||coalesce(p.body,'')||' '||coalesce(p.author_name,'')),query)>0)
   order by p.created_at desc,p.id limit 51 offset skip
  ) x;
 end if;
 return answer;
end $$;
revoke all on function public.huideng_admin_catalog(uuid,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.huideng_admin_catalog(uuid,text,jsonb,uuid) to service_role;
notify pgrst,'reload schema';
commit;
