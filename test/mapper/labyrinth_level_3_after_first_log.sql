-- The map a replay of logs/session-teekywiki-2026-09-25T21-07-06.log has built,
-- with labyrinth-104's description cleaned as it was before the next session.
-- Generated, not written: see labyrinth_level_3_trap_spec.lua for how and when
-- to regenerate it.
BEGIN;
INSERT INTO areas(id,slug,name) VALUES(1,'labyrinth-level-1','The Labyrinth, Level 1');
INSERT INTO areas(id,slug,name) VALUES(2,'labyrinth-level-3','The Labyrinth, Level 3');
INSERT INTO rooms(id,slug,name,description,area_id,first_visited,visits,x,y,z,trap) VALUES(101,'labyrinth-100','labyrinth','You have entered a small room with a with a stone staircase in the center. The staircase leads upward. You can also exit to the west.',2,'2026-09-27T12:16:53',3,0,0,0,NULL);
INSERT INTO rooms(id,slug,name,description,area_id,first_visited,visits,x,y,z,trap) VALUES(102,'labyrinth-101','labyrinth','You are wandering through an intracate tangle of thick subterranean growth. The warm air in this twisting passage makes you perspire. Pungent odors assail your senses from all directions. Exits are north, east, and south.',2,'2026-09-27T12:16:54',3,-1,0,0,NULL);
INSERT INTO rooms(id,slug,name,description,area_id,first_visited,visits,x,y,z,trap) VALUES(103,'labyrinth-102','labyrinth','You are wandering through an intracate tangle of thick subterranean growth. The warm air in this twisting passage makes you perspire. Pungent odors assail your senses from all directions. Exits are north and south.',2,'2026-09-27T12:16:57',3,-1,-1,0,NULL);
INSERT INTO rooms(id,slug,name,description,area_id,first_visited,visits,x,y,z,trap) VALUES(104,'labyrinth-103','labyrinth','You are wandering through an intracate tangle of thick subterranean growth. The warm air in this twisting passage makes you perspire. Pungent odors assail your senses from all directions. Exits are north and west.',2,'2026-09-27T12:17:00',3,-1,-2,0,NULL);
INSERT INTO rooms(id,slug,name,description,area_id,first_visited,visits,x,y,z,trap) VALUES(105,'labyrinth-104','labyrinth','You are wandering through an intracate tangle of thick subterranean growth. The warm air in this twisting passage makes you perspire. Pungent odors assail your senses from all directions. Exits are east and west.',2,'2026-09-27T12:17:03',1,-2,-2,0,NULL);
INSERT INTO room_exits(from_id,direction,to_id,lock_key,lock_door,sealed_by) VALUES(101,'u',NULL,NULL,NULL,NULL);
INSERT INTO room_exits(from_id,direction,to_id,lock_key,lock_door,sealed_by) VALUES(101,'w',102,NULL,NULL,NULL);
INSERT INTO room_exits(from_id,direction,to_id,lock_key,lock_door,sealed_by) VALUES(102,'e',101,NULL,NULL,NULL);
INSERT INTO room_exits(from_id,direction,to_id,lock_key,lock_door,sealed_by) VALUES(102,'n',NULL,NULL,NULL,NULL);
INSERT INTO room_exits(from_id,direction,to_id,lock_key,lock_door,sealed_by) VALUES(102,'s',103,NULL,NULL,NULL);
INSERT INTO room_exits(from_id,direction,to_id,lock_key,lock_door,sealed_by) VALUES(103,'n',102,NULL,NULL,NULL);
INSERT INTO room_exits(from_id,direction,to_id,lock_key,lock_door,sealed_by) VALUES(103,'s',104,NULL,NULL,NULL);
INSERT INTO room_exits(from_id,direction,to_id,lock_key,lock_door,sealed_by) VALUES(104,'n',103,NULL,NULL,NULL);
INSERT INTO room_exits(from_id,direction,to_id,lock_key,lock_door,sealed_by) VALUES(104,'w',105,NULL,NULL,NULL);
INSERT INTO room_exits(from_id,direction,to_id,lock_key,lock_door,sealed_by) VALUES(105,'e',104,NULL,NULL,NULL);
INSERT INTO room_exits(from_id,direction,to_id,lock_key,lock_door,sealed_by) VALUES(105,'w',NULL,NULL,NULL,NULL);
INSERT INTO player_location(player,room_id,updated_at) VALUES('Teekywiki',101,'2026-09-27T12:17:06');
COMMIT;
