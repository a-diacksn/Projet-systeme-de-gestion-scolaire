-- =====================================================================
--  L11 / L12 — Tests des contraintes et des cardinalités (v1, SQLite)
--  À exécuter APRÈS 01_creation_sqlite.sql et 02_jeu_de_test_sqlite.sql
--
--  Partie A : chaque test DOIT ÉCHOUER. Le message noté « attendu »
--             entre crochets est l'erreur que SQLite doit afficher.
--             Exécuter les tests UN PAR UN (sélectionner l'instruction
--             puis exécuter) : un test réussi n'écrit rien en base.
--  Partie B : requêtes de démonstration, qui DOIVENT RÉUSSIR.
--
--  IMPORTANT : sur SQLite, les clés étrangères ne sont vérifiées que si
--  PRAGMA foreign_keys = ON a été exécuté sur la connexion. Si le test
--  T7 ne renvoie pas d'erreur, exécuter la ligne ci-dessous en même
--  temps que le test.
-- =====================================================================
PRAGMA foreign_keys = ON;

-- Doit afficher 1 (clés étrangères actives)
PRAGMA foreign_keys;

-- =====================================================================
-- A1. Domaines de valeurs (CHECK)
-- =====================================================================

-- T1 : note hors de [0 ; 20]  [attendu : chk_evaluer_note]
INSERT INTO evaluer VALUES (1, 1, '2026-11-02', 25, 'Note impossible');

-- T2 : retard sans durée  [attendu : chk_absence_retard]
INSERT INTO s_absenter VALUES (1, 1, '2026-11-02', 'retard', NULL, NULL, 0);

-- T3 : année scolaire incohérente  [attendu : chk_cours_annee]
INSERT INTO cours (type_cours, annee_scolaire, id_matiere, id_professeur, id_classe)
VALUES ('TD', '2026-2028', 1, 1, 1);

-- T4 : créneau hors des horaires de l'école  [attendu : chk_creneau_bornes]
INSERT INTO creneau (jour, heure_debut, heure_fin) VALUES ('lundi', '16:00:00', '18:00:00');

-- T5 : valeur hors liste (ancien ENUM)  [attendu : chk_eleve_sexe]
INSERT INTO eleve (nom, prenom, date_naissance, sexe, id_classe)
VALUES ('Test', 'Sexe', '2011-01-01', 'X', 1);

-- T6 : date impossible (30 février)  [attendu : chk_eleve_date]
INSERT INTO eleve (nom, prenom, date_naissance, sexe, id_classe)
VALUES ('Test', 'Date', '2011-02-30', 'M', 1);

-- =====================================================================
-- A2. Cardinalités du MCD
-- =====================================================================

-- T7 : APPARTENIR (1,1) — un élève dans une classe qui n'existe pas
--      [attendu : FOREIGN KEY constraint failed]
INSERT INTO eleve (nom, prenom, date_naissance, sexe, id_classe)
VALUES ('Test', 'Fantome', '2011-01-01', 'M', 99);

-- T8 : APPARTENIR (1,1) — un élève sans classe  [attendu : NOT NULL constraint failed: eleve.id_classe]
INSERT INTO eleve (nom, prenom, date_naissance, sexe)
VALUES ('Test', 'SansClasse', '2011-01-01', 'M');

-- T9 : ENSEIGNER (1,1) — un cours sans professeur  [attendu : NOT NULL constraint failed: cours.id_professeur]
INSERT INTO cours (type_cours, annee_scolaire, id_matiere, id_classe)
VALUES ('TD', '2026-2027', 1, 1);

-- T10 : ÊTRE PROF. PRINCIPAL (0,1) — un prof principal de deux classes
--       [attendu : UNIQUE constraint failed: classe.id_professeur_principal]
UPDATE classe SET id_professeur_principal = 2 WHERE id_classe = 2;

-- T11 : POSSÉDER (0,1) — un même compte pour deux élèves
--       [attendu : UNIQUE constraint failed: eleve.id_utilisateur]
UPDATE eleve SET id_utilisateur = 8 WHERE id_eleve = 1;

-- T12 : CIF de PLANIFIER — un cours dans une 2e salle au même créneau
--       [attendu : UNIQUE constraint failed: planifier.id_cours, planifier.id_creneau]
INSERT INTO planifier VALUES (1, 1, 5);

-- T13 : ÉVALUER — deux notes pour le même élève, cours et jour
--       [attendu : UNIQUE constraint failed: evaluer.id_eleve, evaluer.id_cours, evaluer.date_evaluation]
INSERT INTO evaluer VALUES (1, 1, '2026-10-05', 12, 'Doublon');

-- T14 : supprimer un élève qui a des notes (ON DELETE RESTRICT)
--       [attendu : FOREIGN KEY constraint failed]
DELETE FROM eleve WHERE id_eleve = 1;

-- =====================================================================
-- A3. Règles de gestion (déclencheurs)
-- =====================================================================

-- T15 : noter un élève de 2nde A dans un cours de 1ère A
--       [attendu : Cet élève ne suit pas ce cours]
INSERT INTO evaluer VALUES (1, 13, '2026-11-02', 14, 'Mauvais cours');

-- T16 : déplacer les Maths de 2nde A (lundi 8 h) dans la Salle 2, déjà prise
--       [attendu : Salle déjà occupée sur ce créneau]
UPDATE planifier SET id_salle = 2 WHERE id_cours = 1 AND id_creneau = 1;

-- T17 : M. Diop a déjà cours en 2nde A le lundi 8 h
--       [attendu : Professeur déjà en cours sur ce créneau]
INSERT INTO planifier VALUES (7, 1, 5);

-- T18 : M. Diop n'est pas disponible le mardi 8 h
--       [attendu : Professeur non disponible sur ce créneau]
INSERT INTO planifier VALUES (1, 4, 5);

-- T19 : 8 élèves dans la Salle de réunion (6 places)
--       [attendu : Salle trop petite pour cette classe]
UPDATE planifier SET id_salle = 6 WHERE id_cours = 1 AND id_creneau = 1;

-- T20 : lundi 10 h, la 2nde A a déjà Français
--       [attendu : Classe déjà en cours sur ce créneau]
INSERT INTO planifier VALUES (1, 2, 5);

-- T21 : ajouter 30 élèves en 2nde A (8 + 30 > 35 places). L'instruction
--       entière est annulée : aucun des 30 élèves n'est gardé.
--       [attendu : Effectif maximal de la classe atteint]
INSERT INTO eleve (nom, prenom, date_naissance, sexe, id_classe)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 30)
SELECT 'Test', 'Eleve ' || i, '2011-01-01', 'M', 1 FROM n;

-- T22 : réduire l'effectif maximal sous le nombre d'élèves
--       [attendu : Effectif maximal inférieur au nombre d'élèves]
UPDATE classe SET effectif_max = 5 WHERE id_classe = 1;

-- T23 : rattacher à un élève le compte d'un professeur
--       [attendu : Ce compte utilisateur n'a pas le rôle attendu]
UPDATE eleve SET id_utilisateur = 2 WHERE id_eleve = 1;

-- =====================================================================
-- B. Requêtes de démonstration (doivent réussir)
-- =====================================================================

-- V1 [doit réussir] : emploi du temps de la 1ère A
SELECT cr.jour, cr.heure_debut, cr.heure_fin, m.nom_matiere,
       p.prenom || ' ' || p.nom AS professeur, s.nom_salle
FROM planifier pl
JOIN cours c      ON c.id_cours = pl.id_cours
JOIN creneau cr   ON cr.id_creneau = pl.id_creneau
JOIN matiere m    ON m.id_matiere = c.id_matiere
JOIN professeur p ON p.id_professeur = c.id_professeur
JOIN salle s      ON s.id_salle = pl.id_salle
JOIN classe cl    ON cl.id_classe = c.id_classe
WHERE cl.nom_classe = '1ère A'
ORDER BY pl.id_creneau;

-- V2 [doit réussir] : bulletin de Momodou, moyenne par matière
SELECT m.nom_matiere, m.coefficient, round(AVG(ev.note), 2) AS moyenne
FROM evaluer ev
JOIN cours c   ON c.id_cours = ev.id_cours
JOIN matiere m ON m.id_matiere = c.id_matiere
WHERE ev.id_eleve = 17
GROUP BY m.id_matiere, m.nom_matiere, m.coefficient
ORDER BY m.id_matiere;

-- V3 [doit réussir] : moyenne générale pondérée de Momodou
SELECT round(SUM(t.moy * t.coef) / SUM(t.coef), 2) AS moyenne_generale
FROM (SELECT AVG(ev.note) AS moy, m.coefficient AS coef
      FROM evaluer ev
      JOIN cours c   ON c.id_cours = ev.id_cours
      JOIN matiere m ON m.id_matiere = c.id_matiere
      WHERE ev.id_eleve = 17
      GROUP BY m.id_matiere, m.coefficient) AS t;

-- V4 [doit réussir] : heures planifiées par semaine et heures prévues
SELECT cl.nom_classe, m.nom_matiere, m.volume_horaire_hebdo AS prevu_h,
       SUM(strftime('%s', cr.heure_fin) - strftime('%s', cr.heure_debut)) / 3600.0 AS planifie_h
FROM cours c
JOIN classe cl    ON cl.id_classe = c.id_classe
JOIN matiere m    ON m.id_matiere = c.id_matiere
JOIN planifier pl ON pl.id_cours = c.id_cours
JOIN creneau cr   ON cr.id_creneau = pl.id_creneau
GROUP BY cl.nom_classe, m.nom_matiere, m.volume_horaire_hebdo
ORDER BY cl.nom_classe, m.nom_matiere;

-- V5 [doit réussir] : toutes les clés étrangères du schéma
--     (chaque ligne = une cardinalité (x,1) du MCD)
SELECT m.name AS table_nom, f."from" AS colonne, f."table" AS table_ref,
       f."to" AS colonne_ref, f.on_delete
FROM sqlite_master m
JOIN pragma_foreign_key_list(m.name) f
WHERE m.type = 'table'
ORDER BY m.name, f."from";

-- V6 [doit réussir] : aucune ligne = aucune clé étrangère cassée
PRAGMA foreign_key_check;
