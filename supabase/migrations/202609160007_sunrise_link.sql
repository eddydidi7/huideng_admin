-- Additive update. Existing link values, permissions and audit protocol are kept.
begin;
alter table public.app_links add column sunrise_url text not null
 default 'https://www.daysfromdate.com/zh-cn/sunrise/cn?utm_source=chatgpt.com'
 constraint app_links_sunrise_https check (
 sunrise_url ~ '^https://[^/@[:space:]]+([/?#][^[:space:]]*)?$'
 and length(sunrise_url)<=2048);
comment on column public.app_links.sunrise_url is '日出栏打开的 HTTPS 网页；仅超级管理员通过安全 API 修改';
-- Change only the links.save assignment, retaining all deployed role, lock,
-- audit, idempotency and version checks. Fail closed if its shape has changed.
do $migration$
declare definition text;
 old_assignment text := 'forum_url=payload->>''forum_url'',version=version+1';
 new_assignment text := 'forum_url=payload->>''forum_url'',sunrise_url=case when payload ? ''sunrise_url'' then payload->>''sunrise_url'' else link.sunrise_url end,version=version+1';
begin
 definition := pg_get_functiondef('public.huideng_admin_dispatch(uuid,text,jsonb,uuid)'::regprocedure);
 if strpos(definition,old_assignment)=0 then
   raise exception 'Admin function differs; review before applying sunrise update';
 end if;
 execute replace(definition,old_assignment,new_assignment);
end $migration$;
commit;
