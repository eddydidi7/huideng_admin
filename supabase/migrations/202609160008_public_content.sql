-- Public app content only; never touches private notes or count records.
begin;
create function public.huideng_valid_about(v jsonb) returns boolean
language sql immutable set search_path=pg_catalog as $$
 select coalesce(jsonb_typeof(v)='object'
 and jsonb_typeof(v->'email')='string' and length(v->>'email')<=254
 and jsonb_typeof(v->'qq')='string' and length(v->>'qq')<=40
 and jsonb_typeof(v->'text_zh')='string' and length(v->>'text_zh')<=20000
 and jsonb_typeof(v->'text_en')='string' and length(v->>'text_en')<=20000
 and jsonb_typeof(v->'images')='array'
 and case when jsonb_typeof(v->'images')='array' then
   jsonb_array_length(v->'images')<=8 and not exists (
     select 1 from jsonb_array_elements(v->'images') x where
       jsonb_typeof(x)<>'string' or length(x#>>'{}')>2048
       or (x#>>'{}') !~ '^https://[^/@[:space:]]+([/?#][^[:space:]]*)?$')
 else false end, false)
$$;
create function public.huideng_valid_public_notes(v jsonb) returns boolean
language sql immutable set search_path=pg_catalog as $$
 select case when jsonb_typeof(v)='array' then
 jsonb_array_length(v)<=100 and octet_length(v::text)<=1200000 and not exists (
   select 1 from jsonb_array_elements(v) n where jsonb_typeof(n)<>'object'
   or coalesce(n->>'id','') !~ '^[0-9a-fA-F-]{36}$'
   or jsonb_typeof(n->'body') is distinct from 'string'
   or length(coalesce(n->>'body','')) not between 1 and 10000
   or jsonb_typeof(n->'updated_at') is distinct from 'string'
   or jsonb_typeof(n->'created_at') is distinct from 'string')
 and (select count(*)=count(distinct n->>'id') from jsonb_array_elements(v) n)
 else false end
$$;
alter table public.app_links
 add column offering_url text not null default '' check(offering_url='' or
   (offering_url ~ '^https://[^/@[:space:]]+([/?#][^[:space:]]*)?$' and length(offering_url)<=2048)),
 add column about_content jsonb not null default '{"email":"eddydid@gmail.com","qq":"79576743","text_zh":"","text_en":"","images":[]}'
   check(public.huideng_valid_about(about_content)),
 add column published_notes jsonb not null default '[]' check(public.huideng_valid_public_notes(published_notes));
do $migration$
declare definition text;
 old_assignment text := 'else link.sunrise_url end,version=version+1';
 new_assignment text := 'else link.sunrise_url end,offering_url=case when payload ? ''offering_url'' then payload->>''offering_url'' else link.offering_url end,about_content=case when payload ? ''about_content'' then payload->''about_content'' else link.about_content end,published_notes=case when payload ? ''published_notes'' then payload->''published_notes'' else link.published_notes end,version=version+1';
begin
 definition:=pg_get_functiondef('public.huideng_admin_dispatch(uuid,text,jsonb,uuid)'::regprocedure);
 if strpos(definition,old_assignment)=0 then raise exception 'Admin function differs; review first'; end if;
 execute replace(definition,old_assignment,new_assignment);
end $migration$;
-- Public images are uploaded only by the admin Edge Function, not by clients.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('app-public-images','app-public-images',true,2097152,array['image/png','image/jpeg','image/webp'])
 on conflict(id) do nothing;
commit;
