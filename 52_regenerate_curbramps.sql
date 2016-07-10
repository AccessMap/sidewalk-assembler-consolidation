/*

Goal: Add 'curbramps' boolean to crossings

Strategy: Recreate 'curbramps' cleaned-up data table after moving sidewalks,
          then apply 'curbramps' label to crossings if both sides have one.

*/
\timing


-- Create the new curbramps table
DROP TABLE IF EXISTS public.curbramps;
CREATE TABLE public.curbramps (
  id integer PRIMARY KEY DEFAULT nextval('serial'),
  geom geometry
);
SELECT geom
  INTO public.curbramps
  FROM (SELECT ST_StartPoint(sw.geom) AS geom
          FROM build.clean_sidewalks sw
         WHERE curbramp_start
         UNION
        SELECT ST_EndPoint(sw.geom) AS geom
          FROM build.clean_sidewalks sw
         WHERE curbramp_end) AS cr;

CREATE INDEX curbramps_index
          ON curbramps
       USING gist(geom);
