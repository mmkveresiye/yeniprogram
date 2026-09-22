-- =====================================================================
--  Mmk Veresiye Takip Programı - Supabase setup
--  Run this whole file once in: Supabase Dashboard > SQL Editor
-- =====================================================================
--  Design: the browser only ever holds the public "anon" key. The tables
--  are locked down with Row Level Security (no policies = no direct
--  access), and every action goes through SECURITY DEFINER functions
--  that check a session token. Passwords are stored as bcrypt hashes.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tables ---------------------------------------------------

create table if not exists public.admin_users (
  id            uuid primary key default gen_random_uuid(),
  username      text not null unique,
  password_hash text not null,
  created_at    timestamptz not null default now()
);

create table if not exists public.clients (
  id            uuid primary key default gen_random_uuid(),
  username      text not null unique,
  password_hash text not null,
  company_name  text not null,
  is_approved   boolean not null default false,
  created_at    timestamptz not null default now()
);

create table if not exists public.app_sessions (
  token      uuid primary key default gen_random_uuid(),
  role       text not null check (role in ('admin', 'client')),
  user_id    uuid not null,
  expires_at timestamptz not null
);

-- ---------- Lock the tables down -------------------------------------
-- RLS on + no policies => the anon key cannot read or write these tables.

alter table public.admin_users  enable row level security;
alter table public.clients      enable row level security;
alter table public.app_sessions enable row level security;

revoke all on table public.admin_users  from anon, authenticated;
revoke all on table public.clients      from anon, authenticated;
revoke all on table public.app_sessions from anon, authenticated;

-- ---------- Helper (internal) ----------------------------------------

create or replace function public.is_admin_token(p_token uuid)
returns boolean
language sql
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from app_sessions s
    join admin_users a on a.id = s.user_id
    where s.token = p_token and s.role = 'admin' and s.expires_at > now()
  );
$$;

-- ---------- Login / session functions --------------------------------

create or replace function public.app_login(p_username text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  u  text := lower(trim(coalesce(p_username, '')));
  a  admin_users%rowtype;
  c  clients%rowtype;
  t  uuid;
begin
  delete from app_sessions where expires_at < now();

  -- 1) Administrator?
  select * into a from admin_users where username = u;
  if found and a.password_hash = crypt(coalesce(p_password, ''), a.password_hash) then
    insert into app_sessions (role, user_id, expires_at)
    values ('admin', a.id, now() + interval '12 hours')
    returning token into t;
    return jsonb_build_object('ok', true, 'role', 'admin', 'token', t, 'name', a.username);
  end if;

  -- 2) Client?
  select * into c from clients where username = u;
  if found and c.password_hash = crypt(coalesce(p_password, ''), c.password_hash) then
    if not c.is_approved then
      return jsonb_build_object('ok', false, 'error', 'pending');
    end if;
    insert into app_sessions (role, user_id, expires_at)
    values ('client', c.id, now() + interval '12 hours')
    returning token into t;
    return jsonb_build_object('ok', true, 'role', 'client', 'token', t, 'name', c.company_name);
  end if;

  perform pg_sleep(0.5);  -- slows down password guessing a little
  return jsonb_build_object('ok', false, 'error', 'invalid');
end;
$$;

create or replace function public.app_validate(p_token uuid, p_role text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  s  app_sessions%rowtype;
  nm text;
begin
  select * into s from app_sessions
   where token = p_token and role = p_role and expires_at > now();
  if not found then
    return jsonb_build_object('valid', false);
  end if;

  if s.role = 'admin' then
    select username into nm from admin_users where id = s.user_id;
  else
    select company_name into nm from clients where id = s.user_id and is_approved;
  end if;

  if nm is null then
    return jsonb_build_object('valid', false);
  end if;
  return jsonb_build_object('valid', true, 'name', nm);
end;
$$;

create or replace function public.app_logout(p_token uuid)
returns void
language sql
security definer
set search_path = public, extensions
as $$
  delete from app_sessions where token = p_token;
$$;

-- ---------- Admin functions ------------------------------------------

create or replace function public.admin_list_clients(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not is_admin_token(p_token) then raise exception 'unauthorized'; end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    from (select id, username, company_name, is_approved, created_at from clients) x
  );
end;
$$;

create or replace function public.admin_add_client(
  p_token uuid, p_username text, p_password text, p_company text,
  p_approved boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  u text := lower(trim(coalesce(p_username, '')));
begin
  if not is_admin_token(p_token) then raise exception 'unauthorized'; end if;
  if u = '' or trim(coalesce(p_company, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if length(coalesce(p_password, '')) < 6 then
    return jsonb_build_object('ok', false, 'error', 'weak_password');
  end if;

  insert into clients (username, password_hash, company_name, is_approved)
  values (u, crypt(p_password, gen_salt('bf')), trim(p_company), coalesce(p_approved, true));
  return jsonb_build_object('ok', true);
exception when unique_violation then
  return jsonb_build_object('ok', false, 'error', 'exists');
end;
$$;

create or replace function public.admin_set_approval(p_token uuid, p_client_id uuid, p_approved boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not is_admin_token(p_token) then raise exception 'unauthorized'; end if;
  update clients set is_approved = p_approved where id = p_client_id;
  if not p_approved then
    delete from app_sessions where role = 'client' and user_id = p_client_id;  -- kick them out now
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.admin_reset_password(p_token uuid, p_client_id uuid, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not is_admin_token(p_token) then raise exception 'unauthorized'; end if;
  if length(coalesce(p_password, '')) < 6 then
    return jsonb_build_object('ok', false, 'error', 'weak_password');
  end if;
  update clients set password_hash = crypt(p_password, gen_salt('bf')) where id = p_client_id;
  delete from app_sessions where role = 'client' and user_id = p_client_id;
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.admin_delete_client(p_token uuid, p_client_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not is_admin_token(p_token) then raise exception 'unauthorized'; end if;
  delete from app_sessions where role = 'client' and user_id = p_client_id;
  delete from clients where id = p_client_id;
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------- Permissions: only the public RPC entry points ------------

revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.app_login(text, text)                          to anon;
grant execute on function public.app_validate(uuid, text)                       to anon;
grant execute on function public.app_logout(uuid)                               to anon;
grant execute on function public.admin_list_clients(uuid)                       to anon;
grant execute on function public.admin_add_client(uuid, text, text, text, boolean) to anon;
grant execute on function public.admin_set_approval(uuid, uuid, boolean)        to anon;
grant execute on function public.admin_reset_password(uuid, uuid, text)         to anon;
grant execute on function public.admin_delete_client(uuid, uuid)                to anon;

-- ---------- First administrator --------------------------------------
-- !! CHANGE THE PASSWORD BELOW before running, or change it afterwards with:
--    update public.admin_users
--       set password_hash = extensions.crypt('NEW_PASSWORD', extensions.gen_salt('bf'))
--     where username = 'admin';

insert into public.admin_users (username, password_hash)
values ('admin', extensions.crypt('ChangeMe123!', extensions.gen_salt('bf')))
on conflict (username) do nothing;
