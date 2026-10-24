-- Robotic landers and impact sites join the Apollo landings; some sites carry a 3D model.

alter table public.sites
  add column kind text not null default 'crewed'
    check (kind in ('crewed', 'robotic', 'impact')),
  add column model text;   -- bundled USDZ name in the app, e.g. 'lunar-module'

comment on column public.sites.kind is 'crewed = Apollo landing; robotic = lander or rover; impact = crater from a spacecraft.';
