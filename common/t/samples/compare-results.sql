DROP DATABASE IF EXISTS test;
CREATE DATABASE test;
USE test;

CREATE TABLE dropme (
   i int
);

CREATE TABLE t (
   i int
);
INSERT INTO t VALUES (1),(2),(3);

CREATE TABLE t2 (
   i int primary key,
   c char
);
INSERT INTO t2 VALUES (1,'a'),(2,'b'),(3,'c');
