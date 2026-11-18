-- =====================================================================
--  Projet BDD CESI / ISJA — Gestion scolaire inspirée de PRONOTE
--  L10 — Script de création (MPD) — version de base (avant spécialités)
--  SGBD : MySQL 8.0.16 ou plus récent (CHECK réellement appliqués)
--  Exécution : MySQL Workbench > File > Open SQL Script > Execute (éclair)
--  Le script repart de zéro : il supprime puis recrée la base.
-- =====================================================================

DROP DATABASE IF EXISTS gestion_scolaire;
CREATE DATABASE gestion_scolaire
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
USE gestion_scolaire;

-- ---------------------------------------------------------------------
-- 1. Tables issues des ENTITÉS (règle R1 : entité -> table)
--    Ordre de création : une table référencée est créée avant celle
--    qui la référence.
-- ---------------------------------------------------------------------

CREATE TABLE utilisateur (
  id_utilisateur     INT          NOT NULL AUTO_INCREMENT,
  login              VARCHAR(50)  NOT NULL,
  mot_de_passe_hash  VARCHAR(255) NOT NULL,
  email              VARCHAR(120) NOT NULL,
  role               ENUM('admin', 'professeur', 'eleve') NOT NULL,
  CONSTRAINT pk_utilisateur PRIMARY KEY (id_utilisateur),
  CONSTRAINT uq_utilisateur_login UNIQUE (login),
  CONSTRAINT uq_utilisateur_email UNIQUE (email),
  CONSTRAINT chk_utilisateur_email CHECK (email LIKE '%_@_%._%'),
  CONSTRAINT chk_utilisateur_hash  CHECK (CHAR_LENGTH(mot_de_passe_hash) >= 60)
) ENGINE = InnoDB;

-- Association POSSÉDER (0,1)-(0,1) -> FK id_utilisateur NULL + UNIQUE (règle R3)
CREATE TABLE professeur (
  id_professeur   INT          NOT NULL AUTO_INCREMENT,
  nom             VARCHAR(60)  NOT NULL,
  prenom          VARCHAR(60)  NOT NULL,
  date_naissance  DATE         NULL,
  telephone       VARCHAR(20)  NULL,
  specialite      VARCHAR(60)  NOT NULL,
  id_utilisateur  INT          NULL,
  CONSTRAINT pk_professeur PRIMARY KEY (id_professeur),
  CONSTRAINT uq_professeur_utilisateur UNIQUE (id_utilisateur),
  CONSTRAINT chk_professeur_tel CHECK (telephone REGEXP '^[+]?[0-9 ]{8,20}$'),
  CONSTRAINT fk_professeur_utilisateur FOREIGN KEY (id_utilisateur)
    REFERENCES utilisateur (id_utilisateur)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE = InnoDB;

-- Association ÊTRE PROF. PRINCIPAL (0,1)-(0,1) -> FK NULL + UNIQUE (règle R3)
CREATE TABLE classe (
  id_classe                INT          NOT NULL AUTO_INCREMENT,
  nom_classe               VARCHAR(30)  NOT NULL,
  niveau                   VARCHAR(20)  NOT NULL,
  filiere                  VARCHAR(40)  NOT NULL,
  effectif_max             TINYINT UNSIGNED NOT NULL,
  id_professeur_principal  INT          NULL,
  CONSTRAINT pk_classe PRIMARY KEY (id_classe),
  CONSTRAINT uq_classe_nom UNIQUE (nom_classe),
  CONSTRAINT uq_classe_prof_principal UNIQUE (id_professeur_principal),
  CONSTRAINT chk_classe_effectif CHECK (effectif_max BETWEEN 1 AND 60),
  CONSTRAINT fk_classe_prof_principal FOREIGN KEY (id_professeur_principal)
    REFERENCES professeur (id_professeur)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE = InnoDB;

-- Association APPARTENIR (1,1)-(0,n) -> FK id_classe NOT NULL (règle R2)
CREATE TABLE eleve (
  id_eleve        INT          NOT NULL AUTO_INCREMENT,
  nom             VARCHAR(60)  NOT NULL,
  prenom          VARCHAR(60)  NOT NULL,
  date_naissance  DATE         NOT NULL,
  lieu_naissance  VARCHAR(80)  NULL,
  sexe            ENUM('M', 'F') NOT NULL,
  adresse         VARCHAR(200) NULL,
  id_classe       INT          NOT NULL,
  id_utilisateur  INT          NULL,
  CONSTRAINT pk_eleve PRIMARY KEY (id_eleve),
  CONSTRAINT uq_eleve_utilisateur UNIQUE (id_utilisateur),
  CONSTRAINT fk_eleve_classe FOREIGN KEY (id_classe)
    REFERENCES classe (id_classe)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_eleve_utilisateur FOREIGN KEY (id_utilisateur)
    REFERENCES utilisateur (id_utilisateur)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE = InnoDB;

CREATE TABLE matiere (
  id_matiere           INT           NOT NULL AUTO_INCREMENT,
  nom_matiere          VARCHAR(60)   NOT NULL,
  coefficient          TINYINT UNSIGNED NOT NULL,
  volume_horaire_hebdo DECIMAL(4,1)  NOT NULL,
  description          TEXT          NULL,
  CONSTRAINT pk_matiere PRIMARY KEY (id_matiere),
  CONSTRAINT uq_matiere_nom UNIQUE (nom_matiere),
  CONSTRAINT chk_matiere_coef   CHECK (coefficient BETWEEN 1 AND 10),
  CONSTRAINT chk_matiere_volume CHECK (volume_horaire_hebdo > 0 AND volume_horaire_hebdo <= 20)
) ENGINE = InnoDB;

CREATE TABLE salle (
  id_salle    INT          NOT NULL AUTO_INCREMENT,
  nom_salle   VARCHAR(30)  NOT NULL,
  type_salle  ENUM('standard', 'labo', 'info') NOT NULL DEFAULT 'standard',
  capacite    SMALLINT UNSIGNED NOT NULL,
  CONSTRAINT pk_salle PRIMARY KEY (id_salle),
  CONSTRAINT uq_salle_nom UNIQUE (nom_salle),
  CONSTRAINT chk_salle_capacite CHECK (capacite BETWEEN 1 AND 200)
) ENGINE = InnoDB;

CREATE TABLE creneau (
  id_creneau   INT   NOT NULL AUTO_INCREMENT,
  jour         ENUM('lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi') NOT NULL,
  heure_debut  TIME  NOT NULL,
  heure_fin    TIME  NOT NULL,
  CONSTRAINT pk_creneau PRIMARY KEY (id_creneau),
  CONSTRAINT uq_creneau UNIQUE (jour, heure_debut),
  CONSTRAINT chk_creneau_ordre  CHECK (heure_fin > heure_debut),
  CONSTRAINT chk_creneau_bornes CHECK (heure_debut >= '08:00:00' AND heure_fin <= '17:00:00')
) ENGINE = InnoDB;

-- COURS, le pivot : CONCERNER, ENSEIGNER et PORTER SUR sont des (1,1)-(0,n)
-- -> trois FK NOT NULL (règle R2)
CREATE TABLE cours (
  id_cours        INT      NOT NULL AUTO_INCREMENT,
  type_cours      ENUM('cours', 'TD', 'TP') NOT NULL DEFAULT 'cours',
  annee_scolaire  CHAR(9)  NOT NULL,
  id_matiere      INT      NOT NULL,
  id_professeur   INT      NOT NULL,
  id_classe       INT      NOT NULL,
  CONSTRAINT pk_cours PRIMARY KEY (id_cours),
  -- une classe n'a qu'un cours de chaque type par matière et par année
  CONSTRAINT uq_cours UNIQUE (id_classe, id_matiere, type_cours, annee_scolaire),
  -- format « 2026-2027 » avec deux années qui se suivent
  CONSTRAINT chk_cours_annee CHECK (
    annee_scolaire REGEXP '^[0-9]{4}-[0-9]{4}$'
    AND CAST(RIGHT(annee_scolaire, 4) AS UNSIGNED) = CAST(LEFT(annee_scolaire, 4) AS UNSIGNED) + 1
  ),
  CONSTRAINT fk_cours_matiere FOREIGN KEY (id_matiere)
    REFERENCES matiere (id_matiere) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_cours_professeur FOREIGN KEY (id_professeur)
    REFERENCES professeur (id_professeur) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_cours_classe FOREIGN KEY (id_classe)
    REFERENCES classe (id_classe) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 2. Tables issues des ASSOCIATIONS (règle R4 : (0,n)-(0,n) ou ternaire)
-- ---------------------------------------------------------------------

-- PLANIFIER (Cours, Créneau, Salle) avec CIF (Cours, Créneau) -> Salle
-- -> clé = (id_cours, id_creneau), id_salle simple FK NOT NULL (règle R6)
CREATE TABLE planifier (
  id_cours    INT NOT NULL,
  id_creneau  INT NOT NULL,
  id_salle    INT NOT NULL,
  CONSTRAINT pk_planifier PRIMARY KEY (id_cours, id_creneau),
  CONSTRAINT fk_planifier_cours FOREIGN KEY (id_cours)
    REFERENCES cours (id_cours) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_planifier_creneau FOREIGN KEY (id_creneau)
    REFERENCES creneau (id_creneau) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_planifier_salle FOREIGN KEY (id_salle)
    REFERENCES salle (id_salle) ON UPDATE CASCADE ON DELETE RESTRICT,
  INDEX idx_planifier_creneau_salle (id_creneau, id_salle)
) ENGINE = InnoDB;

-- ÊTRE DISPONIBLE (Professeur, Créneau), sans attribut
CREATE TABLE etre_disponible (
  id_professeur  INT NOT NULL,
  id_creneau     INT NOT NULL,
  CONSTRAINT pk_etre_disponible PRIMARY KEY (id_professeur, id_creneau),
  CONSTRAINT fk_dispo_professeur FOREIGN KEY (id_professeur)
    REFERENCES professeur (id_professeur) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_dispo_creneau FOREIGN KEY (id_creneau)
    REFERENCES creneau (id_creneau) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE = InnoDB;

-- ÉVALUER (Élève, Cours, Calendrier) : CALENDRIER est réduit à sa date,
-- qui entre dans la clé sans table propre (règle R5)
CREATE TABLE evaluer (
  id_eleve         INT           NOT NULL,
  id_cours         INT           NOT NULL,
  date_evaluation  DATE          NOT NULL,
  note             DECIMAL(4,2)  NOT NULL,
  appreciation     VARCHAR(255)  NULL,
  CONSTRAINT pk_evaluer PRIMARY KEY (id_eleve, id_cours, date_evaluation),
  CONSTRAINT chk_evaluer_note CHECK (note BETWEEN 0 AND 20),
  -- RESTRICT : on ne supprime pas un élève qui a des notes (archives)
  CONSTRAINT fk_evaluer_eleve FOREIGN KEY (id_eleve)
    REFERENCES eleve (id_eleve) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_evaluer_cours FOREIGN KEY (id_cours)
    REFERENCES cours (id_cours) ON UPDATE CASCADE ON DELETE RESTRICT,
  INDEX idx_evaluer_cours_date (id_cours, date_evaluation)
) ENGINE = InnoDB;

-- S'ABSENTER (Élève, Cours, Calendrier) — même principe
-- (l'attribut « type » du MCD s'appelle type_absence : TYPE est un mot-clé SQL)
CREATE TABLE s_absenter (
  id_eleve        INT           NOT NULL,
  id_cours        INT           NOT NULL,
  date_absence    DATE          NOT NULL,
  type_absence    ENUM('absence', 'retard') NOT NULL,
  minutes_retard  SMALLINT UNSIGNED NULL,
  motif           VARCHAR(255)  NULL,
  justifiee       BOOLEAN       NOT NULL DEFAULT FALSE,
  CONSTRAINT pk_s_absenter PRIMARY KEY (id_eleve, id_cours, date_absence),
  -- un retard a une durée, une absence n'en a pas
  CONSTRAINT chk_absence_retard CHECK (
       (type_absence = 'retard'  AND minutes_retard IS NOT NULL AND minutes_retard BETWEEN 1 AND 240)
    OR (type_absence = 'absence' AND minutes_retard IS NULL)
  ),
  CONSTRAINT fk_absenter_eleve FOREIGN KEY (id_eleve)
    REFERENCES eleve (id_eleve) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_absenter_cours FOREIGN KEY (id_cours)
    REFERENCES cours (id_cours) ON UPDATE CASCADE ON DELETE RESTRICT,
  INDEX idx_absenter_cours_date (id_cours, date_absence)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 3. Règles de gestion que les clés et les CHECK ne suffisent pas à
--    garantir : procédures de contrôle + déclencheurs (triggers)
-- ---------------------------------------------------------------------
DELIMITER $$

-- RG : un compte relié à un élève doit avoir le rôle 'eleve',
--      un compte relié à un professeur le rôle 'professeur'
CREATE PROCEDURE verifier_role_compte(IN p_utilisateur INT, IN p_role VARCHAR(20))
BEGIN
  IF p_utilisateur IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM utilisateur u
                     WHERE u.id_utilisateur = p_utilisateur AND u.role = p_role) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Ce compte utilisateur n''a pas le rôle attendu';
  END IF;
END$$

-- RG : une classe ne dépasse pas son effectif maximal
CREATE PROCEDURE verifier_effectif(IN p_classe INT)
BEGIN
  IF (SELECT COUNT(*) FROM eleve e WHERE e.id_classe = p_classe)
     >= (SELECT c.effectif_max FROM classe c WHERE c.id_classe = p_classe) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Effectif maximal de la classe atteint';
  END IF;
END$$

-- RG : on ne note / on ne pointe un élève que dans un cours de SA classe
--      (c'est cette procédure qu'on modifiera pour les spécialités)
CREATE PROCEDURE verifier_eleve_du_cours(IN p_eleve INT, IN p_cours INT)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM eleve e
                 JOIN cours c ON c.id_classe = e.id_classe
                 WHERE e.id_eleve = p_eleve AND c.id_cours = p_cours) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cet élève ne suit pas ce cours (classe différente)';
  END IF;
END$$

-- RG de l'emploi du temps, vérifiées à chaque planification.
-- p_old_cours / p_old_creneau : la ligne modifiée (UPDATE), à ignorer.
CREATE PROCEDURE verifier_planification(
  IN p_cours INT, IN p_creneau INT, IN p_salle INT,
  IN p_old_cours INT, IN p_old_creneau INT)
BEGIN
  DECLARE v_prof INT;
  DECLARE v_classe INT;
  DECLARE v_annee CHAR(9);
  DECLARE v_capacite INT;
  DECLARE v_effectif INT;

  SELECT c.id_professeur, c.id_classe, c.annee_scolaire
    INTO v_prof, v_classe, v_annee
    FROM cours c WHERE c.id_cours = p_cours;

  -- RG1 : une salle n'accueille qu'un cours par créneau
  IF EXISTS (SELECT 1 FROM planifier p JOIN cours c ON c.id_cours = p.id_cours
             WHERE p.id_creneau = p_creneau AND p.id_salle = p_salle
               AND c.annee_scolaire = v_annee AND p.id_cours <> p_cours
               AND NOT (p.id_cours <=> p_old_cours AND p.id_creneau <=> p_old_creneau)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Salle déjà occupée sur ce créneau';
  END IF;

  -- RG2 : un professeur ne fait qu'un cours par créneau
  IF EXISTS (SELECT 1 FROM planifier p JOIN cours c ON c.id_cours = p.id_cours
             WHERE p.id_creneau = p_creneau AND c.id_professeur = v_prof
               AND c.annee_scolaire = v_annee AND p.id_cours <> p_cours
               AND NOT (p.id_cours <=> p_old_cours AND p.id_creneau <=> p_old_creneau)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Professeur déjà en cours sur ce créneau';
  END IF;

  -- RG3 : une classe n'a qu'un cours par créneau (version de base)
  IF EXISTS (SELECT 1 FROM planifier p JOIN cours c ON c.id_cours = p.id_cours
             WHERE p.id_creneau = p_creneau AND c.id_classe = v_classe
               AND c.annee_scolaire = v_annee AND p.id_cours <> p_cours
               AND NOT (p.id_cours <=> p_old_cours AND p.id_creneau <=> p_old_creneau)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Classe déjà en cours sur ce créneau';
  END IF;

  -- RG4 : le professeur doit être disponible sur ce créneau
  IF NOT EXISTS (SELECT 1 FROM etre_disponible d
                 WHERE d.id_professeur = v_prof AND d.id_creneau = p_creneau) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Professeur non disponible sur ce créneau';
  END IF;

  -- RG5 : la salle doit pouvoir accueillir toute la classe
  SELECT s.capacite INTO v_capacite FROM salle s WHERE s.id_salle = p_salle;
  SELECT COUNT(*) INTO v_effectif FROM eleve e WHERE e.id_classe = v_classe;
  IF v_effectif > v_capacite THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Salle trop petite pour cette classe';
  END IF;
END$$

-- Déclencheurs ---------------------------------------------------------

CREATE TRIGGER trg_eleve_bi BEFORE INSERT ON eleve FOR EACH ROW
BEGIN
  CALL verifier_effectif(NEW.id_classe);
  CALL verifier_role_compte(NEW.id_utilisateur, 'eleve');
END$$

CREATE TRIGGER trg_eleve_bu BEFORE UPDATE ON eleve FOR EACH ROW
BEGIN
  IF NEW.id_classe <> OLD.id_classe THEN
    CALL verifier_effectif(NEW.id_classe);
  END IF;
  CALL verifier_role_compte(NEW.id_utilisateur, 'eleve');
END$$

CREATE TRIGGER trg_professeur_bi BEFORE INSERT ON professeur FOR EACH ROW
BEGIN
  CALL verifier_role_compte(NEW.id_utilisateur, 'professeur');
END$$

CREATE TRIGGER trg_professeur_bu BEFORE UPDATE ON professeur FOR EACH ROW
BEGIN
  CALL verifier_role_compte(NEW.id_utilisateur, 'professeur');
END$$

CREATE TRIGGER trg_planifier_bi BEFORE INSERT ON planifier FOR EACH ROW
BEGIN
  CALL verifier_planification(NEW.id_cours, NEW.id_creneau, NEW.id_salle, NULL, NULL);
END$$

CREATE TRIGGER trg_planifier_bu BEFORE UPDATE ON planifier FOR EACH ROW
BEGIN
  CALL verifier_planification(NEW.id_cours, NEW.id_creneau, NEW.id_salle,
                              OLD.id_cours, OLD.id_creneau);
END$$

CREATE TRIGGER trg_evaluer_bi BEFORE INSERT ON evaluer FOR EACH ROW
BEGIN
  CALL verifier_eleve_du_cours(NEW.id_eleve, NEW.id_cours);
END$$

CREATE TRIGGER trg_evaluer_bu BEFORE UPDATE ON evaluer FOR EACH ROW
BEGIN
  CALL verifier_eleve_du_cours(NEW.id_eleve, NEW.id_cours);
END$$

CREATE TRIGGER trg_absenter_bi BEFORE INSERT ON s_absenter FOR EACH ROW
BEGIN
  CALL verifier_eleve_du_cours(NEW.id_eleve, NEW.id_cours);
END$$

CREATE TRIGGER trg_absenter_bu BEFORE UPDATE ON s_absenter FOR EACH ROW
BEGIN
  CALL verifier_eleve_du_cours(NEW.id_eleve, NEW.id_cours);
END$$

DELIMITER ;

-- Fin du script de création : 12 tables, 4 procédures, 10 déclencheurs.
