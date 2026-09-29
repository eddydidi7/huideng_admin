-- One-time owner operation on STAGING first. Replace only the email below.
-- Never provide this file or its execution capability to the Windows client.
begin;
do $$
declare target uuid;
begin
 if exists(select 1 from admin_private.members where role='super_admin' and enabled) then
  raise exception 'A super administrator already exists; use the admin app.';
 end if;
 select id into target from auth.users where lower(email)=lower('eddydidi7@gmail.com');
 if target is null then raise exception 'Create and confirm the owner account first.'; end if;
 insert into admin_private.members(user_id,role) values(target,'super_admin');
 insert into admin_private.audit_logs(actor,action,target) values(target,'members.bootstrap',target::text);
end;
$$;
commit;

