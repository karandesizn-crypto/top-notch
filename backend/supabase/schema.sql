create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  plan text not null default 'free',
  created_at timestamptz not null default now()
);

create table preferences (
  user_id uuid primary key references profiles(id) on delete cascade,
  enabled_providers text[] not null default array['claude','cursor','codex'],
  warning_threshold numeric not null default 80,
  critical_threshold numeric not null default 90,
  notifications_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

create table devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  platform text not null,
  app_version text,
  push_token text,
  created_at timestamptz not null default now()
);

create table usage_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  provider text not null,
  scope text not null,
  percentage_used numeric,
  reset_at timestamptz,
  observed_at timestamptz not null,
  source text not null
);
