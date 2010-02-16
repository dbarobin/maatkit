drop database if exists dm;
create database dm;
use dm;

CREATE TABLE `main_table` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `pub_date` date NOT NULL DEFAULT '0000-00-00',
  `c` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `pub_date` (`pub_date`)
) ENGINE=InnoDB;

CREATE TABLE `other_table_1` (
  `id` int(10) unsigned NOT NULL DEFAULT '0',
  `bar` varchar(255) NOT NULL DEFAULT '',
  KEY `id` (`id`)
) ENGINE=InnoDB;

CREATE TABLE `other_table_2` (
  `id` int(10) unsigned NOT NULL DEFAULT '0',
  `bar` varchar(255) NOT NULL DEFAULT '',
  KEY `id` (`id`)
) ENGINE=InnoDB;

insert into main_table values
   (1, '2010-02-16', 'a'),
   (2, '2010-02-15', 'b'),
   (3, '2010-02-15', 'c'),
   (4, '2010-02-16', 'd'),
   (5, '2010-02-14', 'e');

insert into other_table_1 values
   (1, 'a'),
   (2, 'b'),
   (3, 'c'),
   (4, 'd'),
   (5, 'e'),
   (6, 'ot1');

insert into other_table_2 values
   (1, 'a'),
   (2, 'b'),
   (3, 'c'),
   (4, 'd'),
   (5, 'e'),
   (7, 'ot2');
