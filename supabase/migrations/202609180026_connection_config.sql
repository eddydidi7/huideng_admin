begin;
create table if not exists public.connection_configs (
 id text primary key check(id='global'), version bigint not null default 0,
 envelope jsonb, updated_at timestamptz not null default now()
);
alter table public.connection_configs enable row level security;
revoke all on public.connection_configs from public, anon, authenticated;
grant select,insert,update on public.connection_configs to service_role;
insert into public.connection_configs(id) values('global') on conflict do nothing;
create or replace function public.publish_connection_config(actor uuid, expected_version bigint, signed_envelope jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare current_value public.connection_configs;
begin
 if not exists(select 1 from admin_private.members m where m.user_id=actor and m.enabled and m.role='super_admin') then raise exception 'Forbidden' using errcode='42501'; end if;
 select * into current_value from public.connection_configs where id='global' for update;
 if expected_version is distinct from current_value.version then raise exception 'Version conflict' using errcode='40001'; end if;
 if jsonb_typeof(signed_envelope->'payload') is distinct from 'string' or jsonb_typeof(signed_envelope->'signature') is distinct from 'string' or octet_length(signed_envelope::text)>32768 then raise exception 'Invalid envelope' using errcode='22023'; end if;
 update public.connection_configs set envelope=signed_envelope,version=version+1,updated_at=now() where id='global';
 insert into admin_private.audit_logs(actor,action,target,before_data,after_data) values(actor,'connection.publish','global',to_jsonb(current_value),signed_envelope);
 return jsonb_build_object('version',current_value.version+1,'envelope',signed_envelope);
end $$;
revoke all on function public.publish_connection_config(uuid,bigint,jsonb) from public,anon,authenticated;
grant execute on function public.publish_connection_config(uuid,bigint,jsonb) to service_role;
commit;
