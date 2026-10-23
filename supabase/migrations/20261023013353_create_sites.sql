-- Lumoria: places where human equipment rests on the Moon (and later Mars).
-- Coordinates are selenographic, east-positive longitude, from LROC (2016).

create table public.sites (
  id            text primary key,
  body          text not null default 'moon' check (body in ('moon', 'mars')),
  mission       text not null,
  mission_order smallint not null,
  label         text not null,
  lander        text not null,
  region        jsonb not null,                      -- {"en": "...", "es": "..."}
  landed_at     timestamptz not null,
  crew_surface  text[] not null default '{}',
  crew_orbit    text,
  lat           double precision not null check (lat between -90 and 90),
  lon           double precision not null check (lon between -180 and 180),
  left_behind   jsonb not null default '[]'::jsonb,  -- [{"en": "...", "es": "..."}]
  story         jsonb not null,                      -- {"en": "...", "es": "..."}
  photo         jsonb,                               -- {"url", "credit"} once chosen
  updated_at    timestamptz not null default now(),
  unique (body, mission_order)
);

comment on table public.sites is 'Landing sites shown in Lumoria. Public, read-only from the app.';

-- The app only reads. Writes happen through migrations/seed or the dashboard.
alter table public.sites enable row level security;

create policy "Sites are readable by everyone"
  on public.sites for select
  to anon, authenticated
  using (true);
