-- =====================================================================
--  Problématique 2 — Évolution v2 : les spécialités (SQLite / SQLite Cloud)
--  Script de MIGRATION : modifie la base v1 sans la recréer.
--  Toutes les données (élèves, cours, 288 notes, absences) sont gardées.
--
--  À exécuter UNE SEULE FOIS, après 01 et 02, d'un seul bloc.
--  Tout se passe dans des transactions : en cas d'erreur, exécuter
--      ROLLBACK;
--      PRAGMA foreign_keys = ON;
--  et la base revient à son état d'avant.
--  Si le script a déjà tourné, il s'arrête à « table groupe already
--  exists » sans rien modifier : exécuter les deux lignes ci-dessus.
--
--  Principe : un cours ne s'adresse plus à une CLASSE mais à un GROUPE.
--   - groupe « classe »     : un par classe ; membres = élèves de la classe ;
--   - groupe « specialite » : membres = élèves inscrits (table inscrire).
-- =====================================================================

-- SQLite ne sait pas supprimer une colonne qui porte une clé étrangère :
-- la table cours est reconstruite. Les clés étrangères sont suspendues
-- pendant la reconstruction, puis tout est revérifié avant la fin.
PRAGMA foreign_keys = OFF;

BEGIN TRANSACTION;

-- ---------------------------------------------------------------------
-- Étape 1 — Nouvelle entité GROUPE et association ÊTRE INSCRIT
-- CORRESPONDRE (Groupe 0,1 – Classe 0,1) -> groupe.id_classe NULL + UNIQUE
-- Pour un groupe « classe », nom et niveau viennent de la classe (3FN).
-- ---------------------------------------------------------------------
CREATE TABLE groupe (
  id_groupe    INTEGER,
  type_groupe  TEXT        NOT NULL,
  nom_groupe   VARCHAR(40) NULL,
  niveau       VARCHAR(20) NULL,
  id_classe    INTEGER     NULL,
  CONSTRAINT pk_groupe PRIMARY KEY (id_groupe),
  CONSTRAINT uq_groupe_nom UNIQUE (nom_groupe),
  CONSTRAINT uq_groupe_classe UNIQUE (id_classe),
  CONSTRAINT chk_groupe_type CHECK (
       (type_groupe = 'classe'     AND id_classe IS NOT NULL AND nom_groupe IS NULL AND niveau IS NULL)
    OR (type_groupe = 'specialite' AND id_classe IS NULL AND nom_groupe IS NOT NULL AND niveau IS NOT NULL)),
  CONSTRAINT fk_groupe_classe FOREIGN KEY (id_classe)
    REFERENCES classe (id_classe) ON UPDATE CASCADE ON DELETE CASCADE
);

-- ÊTRE INSCRIT (Élève 0,2 – Groupe 0,n) -> table, clé = les deux identifiants
-- (le maximum 2 est contrôlé par déclencheur, voir RG38)
CREATE TABLE inscrire (
  id_eleve   INTEGER NOT NULL,
  id_groupe  INTEGER NOT NULL,
  CONSTRAINT pk_inscrire PRIMARY KEY (id_eleve, id_groupe),
  CONSTRAINT fk_inscrire_eleve FOREIGN KEY (id_eleve)
    REFERENCES eleve (id_eleve) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_inscrire_groupe FOREIGN KEY (id_groupe)
    REFERENCES groupe (id_groupe) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX idx_inscrire_groupe ON inscrire (id_groupe);

-- ---------------------------------------------------------------------
-- Étape 2 — Un groupe « classe entière » par classe existante
-- (id_groupe = id_classe pour la lisibilité)
-- ---------------------------------------------------------------------
INSERT INTO groupe (id_groupe, type_groupe, nom_groupe, niveau, id_classe)
SELECT c.id_classe, 'classe', NULL, NULL, c.id_classe
FROM classe c ORDER BY c.id_classe;

-- ---------------------------------------------------------------------
-- Étape 3 — COURS : CONCERNER relie désormais COURS (1,1) à GROUPE (0,n).
-- Les déclencheurs qui lisent cours.id_classe sont d'abord retirés,
-- puis la table est reconstruite (méthode officielle SQLite :
-- nouvelle table, copie, suppression, renommage).
-- ---------------------------------------------------------------------
DROP TRIGGER trg_planifier_bi;
DROP TRIGGER trg_planifier_bu;
DROP TRIGGER trg_evaluer_bi;
DROP TRIGGER trg_evaluer_bu;
DROP TRIGGER trg_absenter_bi;
DROP TRIGGER trg_absenter_bu;

CREATE TABLE cours_v2 (
  id_cours        INTEGER,
  type_cours      TEXT    NOT NULL DEFAULT 'cours',
  annee_scolaire  CHAR(9) NOT NULL,
  id_matiere      INTEGER NOT NULL,
  id_professeur   INTEGER NOT NULL,
  id_groupe       INTEGER NOT NULL,
  CONSTRAINT pk_cours PRIMARY KEY (id_cours),
  CONSTRAINT uq_cours UNIQUE (id_groupe, id_matiere, type_cours, annee_scolaire),
  CONSTRAINT chk_cours_type  CHECK (type_cours IN ('cours', 'TD', 'TP')),
  CONSTRAINT chk_cours_annee CHECK (
    annee_scolaire GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
    AND CAST(substr(annee_scolaire, 6, 4) AS INTEGER) = CAST(substr(annee_scolaire, 1, 4) AS INTEGER) + 1),
  CONSTRAINT fk_cours_matiere FOREIGN KEY (id_matiere)
    REFERENCES matiere (id_matiere) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_cours_professeur FOREIGN KEY (id_professeur)
    REFERENCES professeur (id_professeur) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_cours_groupe FOREIGN KEY (id_groupe)
    REFERENCES groupe (id_groupe) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- Chaque cours garde son numéro et passe au groupe de sa classe
INSERT INTO cours_v2 (id_cours, type_cours, annee_scolaire, id_matiere, id_professeur, id_groupe)
SELECT c.id_cours, c.type_cours, c.annee_scolaire, c.id_matiere, c.id_professeur, g.id_groupe
FROM cours c JOIN groupe g ON g.id_classe = c.id_classe;

DROP TABLE cours;
ALTER TABLE cours_v2 RENAME TO cours;
CREATE INDEX idx_cours_professeur ON cours (id_professeur);

-- ---------------------------------------------------------------------
-- Étape 4 — Vues : membres des groupes et cours suivis (calculés)
-- ---------------------------------------------------------------------
CREATE VIEW v_eleve_groupe AS
  SELECT e.id_eleve, g.id_groupe
  FROM eleve e JOIN groupe g ON g.id_classe = e.id_classe   -- tronc commun
  UNION ALL
  SELECT i.id_eleve, i.id_groupe FROM inscrire i;            -- spécialités

CREATE VIEW v_eleve_cours AS
  SELECT m.id_eleve, c.id_cours
  FROM v_eleve_groupe m JOIN cours c ON c.id_groupe = m.id_groupe;

CREATE VIEW v_groupe AS
  SELECT g.id_groupe, g.type_groupe,
         COALESCE(g.nom_groupe, cl.nom_classe) AS libelle,
         COALESCE(g.niveau, cl.niveau)         AS niveau
  FROM groupe g LEFT JOIN classe cl ON cl.id_classe = g.id_classe;

-- ---------------------------------------------------------------------
-- Étape 5 — Règles de gestion mises à jour
-- ---------------------------------------------------------------------

-- RG25 / RG31 : on note et on pointe un élève seulement dans un cours
-- de l'un de SES groupes (classe ou spécialité)
CREATE TRIGGER trg_evaluer_bi BEFORE INSERT ON evaluer
BEGIN
  SELECT RAISE(ABORT, 'Cet élève ne suit pas ce cours (ni sa classe ni ses spécialités)')
  WHERE NOT EXISTS (SELECT 1 FROM v_eleve_cours v
                    WHERE v.id_eleve = NEW.id_eleve AND v.id_cours = NEW.id_cours);
END;

CREATE TRIGGER trg_evaluer_bu BEFORE UPDATE OF id_eleve, id_cours ON evaluer
BEGIN
  SELECT RAISE(ABORT, 'Cet élève ne suit pas ce cours (ni sa classe ni ses spécialités)')
  WHERE NOT EXISTS (SELECT 1 FROM v_eleve_cours v
                    WHERE v.id_eleve = NEW.id_eleve AND v.id_cours = NEW.id_cours);
END;

CREATE TRIGGER trg_absenter_bi BEFORE INSERT ON s_absenter
BEGIN
  SELECT RAISE(ABORT, 'Cet élève ne suit pas ce cours (ni sa classe ni ses spécialités)')
  WHERE NOT EXISTS (SELECT 1 FROM v_eleve_cours v
                    WHERE v.id_eleve = NEW.id_eleve AND v.id_cours = NEW.id_cours);
END;

CREATE TRIGGER trg_absenter_bu BEFORE UPDATE OF id_eleve, id_cours ON s_absenter
BEGIN
  SELECT RAISE(ABORT, 'Cet élève ne suit pas ce cours (ni sa classe ni ses spécialités)')
  WHERE NOT EXISTS (SELECT 1 FROM v_eleve_cours v
                    WHERE v.id_eleve = NEW.id_eleve AND v.id_cours = NEW.id_cours);
END;

-- Emploi du temps. RG18 « une classe = un cours par créneau » est
-- remplacée par « un ÉLÈVE = un cours par créneau » : deux groupes de
-- spécialité d'une même classe peuvent avoir cours en même temps.
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

  SELECT RAISE(ABORT, 'Salle trop petite pour ce groupe')
  WHERE (SELECT COUNT(*) FROM v_eleve_groupe m JOIN cours cn ON cn.id_groupe = m.id_groupe
         WHERE cn.id_cours = NEW.id_cours)
      > (SELECT s.capacite FROM salle s WHERE s.id_salle = NEW.id_salle);

  SELECT RAISE(ABORT, 'Ce groupe a déjà cours sur ce créneau')
  WHERE EXISTS (SELECT 1 FROM planifier p
                JOIN cours c  ON c.id_cours = p.id_cours
                JOIN cours cn ON cn.id_cours = NEW.id_cours
                WHERE p.id_creneau = NEW.id_creneau AND c.id_groupe = cn.id_groupe
                  AND c.annee_scolaire = cn.annee_scolaire AND p.id_cours <> NEW.id_cours);

  SELECT RAISE(ABORT, 'Un élève de ce groupe a déjà cours sur ce créneau')
  WHERE EXISTS (SELECT 1 FROM planifier p
                JOIN cours c            ON c.id_cours = p.id_cours
                JOIN cours cn           ON cn.id_cours = NEW.id_cours
                JOIN v_eleve_groupe m2  ON m2.id_groupe = c.id_groupe
                JOIN v_eleve_groupe m1  ON m1.id_eleve = m2.id_eleve AND m1.id_groupe = cn.id_groupe
                WHERE p.id_creneau = NEW.id_creneau AND c.annee_scolaire = cn.annee_scolaire
                  AND p.id_cours <> NEW.id_cours);
END;

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

  SELECT RAISE(ABORT, 'Salle trop petite pour ce groupe')
  WHERE (SELECT COUNT(*) FROM v_eleve_groupe m JOIN cours cn ON cn.id_groupe = m.id_groupe
         WHERE cn.id_cours = NEW.id_cours)
      > (SELECT s.capacite FROM salle s WHERE s.id_salle = NEW.id_salle);

  SELECT RAISE(ABORT, 'Ce groupe a déjà cours sur ce créneau')
  WHERE EXISTS (SELECT 1 FROM planifier p
                JOIN cours c  ON c.id_cours = p.id_cours
                JOIN cours cn ON cn.id_cours = NEW.id_cours
                WHERE p.id_creneau = NEW.id_creneau AND c.id_groupe = cn.id_groupe
                  AND c.annee_scolaire = cn.annee_scolaire AND p.id_cours <> NEW.id_cours
                  AND NOT (p.id_cours = OLD.id_cours AND p.id_creneau = OLD.id_creneau));

  SELECT RAISE(ABORT, 'Un élève de ce groupe a déjà cours sur ce créneau')
  WHERE EXISTS (SELECT 1 FROM planifier p
                JOIN cours c            ON c.id_cours = p.id_cours
                JOIN cours cn           ON cn.id_cours = NEW.id_cours
                JOIN v_eleve_groupe m2  ON m2.id_groupe = c.id_groupe
                JOIN v_eleve_groupe m1  ON m1.id_eleve = m2.id_eleve AND m1.id_groupe = cn.id_groupe
                WHERE p.id_creneau = NEW.id_creneau AND c.annee_scolaire = cn.annee_scolaire
                  AND p.id_cours <> NEW.id_cours
                  AND NOT (p.id_cours = OLD.id_cours AND p.id_creneau = OLD.id_creneau));
END;

-- Inscriptions en spécialité, vérifiées dans cet ordre :
-- RG35 type, RG36 niveau, RG38 maximum 2, RG37 conflit d'horaire, RG39 places
CREATE TRIGGER trg_inscrire_bi BEFORE INSERT ON inscrire
BEGIN
  SELECT RAISE(ABORT, 'Inscription réservée aux spécialités (la classe entière est automatique)')
  WHERE (SELECT g.type_groupe FROM groupe g WHERE g.id_groupe = NEW.id_groupe) <> 'specialite';

  SELECT RAISE(ABORT, 'Cette spécialité n''est pas ouverte au niveau de l''élève')
  WHERE (SELECT g.niveau FROM groupe g WHERE g.id_groupe = NEW.id_groupe)
     <> (SELECT cl.niveau FROM eleve e JOIN classe cl ON cl.id_classe = e.id_classe
         WHERE e.id_eleve = NEW.id_eleve);

  SELECT RAISE(ABORT, 'Un élève suit au plus 2 spécialités')
  WHERE (SELECT COUNT(*) FROM inscrire i WHERE i.id_eleve = NEW.id_eleve) >= 2;

  SELECT RAISE(ABORT, 'Conflit d''emploi du temps : l''élève a déjà cours sur ces créneaux')
  WHERE EXISTS (SELECT 1
                FROM cours cn
                JOIN planifier pn     ON pn.id_cours = cn.id_cours
                JOIN planifier po     ON po.id_creneau = pn.id_creneau
                JOIN cours co         ON co.id_cours = po.id_cours
                                     AND co.annee_scolaire = cn.annee_scolaire
                JOIN v_eleve_groupe m ON m.id_groupe = co.id_groupe AND m.id_eleve = NEW.id_eleve
                WHERE cn.id_groupe = NEW.id_groupe AND co.id_groupe <> NEW.id_groupe);

  SELECT RAISE(ABORT, 'Groupe complet : la salle n''a plus de place')
  WHERE EXISTS (SELECT 1 FROM cours c
                JOIN planifier p ON p.id_cours = c.id_cours
                JOIN salle s     ON s.id_salle = p.id_salle
                WHERE c.id_groupe = NEW.id_groupe
                  AND s.capacite <= (SELECT COUNT(*) FROM v_eleve_groupe m
                                     WHERE m.id_groupe = NEW.id_groupe));
END;

-- Changer de spécialité = supprimer l'inscription puis réinscrire
CREATE TRIGGER trg_inscrire_bu BEFORE UPDATE ON inscrire
BEGIN
  SELECT RAISE(ABORT, 'Pour changer de spécialité : supprimer l''inscription puis réinscrire');
END;

-- RG40 : toute nouvelle classe reçoit son groupe « classe entière »
CREATE TRIGGER trg_classe_groupe_ai AFTER INSERT ON classe
BEGIN
  INSERT INTO groupe (type_groupe, nom_groupe, niveau, id_classe)
  VALUES ('classe', NULL, NULL, NEW.id_classe);
END;

COMMIT;

-- Clés étrangères réactivées ; la vérification ne doit rien renvoyer
PRAGMA foreign_keys = ON;
PRAGMA foreign_key_check;

-- ---------------------------------------------------------------------
-- Étape 6 — Données : ouverture des spécialités en 1ère A
-- Maths, Physique-Chimie et SVT deviennent des spécialités, en 2 barrettes :
--   barrette 1 : Spé Maths ET Spé SVT en même temps (mardi et jeudi 14 h)
--   barrette 2 : Spé PC (lundi et mercredi 8 h)
-- ---------------------------------------------------------------------
BEGIN TRANSACTION;

-- 6a. Séances du tronc commun Maths, PC, SVT de 1ère A retirées de
--     l'emploi du temps. Les cours 13, 16, 17, leurs notes et leurs
--     absences d'octobre restent en base (historique).
DELETE FROM planifier WHERE id_cours IN (13, 16, 17);

-- 6b. Les groupes de spécialité
INSERT INTO groupe (id_groupe, type_groupe, nom_groupe, niveau, id_classe) VALUES
(4, 'specialite', 'Spé Maths 1ère', 'Première', NULL),
(5, 'specialite', 'Spé PC 1ère',    'Première', NULL),
(6, 'specialite', 'Spé SVT 1ère',   'Première', NULL);

-- 6c. Les cours de spécialité
INSERT INTO cours (id_cours, type_cours, annee_scolaire, id_matiere, id_professeur, id_groupe) VALUES
(19, 'cours', '2026-2027', 1, 1, 4),   -- Spé Maths, M. Diop
(20, 'cours', '2026-2027', 4, 4, 5),   -- Spé PC, M. Fall
(21, 'cours', '2026-2027', 5, 5, 6);   -- Spé SVT, Mme Ba

-- 6d. Nouvelles disponibilités des professeurs
INSERT INTO etre_disponible (id_professeur, id_creneau) VALUES
(1, 6), (1, 12),    -- M. Diop : mardi et jeudi 14 h
(5, 6), (5, 12),    -- Mme Ba  : mardi et jeudi 14 h
(4, 1), (4, 7);     -- M. Fall : lundi et mercredi 8 h

-- 6e. Emploi du temps des spécialités
INSERT INTO planifier (id_cours, id_creneau, id_salle) VALUES
(19, 6, 3), (19, 12, 3),   -- Spé Maths, Salle 3   } en même temps :
(21, 6, 4), (21, 12, 4),   -- Spé SVT, Labo         } barrette 1
(20, 1, 4), (20, 7, 4);    -- Spé PC, Labo            barrette 2

-- 6f. Choix des élèves de 1ère A. Babacar n'a pas encore choisi sa
--     2e spécialité : la requête de contrôle D4 le signale.
INSERT INTO inscrire (id_eleve, id_groupe) VALUES
(17, 4), (17, 5),   -- Momodou : Maths + PC
(18, 6), (18, 5),   -- Fatou   : SVT + PC
(19, 6), (19, 5),   -- Awa
(20, 4), (20, 5),   -- Pape
(21, 6), (21, 5),   -- Ndeye
(22, 4), (22, 5),   -- Serigne
(23, 4), (23, 5),   -- Khady
(24, 4);            -- Babacar : Maths seulement pour l'instant

-- 6g. Premier devoir en Spé Maths et en Spé SVT (mardi 3 novembre 2026)
INSERT INTO evaluer (id_eleve, id_cours, date_evaluation, note, appreciation)
SELECT v.id_eleve, v.id_cours, '2026-11-03',
       8 + ((v.id_eleve * 13 + v.id_cours * 5) % 11),
       'Premier devoir de spécialité'
FROM v_eleve_cours v
WHERE v.id_cours IN (19, 21);

COMMIT;

-- Contrôle : effectifs attendus
-- 2nde A 8 | 2nde B 8 | 1ère A 8 | Spé Maths 5 | Spé PC 7 | Spé SVT 3
SELECT g.libelle, g.type_groupe, g.niveau, COUNT(m.id_eleve) AS effectif
FROM v_groupe g LEFT JOIN v_eleve_groupe m ON m.id_groupe = g.id_groupe
GROUP BY g.id_groupe, g.libelle, g.type_groupe, g.niveau
ORDER BY g.id_groupe;
