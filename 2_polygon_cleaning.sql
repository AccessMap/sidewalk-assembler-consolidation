-- Step 0: Create index on compkey
-- FIXME: address the problem below early-on (step 0) and require unique
--        identifier
-- TODO: Some of this is run on the raw sidewalks data, but we should use the
--       intersection-fixed sidewalks data
--- compkey (now id) is not unique, so must delete streets with non-unique IDs
DELETE FROM streets
      WHERE id IN (SELECT id
                     FROM (SELECT id, ROW_NUMBER() OVER (partition BY id
                                                             ORDER BY id) AS rnum
                             FROM streets) AS t
                    WHERE t.rnum > 1);

CREATE UNIQUE INDEX street_id ON streets (id);

-- Step 1: Polygonizing
DROP TABLE IF EXISTS boundary_polygons CASCADE;

CREATE TABLE boundary_polygons AS
      SELECT g.path[1] as gid, geom
        FROM (SELECT (ST_Dump(ST_Polygonize(picked_sidewalks.geom))).*
      	        FROM (SELECT DISTINCT ON (s.id) s.id,
                                                s.geom
      		                        FROM streets s
      		                   LEFT JOIN sidewalks r
                                      ON s.id = r.segkey
      		                       WHERE r.id is not null) AS picked_sidewalks) AS g;

CREATE INDEX boundary_polygons_index
          ON boundary_polygons
       USING gist(geom);


-- Step 2: Remove overlap polygons
DELETE FROM boundary_polygons
      WHERE gid in (SELECT b1.gid
                      FROM boundary_polygons b1,
                           boundary_polygons b2
                     WHERE ST_Overlaps(b1.geom, b2.geom)
                  GROUP BY b1.gid
                    HAVING count(b1.gid) > 1);

-- Step1: Find all sidewalks what are within a polygons
DROP TABLE IF EXISTS grouped_sidewalks;

CREATE TABLE grouped_sidewalks AS SELECT b.gid AS b_id,
                                         s.id AS s_id,
                                         s.geom AS s_geom
                                    FROM sidewalks AS s
                              INNER JOIN boundary_polygons AS b
                                      ON ST_Within(s.geom, b.geom);
--    LIMIT 10000;

---  Step2: Find all polygons that is not assigned to any polygons because of offshoots.
UPDATE grouped_sidewalks
   SET b_id = query.b_id
  FROM (SELECT b.gid AS b_id,
               s.s_id,
               s.s_geom AS s_geom
          FROM (SELECT *
                  FROM grouped_sidewalks
                 WHERE b_id IS NULL) AS s
    INNER JOIN boundary_polygons AS b
            ON ST_Within(ST_Line_Interpolate_Point(s.s_geom, 0.5), b.geom) = True) AS query
 WHERE grouped_sidewalks.s_id = query.s_id;

-- highway

--- Not important: For qgis visualization
CREATE VIEW correct_sidewalks AS SELECT b.gid AS b_id,
                                        s.s_id,
                                        ST_MakeLine(ST_Line_Interpolate_Point(s.s_geom, 0.5),
                                        ST_Centroid(b.geom)) AS geom
                                   FROM (SELECT *
                                           FROM grouped_sidewalks
                                          WHERE b_id IS NULL) AS s
                                  INNER JOIN boundary_polygons AS b
                                     ON ST_Intersects(s.s_geom, b.geom)
                                  WHERE ST_Within(ST_Line_Interpolate_Point(s.s_geom, 0.5), b.geom) = True;

--- Find a bad polygon(id:666) which looks like a highway.
-- There are 57 Polygons that has centroid outside the polygon. Most of them works well with our algorithm.
CREATE VIEW bad_polygons AS SELECT *
                              FROM boundary_polygons AS b
                             WHERE ST_Within(ST_Centroid(b.geom), b.geom) = False;

-- Step 3: Boundaries
-- There are 2779 sidewalks has not been assigned to any polygons

CREATE VIEW union_polygons AS SELECT q.path[1] AS id,
                                     geom
                                -- FIXME: is are the paranthesis before ST_Dump required?
                                FROM (SELECT (ST_Dump(ST_Union(geom))).*
                                        FROM boundary_polygons) AS q;

-- For each unassigned to the closest polygons
UPDATE grouped_sidewalks
   SET b_id = query.b_id
  FROM (SELECT DISTINCT ON (s.s_id) s.s_id as s_id,
                                    u.id as b_id
                      FROM (SELECT *
                              FROM grouped_sidewalks
                             WHERE b_id IS NULL) AS s
                INNER JOIN union_polygons AS u
                        ON u.id=s.b_id
                  ORDER BY s.s_id, ST_Distance(s.s_geom, u.geom)) AS query
 WHERE grouped_sidewalks.s_id = query.s_id;