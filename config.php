<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();

$CFG->dbtype    = 'pgsql';
$CFG->dblibrary = 'native';
$CFG->dbhost    = 'db';
$CFG->dbname    = getenv('POSTGRES_DB');
$CFG->dbuser    = getenv('POSTGRES_USER');
$CFG->dbpass    = getenv('POSTGRES_PASSWORD');
$CFG->prefix    = 'mdl_';
$CFG->dboptions = ['dbpersist' => 0, 'dbport' => 5432];

$CFG->wwwroot   = 'https://moodle.fcr.lat';
$CFG->dataroot  = '/var/www/moodledata';
$CFG->admin     = 'admin';
$CFG->directorypermissions = 0770;

// TLS terminates at the host nginx.
$CFG->sslproxy = true;
$CFG->reverseproxy = false;

require_once(__DIR__ . '/lib/setup.php');
