CREATE DATABASE IF NOT EXISTS emushpedia_fr CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS emushpedia_en CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS emushpedia_es CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

GRANT ALL PRIVILEGES ON emushpedia_fr.* TO 'mediawiki'@'%';
GRANT ALL PRIVILEGES ON emushpedia_en.* TO 'mediawiki'@'%';
GRANT ALL PRIVILEGES ON emushpedia_es.* TO 'mediawiki'@'%';

FLUSH PRIVILEGES;
