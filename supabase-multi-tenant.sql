-- =====================================================================
--  Mmk Veresiye Takip Programı - ÇOKLU MÜŞTERİ (multi-tenant) katmanı
--  Run this AFTER supabase-setup.sql, once, in the SAME Supabase project.
-- =====================================================================
--  What this does:
--   - Adds a client_id column to your 5 ledger tables (cariler, hareketler,
--     toptanciler, toptanci_hareketleri, urunler) so every business you
--     sell the program to gets its own isolated data, in the same tables,
--     under the one Supabase project you already have.
--   - Locks those tables down with RLS so the anon key can no longer read
--     or write them directly (today it can - anyone with the HTML file
--     can read your apikey and pull every business's data with it).
--   - Adds 4 RPC functions (tenant_get/post/patch/delete) that the app
--     calls instead of hitting the tables directly. They check the
--     logged-in client's session token and silently scope every query to
--     that client's own rows - the front-end code barely changes.
--
--  !! BEFORE RUNNING ON A PROJECT WITH REAL DATA:
--     Existing rows will have client_id = NULL, which is invalid once the
--     NOT NULL constraint below is applied. Either:
--       a) this data is just your own test/demo data -> delete it first, or
--       b) it belongs to a specific client -> run, after adding that
--          client in admin.html, a one-time:
--            update cariler set client_id = 'THEIR-CLIENT-UUID' where client_id is null;
--          (repeat for the other 4 tables) before adding the NOT NULL
--          constraints, or simply leave the columns nullable for now.
-- =====================================================================

-- ---------- 1) Add client_id to the ledger tables ---------------------
-- (CREATE TABLE IF NOT EXISTS covers a fresh project; ADD COLUMN covers
--  a project where these tables already exist from your current app.)

create table if not exists public.cariler (
  kod integer not null,
  unvan text not null,
  bakiye numeric not null default 0
);
create table if not exists public.hareketler (
  id bigserial primary key,
  cari_kod integer not null,
  tarih date not null,
  aciklama text,
  borc numeric not null default 0,
  tahsilat numeric not null default 0
);
create table if not exists public.toptanciler (
  kod integer not null,
  unvan text not null,
  bakiye numeric not null default 0
);
create table if not exists public.toptanci_hareketleri (
  id bigserial primary key,
  toptanci_kod integer not null,
  tarih date not null,
  aciklama text,
  borc numeric not null default 0,
  tahsilat numeric not null default 0
);
create table if not exists public.urunler (
  kod integer not null,
  ad text not null,
  barkod text,
  fiyat numeric not null default 0,
  kategori text
);

alter table public.cariler               add column if not exists client_id uuid references public.clients(id);
alter table public.hareketler             add column if not exists client_id uuid references public.clients(id);
alter table public.toptanciler            add column if not exists client_id uuid references public.clients(id);
alter table public.toptanci_hareketleri   add column if not exists client_id uuid references public.clients(id);
alter table public.urunler                add column if not exists client_id uuid references public.clients(id);

-- kod is only unique WITHIN a client now, not across the whole table
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'cariler_client_kod_uq') then
    alter table public.cariler add constraint cariler_client_kod_uq unique (client_id, kod);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'toptanciler_client_kod_uq') then
    alter table public.toptanciler add constraint toptanciler_client_kod_uq unique (client_id, kod);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'urunler_client_kod_uq') then
    alter table public.urunler add constraint urunler_client_kod_uq unique (client_id, kod);
  end if;
end $$;

create index if not exists hareketler_client_idx on public.hareketler(client_id);
create index if not exists toptanci_hareketleri_client_idx on public.toptanci_hareketleri(client_id);

-- ---------- 2) Lock the tables down ------------------------------------

alter table public.cariler               enable row level security;
alter table public.hareketler            enable row level security;
alter table public.toptanciler           enable row level security;
alter table public.toptanci_hareketleri  enable row level security;
alter table public.urunler               enable row level security;

revoke all on table public.cariler               from anon, authenticated;
revoke all on table public.hareketler            from anon, authenticated;
revoke all on table public.toptanciler           from anon, authenticated;
revoke all on table public.toptanci_hareketleri  from anon, authenticated;
revoke all on table public.urunler               from anon, authenticated;

-- ---------- 3) Helpers used only by the RPCs below --------------------

create or replace function public.tenant_table_ok(p_table text)
returns boolean language sql immutable as $$
  select p_table = any(array['cariler','hareketler','toptanciler','toptanci_hareketleri','urunler']);
$$;

create or replace function public.tenant_col_ok(p_table text, p_col text)
returns boolean language sql immutable as $$
  select p_col = any(
    case p_table
      when 'cariler'               then array['kod','unvan','bakiye','client_id']
      when 'hareketler'            then array['id','cari_kod','tarih','aciklama','borc','tahsilat','client_id']
      when 'toptanciler'           then array['kod','unvan','bakiye','client_id']
      when 'toptanci_hareketleri'  then array['id','toptanci_kod','tarih','aciklama','borc','tahsilat','client_id']
      when 'urunler'                then array['kod','ad','barkod','fiyat','kategori','client_id']
      else array[]::text[]
    end
  );
$$;

-- Resolves the logged-in client's id from their session token, or raises.
create or replace function public.tenant_client_id(p_token uuid)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare cid uuid;
begin
  select s.user_id into cid
    from app_sessions s join clients c on c.id = s.user_id
   where s.token = p_token and s.role = 'client' and s.expires_at > now() and c.is_approved;
  if cid is null then raise exception 'unauthorized'; end if;
  return cid;
end;
$$;

-- Turns a PostgREST-style query string ("col=eq.5&col2=in.(1,2)") into a
-- safe SQL WHERE fragment. Only whitelisted columns/operators are allowed.
create or replace function public.tenant_build_where(p_table text, p_query text)
returns text
language plpgsql
as $$
declare
  pair text; k text; v text; clause text := '';
  inner_txt text; items text[]; quoted text[]; item text;
begin
  if p_query is null or p_query = '' then return ''; end if;
  foreach pair in array string_to_array(p_query, '&') loop
    if pair = '' then continue; end if;
    k := split_part(pair, '=', 1);
    v := split_part(pair, '=', 2);
    if k in ('order','select','limit','offset') then continue; end if;
    if not tenant_col_ok(p_table, k) then raise exception 'bad column %', k; end if;
    if v like 'eq.%' then
      clause := clause || format(' and %I = %L', k, substring(v from 4));
    elsif v like 'neq.%' then
      clause := clause || format(' and %I <> %L', k, substring(v from 5));
    elsif v like 'gte.%' then
      clause := clause || format(' and %I >= %L', k, substring(v from 5));
    elsif v like 'lte.%' then
      clause := clause || format(' and %I <= %L', k, substring(v from 5));
    elsif v like 'gt.%' then
      clause := clause || format(' and %I > %L', k, substring(v from 4));
    elsif v like 'lt.%' then
      clause := clause || format(' and %I < %L', k, substring(v from 4));
    elsif v like 'in.(%' then
      inner_txt := substring(v from 5 for length(v) - 5);
      items := string_to_array(inner_txt, ',');
      quoted := array[]::text[];
      foreach item in array items loop
        quoted := quoted || quote_literal(item);
      end loop;
      clause := clause || format(' and %I in (%s)', k, array_to_string(quoted, ','));
    else
      raise exception 'unsupported filter %=%', k, v;
    end if;
  end loop;
  return clause;
end;
$$;

create or replace function public.tenant_build_order(p_table text, p_query text)
returns text
language plpgsql
as $$
declare
  pair text; k text; v text; item text; col text; dir text; out_parts text[] := array[]::text[];
begin
  if p_query is null or p_query = '' then return ''; end if;
  foreach pair in array string_to_array(p_query, '&') loop
    k := split_part(pair, '=', 1);
    v := split_part(pair, '=', 2);
    if k = 'order' then
      foreach item in array string_to_array(v, ',') loop
        col := split_part(item, '.', 1);
        dir := coalesce(nullif(split_part(item, '.', 2), ''), 'asc');
        if not tenant_col_ok(p_table, col) then raise exception 'bad order column %', col; end if;
        if dir not in ('asc','desc') then dir := 'asc'; end if;
        out_parts := out_parts || format('%I %s', col, dir);
      end loop;
    end if;
  end loop;
  if array_length(out_parts,1) is null then return ''; end if;
  return ' order by ' || array_to_string(out_parts, ', ');
end;
$$;

-- ---------- 4) The 4 entry points the app calls ------------------------

create or replace function public.tenant_get(p_token uuid, p_table text, p_query text default '')
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare cid uuid; wh text; ordc text; sql text; result jsonb;
begin
  if not tenant_table_ok(p_table) then raise exception 'bad table'; end if;
  cid := tenant_client_id(p_token);
  wh := tenant_build_where(p_table, p_query);
  ordc := tenant_build_order(p_table, p_query);
  sql := format('select coalesce(jsonb_agg(t), ''[]''::jsonb) from (select * from %I where client_id = %L%s%s) t',
                p_table, cid, wh, ordc);
  execute sql into result;
  return result;
end;
$$;

-- p_data may be a single object ({...}) or an array of objects ([{...},{...}])
-- for bulk inserts (used by the backup-restore screen). All rows must share
-- the same set of keys (which is how the app already sends them).
create or replace function public.tenant_post(p_token uuid, p_table text, p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  cid uuid; k text; row_json jsonb; first_row jsonb;
  cols text[] := array[]::text[]; vals text[]; row_values text[] := array[]::text[];
  sql text; result jsonb;
begin
  if not tenant_table_ok(p_table) then raise exception 'bad table'; end if;
  cid := tenant_client_id(p_token);

  first_row := case when jsonb_typeof(p_data) = 'array' then p_data -> 0 else p_data end;
  cols := array[quote_ident('client_id')];
  for k in select jsonb_object_keys(first_row) loop
    if k = 'client_id' then continue; end if;
    if not tenant_col_ok(p_table, k) then raise exception 'bad column %', k; end if;
    cols := cols || quote_ident(k);
  end loop;

  for row_json in
    select j from jsonb_array_elements(
      case when jsonb_typeof(p_data) = 'array' then p_data else jsonb_build_array(p_data) end
    ) j
  loop
    vals := array[quote_literal(cid::text)];
    for k in select jsonb_object_keys(first_row) loop
      if k = 'client_id' then continue; end if;
      vals := vals || coalesce(quote_literal(row_json ->> k), 'null');
    end loop;
    row_values := row_values || ('(' || array_to_string(vals, ',') || ')');
  end loop;

  sql := format('with ins as (insert into %I (%s) values %s returning *) select coalesce(jsonb_agg(to_jsonb(ins)), ''[]''::jsonb) from ins',
                p_table, array_to_string(cols, ','), array_to_string(row_values, ','));
  execute sql into result;
  return result;
end;
$$;

create or replace function public.tenant_patch(p_token uuid, p_table text, p_query text, p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  cid uuid; wh text; k text; sets text[] := array[]::text[]; sql text; result jsonb;
begin
  if not tenant_table_ok(p_table) then raise exception 'bad table'; end if;
  cid := tenant_client_id(p_token);
  wh := tenant_build_where(p_table, p_query);
  for k in select jsonb_object_keys(p_data) loop
    if k = 'client_id' then continue; end if;
    if not tenant_col_ok(p_table, k) then raise exception 'bad column %', k; end if;
    sets := sets || format('%I = %L', k, p_data ->> k);
  end loop;
  if array_length(sets,1) is null then raise exception 'no fields to update'; end if;
  sql := format('with upd as (update %I set %s where client_id = %L%s returning *) select coalesce(jsonb_agg(upd), ''[]''::jsonb) from upd',
                p_table, array_to_string(sets, ', '), cid, wh);
  execute sql into result;
  return result;
end;
$$;

create or replace function public.tenant_delete(p_token uuid, p_table text, p_query text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare cid uuid; wh text; sql text; cnt int;
begin
  if not tenant_table_ok(p_table) then raise exception 'bad table'; end if;
  cid := tenant_client_id(p_token);
  wh := tenant_build_where(p_table, p_query);
  sql := format('with del as (delete from %I where client_id = %L%s returning 1) select count(*) from del', p_table, cid, wh);
  execute sql into cnt;
  return jsonb_build_object('deleted', cnt);
end;
$$;

revoke execute on function public.tenant_get(uuid, text, text)          from public;
revoke execute on function public.tenant_post(uuid, text, jsonb)        from public;
revoke execute on function public.tenant_patch(uuid, text, text, jsonb) from public;
revoke execute on function public.tenant_delete(uuid, text, text)       from public;

grant execute on function public.tenant_get(uuid, text, text)          to anon;
grant execute on function public.tenant_post(uuid, text, jsonb)        to anon;
grant execute on function public.tenant_patch(uuid, text, text, jsonb) to anon;
grant execute on function public.tenant_delete(uuid, text, text)       to anon;
