-- =====================================================================
--  Problématique 2 — Évolution de la base : les spécialités
--  Script de MIGRATION : modifie la base existante sans la recréer.
--  Toutes les données (élèves, cours, 288 notes, absences) sont gardées.
--
--  À exécuter UNE SEULE FOIS, après 01_creation.sql et 02_jeu_de_test.sql.
--  Garde-fou : si le script a déjà tourné, il s'arrête dès la 1re
--  instruction (« Table 'groupe' already exists ») sans rien modifier.
--
--  AVANT DE LANCER : faire une sauvegarde (les ALTER TABLE de MySQL
--  ne s'annulent pas) : Workbench > Server > Data Export > gestion_scolaire
--  ou en ligne de commande : mysqldump -u root -p gestion_scolaire > sauvegarde.sql
--
--  Principe : un cours ne s'adresse plus à une CLASSE mais à un GROUPE.
--   - groupe « classe entière » : un par classe, ses membres sont les
--     élèves de la classe (tronc commun) ;
--   - groupe « spécialité » : ses membres sont les élèves inscrits.
--  Momodou et Fatou sont dans le même groupe classe (1ère A) mais dans
--  des groupes de spécialité différents.
-- =====================================================================
USE gestion_scolaire;
SET SQL_SAFE_UPDATES = 0;   -- Workbench bloque sinon les UPDATE avec jointure

-- ---------------------------------------------------------------------
-- Étape 1 — Nouvelle entité GROUPE
-- Pour un groupe « classe », le nom et le niveau viennent de la classe
-- (pas de doublon : 3FN). Pour un groupe « spécialité », ils sont saisis.
-- ---------------------------------------------------------------------
CREATE TABLE groupe (
  id_groupe    INT          NOT NULL AUTO_INCREMENT,
  type_groupe  ENUM('classe', 'specialite') NOT NULL,
  nom_groupe   VARCHAR(40)  NULL,
  niveau       VARCHAR(20)  NULL,
  id_classe    INT          NULL,
  CONSTRAINT pk_groupe PRIMARY KEY (id_groupe),
  CONSTRAINT uq_groupe_nom UNIQUE (nom_groupe),
  CONSTRAINT uq_groupe_classe UNIQUE (id_classe),   -- un seul groupe par classe
  CONSTRAINT chk_groupe_type CHECK (
       (type_groupe = 'classe'     AND id_classe IS NOT NULL AND nom_groupe IS NULL AND niveau IS NULL)
    OR (type_groupe = 'specialite' AND id_classe IS NULL AND nom_groupe IS NOT NULL AND niveau IS NOT NULL)
  ),
  -- RESTRICT obligatoire : MySQL interdit CASCADE sur une colonne utilisée dans un CHECK
  CONSTRAINT fk_groupe_classe FOREIGN KEY (id_classe)
    REFERENCES classe (id_classe) ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE = InnoDB;

-- Nouvelle association ÊTRE INSCRIT (Élève, Groupe de spécialité)
CREATE TABLE inscrire (
  id_eleve   INT NOT NULL,
  id_groupe  INT NOT NULL,
  CONSTRAINT pk_inscrire PRIMARY KEY (id_eleve, id_groupe),
  CONSTRAINT fk_inscrire_eleve FOREIGN KEY (id_eleve)
    REFERENCES eleve (id_eleve) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_inscrire_groupe FOREIGN KEY (id_groupe)
    REFERENCES groupe (id_groupe) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- Étape 2 — Reprise des données : un groupe « classe entière » par
-- classe existante (id_groupe = id_classe pour la lisibilité)
-- ---------------------------------------------------------------------
INSERT INTO groupe (id_groupe, type_groupe, nom_groupe, niveau, id_classe)
SELECT c.id_classe, 'classe', NULL, NULL, c.id_classe
FROM classe c
ORDER BY c.id_classe;

-- ---------------------------------------------------------------------
-- Étape 3 — COURS : la FK id_classe est remplacée par id_groupe.
-- Chaque cours existant est rattaché au groupe de sa classe : aucune
-- information n'est perdue (classe = groupe.id_classe).
-- ---------------------------------------------------------------------
ALTER TABLE cours ADD COLUMN id_groupe INT NULL AFTER id_professeur;

UPDATE cours c
JOIN groupe g ON g.id_classe = c.id_classe
SET c.id_groupe = g.id_groupe;

ALTER TABLE cours DROP FOREIGN KEY fk_cours_classe;
ALTER TABLE cours DROP INDEX uq_cours;
-- échoue si un cours n'a pas reçu de groupe : sécurité avant la suppression
ALTER TABLE cours MODIFY id_groupe INT NOT NULL;
ALTER TABLE cours DROP COLUMN id_classe;
ALTER TABLE cours
  ADD CONSTRAINT uq_cours UNIQUE (id_groupe, id_matiere, type_cours, annee_scolaire);
ALTER TABLE cours
  ADD CONSTRAINT fk_cours_groupe FOREIGN KEY (id_groupe)
    REFERENCES groupe (id_groupe) ON UPDATE CASCADE ON DELETE RESTRICT;

-- ---------------------------------------------------------------------
-- Étape 4 — Vues : qui est membre de quel groupe, qui suit quel cours
-- (calculé, jamais stocké en double)
-- ---------------------------------------------------------------------
CREATE VIEW v_eleve_groupe AS
  SELECT e.id_eleve, g.id_groupe
  FROM eleve e JOIN groupe g ON g.id_classe = e.id_classe      -- tronc commun
  UNION ALL
  SELECT i.id_eleve, i.id_groupe FROM inscrire i;               -- spécialités

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
DELIMITER $$

-- RG25/RG31 : on note et on pointe un élève seulement dans un cours
-- de l'un de SES groupes (classe ou spécialité)
DROP PROCEDURE IF EXISTS verifier_eleve_du_cours$$
CREATE PROCEDURE verifier_eleve_du_cours(IN p_eleve INT, IN p_cours INT)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM v_eleve_cours v
                 WHERE v.id_eleve = p_eleve AND v.id_cours = p_cours) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cet élève ne suit pas ce cours (ni sa classe ni ses spécialités)';
  END IF;
END$$

-- Emploi du temps : l'ancienne règle « une classe = un cours par créneau »
-- devient « un ÉLÈVE = un cours par créneau ». Deux groupes de spécialité
-- de la même classe peuvent donc avoir cours en même temps.
DROP PROCEDURE IF EXISTS verifier_planification$$
CREATE PROCEDURE verifier_planification(
  IN p_cours INT, IN p_creneau INT, IN p_salle INT,
  IN p_old_cours INT, IN p_old_creneau INT)
BEGIN
  DECLARE v_prof INT;
  DECLARE v_groupe INT;
  DECLARE v_annee CHAR(9);
  DECLARE v_capacite INT;
  DECLARE v_effectif INT;

  SELECT c.id_professeur, c.id_groupe, c.annee_scolaire
    INTO v_prof, v_groupe, v_annee
    FROM cours c WHERE c.id_cours = p_cours;

  -- RG1 : salle libre
  IF EXISTS (SELECT 1 FROM planifier p JOIN cours c ON c.id_cours = p.id_cours
             WHERE p.id_creneau = p_creneau AND p.id_salle = p_salle
               AND c.annee_scolaire = v_annee AND p.id_cours <> p_cours
               AND NOT (p.id_cours <=> p_old_cours AND p.id_creneau <=> p_old_creneau)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Salle déjà occupée sur ce créneau';
  END IF;

  -- RG2 : professeur libre
  IF EXISTS (SELECT 1 FROM planifier p JOIN cours c ON c.id_cours = p.id_cours
             WHERE p.id_creneau = p_creneau AND c.id_professeur = v_prof
               AND c.annee_scolaire = v_annee AND p.id_cours <> p_cours
               AND NOT (p.id_cours <=> p_old_cours AND p.id_creneau <=> p_old_creneau)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Professeur déjà en cours sur ce créneau';
  END IF;

  -- RG3a : le groupe n'a qu'un cours par créneau
  IF EXISTS (SELECT 1 FROM planifier p JOIN cours c ON c.id_cours = p.id_cours
             WHERE p.id_creneau = p_creneau AND c.id_groupe = v_groupe
               AND c.annee_scolaire = v_annee AND p.id_cours <> p_cours
               AND NOT (p.id_cours <=> p_old_cours AND p.id_creneau <=> p_old_creneau)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ce groupe a déjà cours sur ce créneau';
  END IF;

  -- RG3b (remplace RG3) : aucun élève du groupe n'a déjà cours sur ce créneau
  IF EXISTS (SELECT 1 FROM planifier p
             JOIN cours c           ON c.id_cours = p.id_cours
             JOIN v_eleve_groupe m2 ON m2.id_groupe = c.id_groupe
             JOIN v_eleve_groupe m1 ON m1.id_eleve = m2.id_eleve AND m1.id_groupe = v_groupe
             WHERE p.id_creneau = p_creneau AND c.annee_scolaire = v_annee
               AND p.id_cours <> p_cours
               AND NOT (p.id_cours <=> p_old_cours AND p.id_creneau <=> p_old_creneau)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un élève de ce groupe a déjà cours sur ce créneau';
  END IF;

  -- RG4 : professeur disponible
  IF NOT EXISTS (SELECT 1 FROM etre_disponible d
                 WHERE d.id_professeur = v_prof AND d.id_creneau = p_creneau) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Professeur non disponible sur ce créneau';
  END IF;

  -- RG5 : la salle peut accueillir tout le GROUPE
  SELECT s.capacite INTO v_capacite FROM salle s WHERE s.id_salle = p_salle;
  SELECT COUNT(*) INTO v_effectif FROM v_eleve_groupe m WHERE m.id_groupe = v_groupe;
  IF v_effectif > v_capacite THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Salle trop petite pour ce groupe';
  END IF;
END$$

-- Nouvelles règles sur les inscriptions en spécialité
CREATE PROCEDURE verifier_inscription(IN p_eleve INT, IN p_groupe INT)
BEGIN
  DECLARE v_type VARCHAR(20);
  DECLARE v_niveau_groupe VARCHAR(20);
  DECLARE v_niveau_eleve VARCHAR(20);

  SELECT g.type_groupe, g.niveau INTO v_type, v_niveau_groupe
    FROM groupe g WHERE g.id_groupe = p_groupe;
  SELECT cl.niveau INTO v_niveau_eleve
    FROM eleve e JOIN classe cl ON cl.id_classe = e.id_classe
    WHERE e.id_eleve = p_eleve;

  -- RG35 : on ne s'inscrit qu'à un groupe de spécialité
  IF v_type <> 'specialite' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Inscription réservée aux spécialités (la classe entière est automatique)';
  END IF;

  -- RG36 : la spécialité est du niveau de la classe de l'élève
  IF v_niveau_groupe <> v_niveau_eleve THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cette spécialité n''est pas ouverte au niveau de l''élève';
  END IF;

  -- RG37 : la spécialité ne tombe pas sur un créneau où l'élève a déjà cours
  IF EXISTS (SELECT 1
             FROM cours cn
             JOIN planifier pn      ON pn.id_cours = cn.id_cours
             JOIN planifier po      ON po.id_creneau = pn.id_creneau
             JOIN cours co          ON co.id_cours = po.id_cours
                                   AND co.annee_scolaire = cn.annee_scolaire
             JOIN v_eleve_groupe m  ON m.id_groupe = co.id_groupe AND m.id_eleve = p_eleve
             WHERE cn.id_groupe = p_groupe) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Conflit d''emploi du temps : l''élève a déjà cours sur ces créneaux';
  END IF;

  -- RG38 : au plus 2 spécialités par élève
  IF (SELECT COUNT(*) FROM inscrire i WHERE i.id_eleve = p_eleve) >= 2 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un élève suit au plus 2 spécialités';
  END IF;

  -- RG39 : la salle des cours du groupe garde assez de places
  IF EXISTS (SELECT 1 FROM cours c
             JOIN planifier p ON p.id_cours = c.id_cours
             JOIN salle s     ON s.id_salle = p.id_salle
             WHERE c.id_groupe = p_groupe
               AND s.capacite <= (SELECT COUNT(*) FROM v_eleve_groupe m WHERE m.id_groupe = p_groupe)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Groupe complet : la salle n''a plus de place';
  END IF;
END$$

CREATE TRIGGER trg_inscrire_bi BEFORE INSERT ON inscrire FOR EACH ROW
BEGIN
  CALL verifier_inscription(NEW.id_eleve, NEW.id_groupe);
END$$

-- Changer de spécialité = supprimer l'inscription puis en créer une autre
CREATE TRIGGER trg_inscrire_bu BEFORE UPDATE ON inscrire FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Pour changer de spécialité : supprimer l''inscription puis réinscrire';
END$$

-- RG40 : toute nouvelle classe reçoit automatiquement son groupe « classe entière »
CREATE TRIGGER trg_classe_ai AFTER INSERT ON classe FOR EACH ROW
BEGIN
  INSERT INTO groupe (type_groupe, nom_groupe, niveau, id_classe)
  VALUES ('classe', NULL, NULL, NEW.id_classe);
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- Étape 6 — Données : ouverture des spécialités en 1ère A
-- Maths, Physique-Chimie et SVT y deviennent des spécialités.
-- Organisation en 2 « barrettes » :
--   barrette 1 : Spé Maths ET Spé SVT en même temps (mardi et jeudi 14 h)
--   barrette 2 : Spé PC (lundi et mercredi 8 h)
-- Choix possibles : Maths + PC ou SVT + PC.
-- ---------------------------------------------------------------------

-- 6a. Les séances du tronc commun Maths, PC et SVT de la 1ère A sont
--     retirées de l'emploi du temps. Les cours 13, 16, 17 et leurs notes
--     et absences d'octobre restent en base (historique).
DELETE FROM planifier WHERE id_cours IN (13, 16, 17);

-- 6b. Les trois groupes de spécialité
INSERT INTO groupe (id_groupe, type_groupe, nom_groupe, niveau, id_classe) VALUES
(4, 'specialite', 'Spé Maths 1ère', 'Première', NULL),
(5, 'specialite', 'Spé PC 1ère',    'Première', NULL),
(6, 'specialite', 'Spé SVT 1ère',   'Première', NULL);

-- 6c. Les cours de spécialité
INSERT INTO cours (id_cours, type_cours, annee_scolaire, id_matiere, id_professeur, id_groupe) VALUES
(19, 'cours', '2026-2027', 1, 1, 4),   -- Spé Maths, M. Diop
(20, 'cours', '2026-2027', 4, 4, 5),   -- Spé PC, M. Fall
(21, 'cours', '2026-2027', 5, 5, 6);   -- Spé SVT, Mme Ba

-- 6d. Nouvelles disponibilités déclarées par les professeurs
INSERT INTO etre_disponible (id_professeur, id_creneau) VALUES
(1, 6), (1, 12),    -- M. Diop : mardi et jeudi 14 h
(5, 6), (5, 12),    -- Mme Ba  : mardi et jeudi 14 h
(4, 1), (4, 7);     -- M. Fall : lundi et mercredi 8 h

-- 6e. Emploi du temps des spécialités
INSERT INTO planifier (id_cours, id_creneau, id_salle) VALUES
(19, 6, 3), (19, 12, 3),   -- Spé Maths, Salle 3    } en même temps :
(21, 6, 4), (21, 12, 4),   -- Spé SVT, Labo          } barrette 1
(20, 1, 4), (20, 7, 4);    -- Spé PC, Labo             barrette 2

-- 6f. Choix des élèves de 1ère A
INSERT INTO inscrire (id_eleve, id_groupe) VALUES
(17, 4), (17, 5),   -- Momodou : Maths + PC
(18, 6), (18, 5),   -- Fatou   : SVT + PC
(19, 6), (19, 5),   -- Awa
(20, 4), (20, 5),   -- Pape
(21, 6), (21, 5),   -- Ndeye
(22, 4), (22, 5),   -- Serigne
(23, 4), (23, 5),   -- Khady
(24, 6), (24, 5);   -- Babacar

-- 6g. Un premier devoir en Spé Maths et en Spé SVT (mardi 3 novembre 2026)
INSERT INTO evaluer (id_eleve, id_cours, date_evaluation, note, appreciation)
SELECT v.id_eleve, v.id_cours, '2026-11-03',
       ROUND(8 + MOD(v.id_eleve * 13 + v.id_cours * 5, 11), 2),
       'Premier devoir de spécialité'
FROM v_eleve_cours v
WHERE v.id_cours IN (19, 21);

SET SQL_SAFE_UPDATES = 1;

-- Contrôle : groupes et effectifs attendus
-- 2nde A 8 | 2nde B 8 | 1ère A 8 | Spé Maths 4 | Spé PC 8 | Spé SVT 4
SELECT g.libelle, g.type_groupe, g.niveau, COUNT(m.id_eleve) AS effectif
FROM v_groupe g LEFT JOIN v_eleve_groupe m ON m.id_groupe = g.id_groupe
GROUP BY g.id_groupe, g.libelle, g.type_groupe, g.niveau
ORDER BY g.id_groupe;
