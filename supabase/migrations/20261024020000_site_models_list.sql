-- A site can offer several 3D models (Apollo 15-17: the rover and the lunar module).

alter table public.sites
  add column models text[] not null default '{}';

update public.sites set models = array[model] where model is not null;

alter table public.sites drop column model;

comment on column public.sites.models is 'Bundled USDZ names in the app, the first shown first, e.g. {lunar-rover,lunar-module}.';
