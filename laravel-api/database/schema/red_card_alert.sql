CREATE DATABASE IF NOT EXISTS red_card_alert
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE red_card_alert;

CREATE TABLE users (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  email_verified_at TIMESTAMP NULL,
  password VARCHAR(255) NOT NULL,
  role ENUM('admin','user') NOT NULL DEFAULT 'user',
  subscription_status ENUM('free_trial','active_paid','expired','disabled') NOT NULL DEFAULT 'free_trial',
  trial_ends_at TIMESTAMP NULL,
  subscription_ends_at TIMESTAMP NULL,
  remember_token VARCHAR(100) NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  INDEX users_role_index (role),
  INDEX users_subscription_status_index (subscription_status),
  INDEX users_trial_ends_at_index (trial_ends_at),
  INDEX users_subscription_ends_at_index (subscription_ends_at)
) ENGINE=InnoDB;

CREATE TABLE personal_access_tokens (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tokenable_type VARCHAR(255) NOT NULL,
  tokenable_id BIGINT UNSIGNED NOT NULL,
  name TEXT NOT NULL,
  token VARCHAR(64) NOT NULL UNIQUE,
  abilities TEXT NULL,
  last_used_at TIMESTAMP NULL,
  expires_at TIMESTAMP NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  INDEX personal_access_tokens_tokenable_index (tokenable_type, tokenable_id),
  INDEX personal_access_tokens_expires_at_index (expires_at)
) ENGINE=InnoDB;

CREATE TABLE leagues (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider VARCHAR(30) NOT NULL,
  provider_id VARCHAR(120) NOT NULL,
  name VARCHAR(255) NOT NULL,
  country VARCHAR(120) NULL,
  logo_url TEXT NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  UNIQUE KEY leagues_provider_provider_id_unique (provider, provider_id)
) ENGINE=InnoDB;

CREATE TABLE teams (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider VARCHAR(30) NOT NULL,
  provider_id VARCHAR(120) NOT NULL,
  name VARCHAR(255) NOT NULL,
  country VARCHAR(120) NULL,
  logo_url TEXT NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  UNIQUE KEY teams_provider_provider_id_unique (provider, provider_id)
) ENGINE=InnoDB;

CREATE TABLE fixtures (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider VARCHAR(30) NOT NULL,
  provider_id VARCHAR(160) NOT NULL UNIQUE,
  league_id BIGINT UNSIGNED NOT NULL,
  home_team_id BIGINT UNSIGNED NOT NULL,
  away_team_id BIGINT UNSIGNED NOT NULL,
  status VARCHAR(60) NOT NULL,
  minute SMALLINT UNSIGNED NULL,
  venue VARCHAR(255) NULL,
  referee VARCHAR(255) NULL,
  season SMALLINT UNSIGNED NULL,
  has_timeline TINYINT(1) NOT NULL DEFAULT 0,
  home_score SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  away_score SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  home_yellow_cards SMALLINT UNSIGNED NULL,
  away_yellow_cards SMALLINT UNSIGNED NULL,
  home_red_cards SMALLINT UNSIGNED NULL,
  away_red_cards SMALLINT UNSIGNED NULL,
  home_shots SMALLINT UNSIGNED NULL,
  away_shots SMALLINT UNSIGNED NULL,
  home_shots_on_target SMALLINT UNSIGNED NULL,
  away_shots_on_target SMALLINT UNSIGNED NULL,
  home_corners SMALLINT UNSIGNED NULL,
  away_corners SMALLINT UNSIGNED NULL,
  starts_at TIMESTAMP NULL,
  last_synced_at TIMESTAMP NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  INDEX fixtures_status_index (status),
  INDEX fixtures_starts_at_index (starts_at),
  CONSTRAINT fixtures_league_id_fk FOREIGN KEY (league_id) REFERENCES leagues(id),
  CONSTRAINT fixtures_home_team_id_fk FOREIGN KEY (home_team_id) REFERENCES teams(id),
  CONSTRAINT fixtures_away_team_id_fk FOREIGN KEY (away_team_id) REFERENCES teams(id)
) ENGINE=InnoDB;

CREATE TABLE match_events (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  fixture_id BIGINT UNSIGNED NOT NULL,
  provider_event_id VARCHAR(160) NULL,
  fingerprint CHAR(64) NOT NULL UNIQUE,
  type VARCHAR(60) NOT NULL,
  detail VARCHAR(255) NOT NULL,
  minute SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  extra_minute SMALLINT UNSIGNED NULL,
  team_provider_id VARCHAR(120) NULL,
  team_name VARCHAR(255) NULL,
  player_provider_id VARCHAR(120) NULL,
  player_name VARCHAR(255) NULL,
  comments TEXT NULL,
  is_red_card TINYINT(1) NOT NULL DEFAULT 0,
  occurred_at TIMESTAMP NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  INDEX match_events_type_index (type),
  INDEX match_events_is_red_card_index (is_red_card),
  INDEX match_events_occurred_at_index (occurred_at),
  CONSTRAINT match_events_fixture_id_fk FOREIGN KEY (fixture_id) REFERENCES fixtures(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE match_insights (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  fixture_id BIGINT UNSIGNED NOT NULL UNIQUE,
  data JSON NOT NULL,
  synced_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  INDEX match_insights_synced_at_index (synced_at),
  CONSTRAINT match_insights_fixture_id_fk FOREIGN KEY (fixture_id) REFERENCES fixtures(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE favorite_teams (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  team_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  UNIQUE KEY favorite_teams_user_team_unique (user_id, team_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE favorite_leagues (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  league_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  UNIQUE KEY favorite_leagues_user_league_unique (user_id, league_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (league_id) REFERENCES leagues(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE favorite_fixtures (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  fixture_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  UNIQUE KEY favorite_fixtures_user_fixture_unique (user_id, fixture_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (fixture_id) REFERENCES fixtures(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE alert_settings (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL UNIQUE,
  push_enabled TINYINT(1) NOT NULL DEFAULT 1,
  vibration_enabled TINYINT(1) NOT NULL DEFAULT 1,
  red_cards_enabled TINYINT(1) NOT NULL DEFAULT 1,
  yellow_cards_enabled TINYINT(1) NOT NULL DEFAULT 1,
  all_matches TINYINT(1) NOT NULL DEFAULT 0,
  sound VARCHAR(40) NOT NULL DEFAULT 'Siren',
  silent_from TIME NULL,
  silent_until TIME NULL,
  timezone VARCHAR(64) NOT NULL DEFAULT 'UTC',
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE device_tokens (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  token VARCHAR(512) NOT NULL UNIQUE,
  platform ENUM('android','ios','web') NOT NULL,
  device_name VARCHAR(255) NULL,
  app_version VARCHAR(30) NULL,
  last_seen_at TIMESTAMP NULL,
  revoked_at TIMESTAMP NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE subscriptions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  plan VARCHAR(80) NOT NULL,
  amount INT UNSIGNED NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'TZS',
  payment_method VARCHAR(30) NOT NULL,
  payment_reference VARCHAR(100) NOT NULL UNIQUE,
  status VARCHAR(30) NOT NULL,
  started_at TIMESTAMP NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  INDEX subscriptions_status_index (status),
  INDEX subscriptions_expires_at_index (expires_at),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE payments (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  amount INT UNSIGNED NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'TZS',
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  reference VARCHAR(120) NULL UNIQUE,
  payment_method VARCHAR(40) NULL,
  recorded_by BIGINT UNSIGNED NULL,
  paid_at TIMESTAMP NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  INDEX payments_status_index (status),
  INDEX payments_user_status_paid_at_index (user_id, status, paid_at),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE alert_deliveries (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  match_event_id BIGINT UNSIGNED NOT NULL,
  device_token_id BIGINT UNSIGNED NOT NULL,
  status ENUM('pending','sent','delivered','failed') NOT NULL DEFAULT 'pending',
  provider_message_id VARCHAR(255) NULL,
  error_message TEXT NULL,
  sent_at TIMESTAMP NULL,
  delivered_at TIMESTAMP NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL,
  UNIQUE KEY alert_deliveries_event_device_unique (match_event_id, device_token_id),
  INDEX alert_deliveries_status_index (status),
  FOREIGN KEY (match_event_id) REFERENCES match_events(id) ON DELETE CASCADE,
  FOREIGN KEY (device_token_id) REFERENCES device_tokens(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE sync_runs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  provider VARCHAR(30) NOT NULL,
  status ENUM('running','success','failed') NOT NULL,
  fixtures_count INT UNSIGNED NOT NULL DEFAULT 0,
  events_count INT UNSIGNED NOT NULL DEFAULT 0,
  error_message TEXT NULL,
  started_at TIMESTAMP NOT NULL,
  finished_at TIMESTAMP NULL,
  created_at TIMESTAMP NULL,
  updated_at TIMESTAMP NULL
) ENGINE=InnoDB;

CREATE TABLE cache (
  `key` VARCHAR(255) PRIMARY KEY,
  value MEDIUMTEXT NOT NULL,
  expiration INT NOT NULL
) ENGINE=InnoDB;

CREATE TABLE cache_locks (
  `key` VARCHAR(255) PRIMARY KEY,
  owner VARCHAR(255) NOT NULL,
  expiration INT NOT NULL
) ENGINE=InnoDB;

CREATE TABLE jobs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  queue VARCHAR(255) NOT NULL,
  payload LONGTEXT NOT NULL,
  attempts TINYINT UNSIGNED NOT NULL,
  reserved_at INT UNSIGNED NULL,
  available_at INT UNSIGNED NOT NULL,
  created_at INT UNSIGNED NOT NULL,
  INDEX jobs_queue_index (queue)
) ENGINE=InnoDB;

CREATE TABLE job_batches (
  id VARCHAR(255) PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  total_jobs INT NOT NULL,
  pending_jobs INT NOT NULL,
  failed_jobs INT NOT NULL,
  failed_job_ids LONGTEXT NOT NULL,
  options MEDIUMTEXT NULL,
  cancelled_at INT NULL,
  created_at INT NOT NULL,
  finished_at INT NULL
) ENGINE=InnoDB;

CREATE TABLE failed_jobs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  uuid VARCHAR(255) NOT NULL UNIQUE,
  connection TEXT NOT NULL,
  queue TEXT NOT NULL,
  payload LONGTEXT NOT NULL,
  exception LONGTEXT NOT NULL,
  failed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;
