<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();

foreach (['POSTGRES_DB', 'POSTGRES_USER', 'POSTGRES_PASSWORD'] as $name) {
    if (getenv($name) === false || getenv($name) === '') {
        throw new RuntimeException("Required environment variable {$name} is not set.");
    }
}

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

$CFG->pathtogs = '/usr/bin/gs';
$CFG->pathtodot = '/usr/bin/dot';
$CFG->preventexecpath = true;
$CFG->disableupdateautodeploy = true;
$CFG->debug = 0;
$CFG->debugdisplay = false;

require_once(__DIR__ . '/lib/setup.php');
