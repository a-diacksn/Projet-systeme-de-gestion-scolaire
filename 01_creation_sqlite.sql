-- =====================================================================
--  Projet BDD CESI / ISJA — Gestion scolaire inspirée de PRONOTE
--  L10 — MPD v1 (version de base, avant spécialités)
--  Dialecte : SQLite 3.35 ou plus récent (SQLite Cloud)
--
--  Différences avec la version MySQL (même modèle, autre syntaxe) :
--   - pas de CREATE DATABASE / USE : la base se choisit dans SQLite Cloud ;
--   - ENUM        -> TEXT + CHECK (valeur IN (...)) ;
--   - AUTO_INCREMENT -> INTEGER PRIMARY KEY (numéro attribué tout seul) ;
--   - BOOLEAN     -> 0 / 1 contrôlé par CHECK ;
--   - DATE, TIME  -> texte 'AAAA-MM-JJ' et 'HH:MM:SS' contrôlé par CHECK ;
--   - procédures stockées -> déclencheurs avec RAISE(ABORT, 'message') ;
--   - les clés étrangères ne sont vérifiées qu'après
--     PRAGMA foreign_keys = ON (à chaque connexion).
--
--  Le script repart de zéro : il supprime puis recrée toutes les tables
--  (y compris celles de la v2 si elles existent).
-- =====================================================================

PRAGMA foreign_keys = OFF;   -- le temps de supprimer l'ancienne base

DROP VIEW  IF EXISTS v_groupe;
DROP VIEW  IF EXISTS v_eleve_cours;
DROP VIEW  IF EXISTS v_eleve_groupe;
DROP TABLE IF EXISTS inscrire;
DROP TABLE IF EXISTS s_absenter;
DROP TABLE IF EXISTS evaluer;
DROP TABLE IF EXISTS etre_disponible;
DROP TABLE IF EXISTS planifier;
DROP TABLE IF EXISTS cours_v2;
DROP TABLE IF EXISTS cours;
DROP TABLE IF EXISTS groupe;
DROP TABLE IF EXISTS creneau;
DROP TABLE IF EXISTS salle;
DROP TABLE IF EXISTS matiere;
DROP TABLE IF EXISTS eleve;
DROP TABLE IF EXISTS classe;
DROP TABLE IF EXISTS professeur;
DROP TABLE IF EXISTS utilisateur;

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- 1. Tables issues des ENTITÉS (règle R1 : entité -> table)
-- ---------------------------------------------------------------------

CREATE TABLE utilisateur (
  id_utilisateur     INTEGER,
  login              VARCHAR(50)  NOT NULL,
  mot_de_passe_hash  VARCHAR(255) NOT NULL,
  email              VARCHAR(120) NOT NULL,
  role               TEXT         NOT NULL,
  CONSTRAINT pk_utilisateur PRIMARY KEY (id_utilisateur),
  CONSTRAINT uq_utilisateur_login UNIQUE (login),
  CONSTRAINT uq_utilisateur_email UNIQUE (email),
  CONSTRAINT chk_utilisateur_login CHECK (length(login) BETWEEN 3 AND 50),
  CONSTRAINT chk_utilisateur_email CHECK (email LIKE '%_@_%._%'),
  CONSTRAINT chk_utilisateur_hash  CHECK (length(mot_de_passe_hash) >= 60),
  CONSTRAINT chk_utilisateur_role  CHECK (role IN ('admin', 'professeur', 'eleve'))
);

-- POSSÉDER (0,1)-(0,1) -> FK id_utilisateur NULL + UNIQUE (règle R3)
CREATE TABLE professeur (
  id_professeur   INTEGER,
  nom             VARCHAR(60) NOT NULL,
  prenom          VARCHAR(60) NOT NULL,
  date_naissance  DATE        NULL,
  telephone       VARCHAR(20) NULL,
  specialite      VARCHAR(60) NOT NULL,
  id_utilisateur  INTEGER     NULL,
  CONSTRAINT pk_professeur PRIMARY KEY (id_professeur),
  CONSTRAINT uq_professeur_utilisateur UNIQUE (id_utilisateur),
  CONSTRAINT chk_professeur_nom  CHECK (length(nom) BETWEEN 1 AND 60 AND length(prenom) BETWEEN 1 AND 60),
  CONSTRAINT chk_professeur_date CHECK (date_naissance IS NULL OR date(date_naissance) IS date_naissance),
  CONSTRAINT chk_professeur_tel  CHECK (telephone IS NULL OR
             (length(telephone) BETWEEN 8 AND 20 AND telephone NOT GLOB '*[^0-9 +]*')),
  CONSTRAINT fk_professeur_utilisateur FOREIGN KEY (id_utilisateur)
    REFERENCES utilisateur (id_utilisateur) ON UPDATE CASCADE ON DELETE SET NULL
);

-- ÊTRE PROF. PRINCIPAL (0,1)-(0,1) -> FK NULL + UNIQUE (règle R3)
CREATE TABLE classe (
  id_classe                INTEGER,
  nom_classe               VARCHAR(30) NOT NULL,
  niveau                   VARCHAR(20) NOT NULL,
  filiere                  VARCHAR(40) NOT NULL,
  effectif_max             TINYINT     NOT NULL,
  id_professeur_principal  INTEGER     NULL,
  CONSTRAINT pk_classe PRIMARY KEY (id_classe),
  CONSTRAINT uq_classe_nom UNIQUE (nom_classe),
  CONSTRAINT uq_classe_prof_principal UNIQUE (id_professeur_principal),
  CONSTRAINT chk_classe_nom      CHECK (length(nom_classe) BETWEEN 1 AND 30),
  CONSTRAINT chk_classe_effectif CHECK (effectif_max BETWEEN 1 AND 60),
  CONSTRAINT fk_classe_prof_principal FOREIGN KEY (id_professeur_principal)
    REFERENCES professeur (id_professeur) ON UPDATE CASCADE ON DELETE SET NULL
);

-- APPARTENIR (1,1)-(0,n) -> FK id_classe NOT NULL (règle R2)
-- POSSÉDER   (0,1)-(0,1) -> FK id_utilisateur NULL + UNIQUE (règle R3)
CREATE TABLE eleve (
  id_eleve        INTEGER,
  nom             VARCHAR(60)  NOT NULL,
  prenom          VARCHAR(60)  NOT NULL,
  date_naissance  DATE         NOT NULL,
  lieu_naissance  VARCHAR(80)  NULL,
  sexe            TEXT         NOT NULL,
  adresse         VARCHAR(200) NULL,
  id_classe       INTEGER      NOT NULL,
  id_utilisateur  INTEGER      NULL,
  CONSTRAINT pk_eleve PRIMARY KEY (id_eleve),
  CONSTRAINT uq_eleve_utilisateur UNIQUE (id_utilisateur),
  CONSTRAINT chk_eleve_nom  CHECK (length(nom) BETWEEN 1 AND 60 AND length(prenom) BETWEEN 1 AND 60),
  CONSTRAINT chk_eleve_date CHECK (date(date_naissance) IS date_naissance),
  CONSTRAINT chk_eleve_sexe CHECK (sexe IN ('M', 'F')),
  CONSTRAINT fk_eleve_classe FOREIGN KEY (id_classe)
    REFERENCES classe (id_classe) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_eleve_utilisateur FOREIGN KEY (id_utilisateur)
    REFERENCES utilisateur (id_utilisateur) ON UPDATE CASCADE ON DELETE SET NULL
);
CREATE INDEX idx_eleve_classe ON eleve (id_classe);

CREATE TABLE matiere (
  id_matiere           INTEGER,
  nom_matiere          VARCHAR(60)  NOT NULL,
  coefficient          TINYINT      NOT NULL,
  volume_horaire_hebdo DECIMAL(4,1) NOT NULL,
  description          TEXT         NULL,
  CONSTRAINT pk_matiere PRIMARY KEY (id_matiere),
  CONSTRAINT uq_matiere_nom UNIQUE (nom_matiere),
  CONSTRAINT chk_matiere_nom    CHECK (length(nom_matiere) BETWEEN 1 AND 60),
  CONSTRAINT chk_matiere_coef   CHECK (coefficient BETWEEN 1 AND 10),
  CONSTRAINT chk_matiere_volume CHECK (volume_horaire_hebdo > 0 AND volume_horaire_hebdo <= 20)
);

CREATE TABLE salle (
  id_salle    INTEGER,
  nom_salle   VARCHAR(30) NOT NULL,
  type_salle  TEXT        NOT NULL DEFAULT 'standard',
  capacite    SMALLINT    NOT NULL,
  CONSTRAINT pk_salle PRIMARY KEY (id_salle),
  CONSTRAINT uq_salle_nom UNIQUE (nom_salle),
  CONSTRAINT chk_salle_nom      CHECK (length(nom_salle) BETWEEN 1 AND 30),
  CONSTRAINT chk_salle_type     CHECK (type_salle IN ('standard', 'labo', 'info')),
  CONSTRAINT chk_salle_capacite CHECK (capacite BETWEEN 1 AND 200)
);

CREATE TABLE creneau (
  id_creneau   INTEGER,
  jour         TEXT NOT NULL,
  heure_debut  TIME NOT NULL,
  heure_fin    TIME NOT NULL,
  CONSTRAINT pk_creneau PRIMARY KEY (id_creneau),
  CONSTRAINT uq_creneau UNIQUE (jour, heure_debut),
  CONSTRAINT chk_creneau_jour   CHECK (jour IN ('lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi')),
  CONSTRAINT chk_creneau_format CHECK (time(heure_debut) IS heure_debut AND time(heure_fin) IS heure_fin),
  CONSTRAINT chk_creneau_ordre  CHECK (heure_fin > heure_debut),
  CONSTRAINT chk_creneau_bornes CHECK (heure_debut >= '08:00:00' AND heure_fin <= '17:00:00')
);

-- COURS, le pivot : CONCERNER, ENSEIGNER et PORTER SUR sont des (1,1)-(0,n)
-- -> trois FK NOT NULL, non uniques (règle R2)
CREATE TABLE cours (
  id_cours        INTEGER,
  type_cours      TEXT    NOT NULL DEFAULT 'cours',
  annee_scolaire  CHAR(9) NOT NULL,
  id_matiere      INTEGER NOT NULL,
  id_professeur   INTEGER NOT NULL,
  id_classe       INTEGER NOT NULL,
  CONSTRAINT pk_cours PRIMARY KEY (id_cours),
  CONSTRAINT uq_cours UNIQUE (id_classe, id_matiere, type_cours, annee_scolaire),
  CONSTRAINT chk_cours_type  CHECK (type_cours IN ('cours', 'TD', 'TP')),
  CONSTRAINT chk_cours_annee CHECK (
    annee_scolaire GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
    AND CAST(substr(annee_scolaire, 6, 4) AS INTEGER) = CAST(substr(annee_scolaire, 1, 4) AS INTEGER) + 1),
  CONSTRAINT fk_cours_matiere FOREIGN KEY (id_matiere)
    REFERENCES matiere (id_matiere) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_cours_professeur FOREIGN KEY (id_professeur)
    REFERENCES professeur (id_professeur) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_cours_classe FOREIGN KEY (id_classe)
    REFERENCES classe (id_classe) ON UPDATE CASCADE ON DELETE RESTRICT
);
CREATE INDEX idx_cours_professeur ON cours (id_professeur);

-- ---------------------------------------------------------------------
-- 2. Tables issues des ASSOCIATIONS (règle R4)
-- ---------------------------------------------------------------------

-- PLANIFIER (Cours, Créneau, Salle) + CIF (Cours, Créneau) -> Salle
-- -> clé (id_cours, id_creneau), id_salle simple FK NOT NULL (règle R6)
CREATE TABLE planifier (
  id_cours    INTEGER NOT NULL,
  id_creneau  INTEGER NOT NULL,
  id_salle    INTEGER NOT NULL,
  CONSTRAINT pk_planifier PRIMARY KEY (id_cours, id_creneau),
  CONSTRAINT fk_planifier_cours FOREIGN KEY (id_cours)
    REFERENCES cours (id_cours) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_planifier_creneau FOREIGN KEY (id_creneau)
    REFERENCES creneau (id_creneau) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_planifier_salle FOREIGN KEY (id_salle)
    REFERENCES salle (id_salle) ON UPDATE CASCADE ON DELETE RESTRICT
);
CREATE INDEX idx_planifier_creneau_salle ON planifier (id_creneau, id_salle);

-- ÊTRE DISPONIBLE (Professeur, Créneau) (0,n)-(0,n), sans attribut
CREATE TABLE etre_disponible (
  id_professeur  INTEGER NOT NULL,
  id_creneau     INTEGER NOT NULL,
  CONSTRAINT pk_etre_disponible PRIMARY KEY (id_professeur, id_creneau),
  CONSTRAINT fk_dispo_professeur FOREIGN KEY (id_professeur)
    REFERENCES professeur (id_professeur) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_dispo_creneau FOREIGN KEY (id_creneau)
    REFERENCES creneau (id_creneau) ON UPDATE CASCADE ON DELETE CASCADE
);

-- ÉVALUER (Élève, Cours, Calendrier) : CALENDRIER, réduit à sa date,
-- entre dans la clé sans table propre (règle R5)
CREATE TABLE evaluer (
  id_eleve         INTEGER      NOT NULL,
  id_cours         INTEGER      NOT NULL,
  date_evaluation  DATE         NOT NULL,
  note             DECIMAL(4,2) NOT NULL,
  appreciation     VARCHAR(255) NULL,
  CONSTRAINT pk_evaluer PRIMARY KEY (id_eleve, id_cours, date_evaluation),
  CONSTRAINT chk_evaluer_date CHECK (date(date_evaluation) IS date_evaluation),
  CONSTRAINT chk_evaluer_note CHECK (note BETWEEN 0 AND 20 AND round(note, 2) = note),
  CONSTRAINT fk_evaluer_eleve FOREIGN KEY (id_eleve)
    REFERENCES eleve (id_eleve) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_evaluer_cours FOREIGN KEY (id_cours)
    REFERENCES cours (id_cours) ON UPDATE CASCADE ON DELETE RESTRICT
);
CREATE INDEX idx_evaluer_cours_date ON evaluer (id_cours, date_evaluation);

-- S'ABSENTER (Élève, Cours, Calendrier) — même principe
CREATE TABLE s_absenter (
  id_eleve        INTEGER      NOT NULL,
  id_cours        INTEGER      NOT NULL,
  date_absence    DATE         NOT NULL,
  type_absence    TEXT         NOT NULL,
  minutes_retard  SMALLINT     NULL,
  motif           VARCHAR(255) NULL,
  justifiee       BOOLEAN      NOT NULL DEFAULT 0,
  CONSTRAINT pk_s_absenter PRIMARY KEY (id_eleve, id_cours, date_absence),
  CONSTRAINT chk_absence_date CHECK (date(date_absence) IS date_absence),
  CONSTRAINT chk_absence_type CHECK (type_absence IN ('absence', 'retard')),
  -- IS NOT NULL indispensable : un CHECK laisse passer un résultat NULL
  CONSTRAINT chk_absence_retard CHECK (
       (type_absence = 'retard'  AND minutes_retard IS NOT NULL AND minutes_retard BETWEEN 1 AND 240)
    OR (type_absence = 'absence' AND minutes_retard IS NULL)),
  CONSTRAINT chk_absence_justifiee CHECK (justifiee IN (0, 1)),
  CONSTRAINT fk_absenter_eleve FOREIGN KEY (id_eleve)
    REFERENCES eleve (id_eleve) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_absenter_cours FOREIGN KEY (id_cours)
    REFERENCES cours (id_cours) ON UPDATE CASCADE ON DELETE RESTRICT
);
CREATE INDEX idx_absenter_cours_date ON s_absenter (id_cours, date_absence);

-- ---------------------------------------------------------------------
-- 3. Règles de gestion non exprimables par une clé ou un CHECK
--    -> déclencheurs. RAISE(ABORT, ...) annule l'instruction en cours.
-- ---------------------------------------------------------------------

-- RG02 : une classe ne dépasse pas son effectif maximal
CREATE TRIGGER trg_eleve_effectif_bi BEFORE INSERT ON eleve
BEGIN
  SELECT RAISE(ABORT, 'Effectif maximal de la classe atteint')
  WHERE (SELECT COUNT(*) FROM eleve e WHERE e.id_classe = NEW.id_classe)
     >= (SELECT c.effectif_max FROM classe c WHERE c.id_classe = NEW.id_classe);
END;

CREATE TRIGGER trg_eleve_effectif_bu BEFORE UPDATE OF id_classe ON eleve
WHEN NEW.id_classe <> OLD.id_classe
BEGIN
  SELECT RAISE(ABORT, 'Effectif maximal de la classe atteint')
  WHERE (SELECT COUNT(*) FROM eleve e WHERE e.id_classe = NEW.id_classe)
     >= (SELECT c.effectif_max FROM classe c WHERE c.id_classe = NEW.id_classe);
END;

-- RG02 (suite) : on ne réduit pas effectif_max sous le nombre d'élèves inscrits
CREATE TRIGGER trg_classe_effectif_bu BEFORE UPDATE OF effectif_max ON classe
BEGIN
  SELECT RAISE(ABORT, 'Effectif maximal inférieur au nombre d''élèves de la classe')
  WHERE NEW.effectif_max < (SELECT COUNT(*) FROM eleve e WHERE e.id_classe = NEW.id_classe);
END;

-- RG34 : le compte d'un élève a le rôle 'eleve', celui d'un prof le rôle 'professeur'
CREATE TRIGGER trg_eleve_role_bi BEFORE INSERT ON eleve
WHEN NEW.id_utilisateur IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'Ce compte utilisateur n''a pas le rôle attendu')
  WHERE NOT EXISTS (SELECT 1 FROM utilisateur u
                    WHERE u.id_utilisateur = NEW.id_utilisateur AND u.role = 'eleve');
END;

CREATE TRIGGER trg_eleve_role_bu BEFORE UPDATE OF id_utilisateur ON eleve
WHEN NEW.id_utilisateur IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'Ce compte utilisateur n''a pas le rôle attendu')
  WHERE NOT EXISTS (SELECT 1 FROM utilisateur u
                    WHERE u.id_utilisateur = NEW.id_utilisateur AND u.role = 'eleve');
END;

CREATE TRIGGER trg_professeur_role_bi BEFORE INSERT ON professeur
WHEN NEW.id_utilisateur IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'Ce compte utilisateur n''a pas le rôle attendu')
  WHERE NOT EXISTS (SELECT 1 FROM utilisateur u
                    WHERE u.id_utilisateur = NEW.id_utilisateur AND u.role = 'professeur');
END;

CREATE TRIGGER trg_professeur_role_bu BEFORE UPDATE OF id_utilisateur ON professeur
WHEN NEW.id_utilisateur IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'Ce compte utilisateur n''a pas le rôle attendu')
  WHERE NOT EXISTS (SELECT 1 FROM utilisateur u
                    WHERE u.id_utilisateur = NEW.id_utilisateur AND u.role = 'professeur');
END;

-- RG25 / RG31 : on note et on pointe un élève seulement dans un cours de SA classe
CREATE TRIGGER trg_evaluer_bi BEFORE INSERT ON evaluer
BEGIN
  SELECT RAISE(ABORT, 'Cet élève ne suit pas ce cours (classe différente)')
  WHERE NOT EXISTS (SELECT 1 FROM eleve e JOIN cours c ON c.id_classe = e.id_classe
                    WHERE e.id_eleve = NEW.id_eleve AND c.id_cours = NEW.id_cours);
END;

CREATE TRIGGER trg_evaluer_bu BEFORE UPDATE OF id_eleve, id_cours ON evaluer
BEGIN
  SELECT RAISE(ABORT, 'Cet élève ne suit pas ce cours (classe différente)')
  WHERE NOT EXISTS (SELECT 1 FROM eleve e JOIN cours c ON c.id_classe = e.id_classe
                    WHERE e.id_eleve = NEW.id_eleve AND c.id_cours = NEW.id_cours);
END;

CREATE TRIGGER trg_absenter_bi BEFORE INSERT ON s_absenter
BEGIN
  SELECT RAISE(ABORT, 'Cet élève ne suit pas ce cours (classe différente)')
  WHERE NOT EXISTS (SELECT 1 FROM eleve e JOIN cours c ON c.id_classe = e.id_classe
                    WHERE e.id_eleve = NEW.id_eleve AND c.id_cours = NEW.id_cours);
END;

CREATE TRIGGER trg_absenter_bu BEFORE UPDATE OF id_eleve, id_cours ON s_absenter
BEGIN
  SELECT RAISE(ABORT, 'Cet élève ne suit pas ce cours (classe différente)')
  WHERE NOT EXISTS (SELECT 1 FROM eleve e JOIN cours c ON c.id_classe = e.id_classe
                    WHERE e.id_eleve = NEW.id_eleve AND c.id_cours = NEW.id_cours);
END;

-- Emploi du temps, vérifié dans cet ordre à chaque planification :
-- RG16 salle libre, RG17 prof libre, RG20 prof disponible,
-- RG21 capacité suffisante, RG18 classe libre.
CREATE TRIGGER trg_planifier_bi BEFORE INSERT ON planifier
BEGIN
  SELECT RAISE(ABORT, 'Cours inexistant')
  WHERE NOT EXISTS (SELECT 1 FROM cours WHERE id_cours = NEW.id_cours);

  SELECT RAISE(ABORT, 'Salle déjà occupée sur ce créneau')
  WHERE EXISTS (SELECT 1 FROM planifier p
                JOIN cours c  ON c.id_cours = p.id_cours
                JOIN cours cn ON cn.id_cours = NEW.id_cours
                WHERE p.id_creneau = NEW.id_creneau AND p.id_salle = NEW.id_salle
                  AND c.annee_scolaire = cn.annee_scolaire AND p.id_cours <> NEW.id_cours);

  SELECT RAISE(ABORT, 'Professeur déjà en cours sur ce créneau')
  WHERE EXISTS (SELECT 1 FROM planifier p
                JOIN cours c  ON c.id_cours = p.id_cours
                JOIN cours cn ON cn.id_cours = NEW.id_cours
                WHERE p.id_creneau = NEW.id_creneau AND c.id_professeur = cn.id_professeur
                  AND c.annee_scolaire = cn.annee_scolaire AND p.id_cours <> NEW.id_cours);

  SELECT RAISE(ABORT, 'Professeur non disponible sur ce créneau')
  WHERE NOT EXISTS (SELECT 1 FROM etre_disponible d
                    JOIN cours cn ON cn.id_professeur = d.id_professeur
                    WHERE cn.id_cours = NEW.id_cours AND d.id_creneau = NEW.id_creneau);

  SELECT RAISE(ABORT, 'Salle trop petite pour cette classe')
  WHERE (SELECT COUNT(*) FROM eleve e JOIN cours cn ON cn.id_classe = e.id_classe
         WHERE cn.id_cours = NEW.id_cours)
      > (SELECT s.capacite FROM salle s WHERE s.id_salle = NEW.id_salle);

  SELECT RAISE(ABORT, 'Classe déjà en cours sur ce créneau')
  WHERE EXISTS (SELECT 1 FROM planifier p
                JOIN cours c  ON c.id_cours = p.id_cours
                JOIN cours cn ON cn.id_cours = NEW.id_cours
                WHERE p.id_creneau = NEW.id_creneau AND c.id_classe = cn.id_classe
                  AND c.annee_scolaire = cn.annee_scolaire AND p.id_cours <> NEW.id_cours);
END;

-- Même contrôle quand on déplace une séance ; la ligne modifiée (OLD)
-- est ignorée pour ne pas entrer en conflit avec elle-même.
CREATE TRIGGER trg_planifier_bu BEFORE UPDATE ON planifier
BEGIN
  SELECT RAISE(ABORT, 'Cours inexistant')
  WHERE NOT EXISTS (SELECT 1 FROM cours WHERE id_cours = NEW.id_cours);

  SELECT RAISE(ABORT, 'Salle déjà occupée sur ce créneau')
  WHERE EXISTS (SELECT 1 FROM planifier p
                JOIN cours c  ON c.id_cours = p.id_cours
                JOIN cours cn ON cn.id_cours = NEW.id_cours
                WHERE p.id_creneau = NEW.id_creneau AND p.id_salle = NEW.id_salle
                  AND c.annee_scolaire = cn.annee_scolaire AND p.id_cours <> NEW.id_cours
                  AND NOT (p.id_cours = OLD.id_cours AND p.id_creneau = OLD.id_creneau));

  SELECT RAISE(ABORT, 'Professeur déjà en cours sur ce créneau')
  WHERE EXISTS (SELECT 1 FROM planifier p
                JOIN cours c  ON c.id_cours = p.id_cours
                JOIN cours cn ON cn.id_cours = NEW.id_cours
                WHERE p.id_creneau = NEW.id_creneau AND c.id_professeur = cn.id_professeur
                  AND c.annee_scolaire = cn.annee_scolaire AND p.id_cours <> NEW.id_cours
                  AND NOT (p.id_cours = OLD.id_cours AND p.id_creneau = OLD.id_creneau));

  SELECT RAISE(ABORT, 'Professeur non disponible sur ce créneau')
  WHERE NOT EXISTS (SELECT 1 FROM etre_disponible d
                    JOIN cours cn ON cn.id_professeur = d.id_professeur
                    WHERE cn.id_cours = NEW.id_cours AND d.id_creneau = NEW.id_creneau);

  SELECT RAISE(ABORT, 'Salle trop petite pour cette classe')
  WHERE (SELECT COUNT(*) FROM eleve e JOIN cours cn ON cn.id_classe = e.id_classe
         WHERE cn.id_cours = NEW.id_cours)
      > (SELECT s.capacite FROM salle s WHERE s.id_salle = NEW.id_salle);

  SELECT RAISE(ABORT, 'Classe déjà en cours sur ce créneau')
  WHERE EXISTS (SELECT 1 FROM planifier p
                JOIN cours c  ON c.id_cours = p.id_cours
                JOIN cours cn ON cn.id_cours = NEW.id_cours
                WHERE p.id_creneau = NEW.id_creneau AND c.id_classe = cn.id_classe
                  AND c.annee_scolaire = cn.annee_scolaire AND p.id_cours <> NEW.id_cours
                  AND NOT (p.id_cours = OLD.id_cours AND p.id_creneau = OLD.id_creneau));
END;

-- Fin : 12 tables, 5 index, 13 déclencheurs.
SELECT 'Base v1 créée' AS resultat,
       (SELECT COUNT(*) FROM sqlite_master WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%') AS nb_tables,
       (SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger') AS nb_declencheurs;
