-- =====================================================================
--  L11 / L12 — Tests des contraintes d'intégrité (démonstration jury)
--  À exécuter APRÈS 01_creation.sql et 02_jeu_de_test.sql
--
--  Chaque test DOIT ÉCHOUER : le message d'erreur prouve que la règle
--  est protégée par la base. Dans Workbench, exécuter les tests UN PAR
--  UN (curseur dans l'instruction puis Ctrl+Entrée).
--  Les tests qui modifient des données sont dans une transaction
--  annulée (ROLLBACK) : la base reste propre.
-- =====================================================================
USE gestion_scolaire;

-- ---------- A. Contraintes CHECK -------------------------------------

-- T1 : note hors de [0 ; 20]               -> chk_evaluer_note
INSERT INTO evaluer VALUES (1, 1, '2026-11-02', 25, 'Note impossible');

-- T2 : retard sans durée                    -> chk_absence_retard
INSERT INTO s_absenter VALUES (1, 1, '2026-11-02', 'retard', NULL, NULL, FALSE);

-- T3 : année scolaire incohérente           -> chk_cours_annee
INSERT INTO cours (type_cours, annee_scolaire, id_matiere, id_professeur, id_classe)
VALUES ('TD', '2026-2028', 1, 1, 1);

-- T4 : créneau hors des horaires de l'école -> chk_creneau_bornes
INSERT INTO creneau (jour, heure_debut, heure_fin) VALUES ('lundi', '16:00:00', '18:00:00');

-- ---------- B. Clés primaires, uniques et étrangères -----------------

-- T5 : deux notes pour le même élève, même cours, même jour -> PRIMARY KEY
INSERT INTO evaluer VALUES (1, 1, '2026-10-05', 12, 'Doublon');

-- T6 : élève dans une classe qui n'existe pas -> fk_eleve_classe
INSERT INTO eleve (nom, prenom, date_naissance, sexe, id_classe)
VALUES ('Test', 'Fantome', '2011-01-01', 'M', 99);

-- T7 : supprimer un élève qui a des notes -> ON DELETE RESTRICT
DELETE FROM eleve WHERE id_eleve = 1;

-- T8 : un prof principal de deux classes -> uq_classe_prof_principal
UPDATE classe SET id_professeur_principal = 2 WHERE id_classe = 2;

-- ---------- C. Règles de gestion (déclencheurs) ----------------------

-- T9 : noter un élève de 2nde A dans un cours de 1ère A
--      -> « Cet élève ne suit pas ce cours »
INSERT INTO evaluer VALUES (1, 13, '2026-11-02', 14, 'Mauvais cours');

-- T10 : salle déjà occupée (Salle 3, lundi 14 h, occupée par la 1ère A)
--       -> « Salle déjà occupée sur ce créneau »
INSERT INTO planifier VALUES (1, 3, 3);

-- T11 : prof déjà en cours (M. Diop fait cours en 2nde A le lundi 8 h)
--       -> « Professeur déjà en cours sur ce créneau »
INSERT INTO planifier VALUES (7, 1, 5);

-- T12 : prof non disponible, puis salle trop petite
START TRANSACTION;
  INSERT INTO creneau VALUES (16, 'samedi', '08:00:00', '10:00:00');
  INSERT INTO salle VALUES (6, 'Petit bureau', 'standard', 5);
  -- T12a : M. Diop n'est pas disponible le samedi -> « Professeur non disponible »
  INSERT INTO planifier VALUES (1, 16, 1);
  -- T12b : on le rend disponible, mais la salle n'a que 5 places pour 8 élèves
  INSERT INTO etre_disponible VALUES (1, 16);
  INSERT INTO planifier VALUES (1, 16, 6);   -- -> « Salle trop petite »
ROLLBACK;

-- T13 : effectif maximal atteint
START TRANSACTION;
  UPDATE classe SET effectif_max = 8 WHERE id_classe = 1;
  INSERT INTO eleve (nom, prenom, date_naissance, sexe, id_classe)
  VALUES ('Test', 'Neuvieme', '2011-01-01', 'F', 1);   -- -> « Effectif maximal »
ROLLBACK;

-- T14 : rattacher à un élève le compte d'un professeur
--       -> « Ce compte utilisateur n'a pas le rôle attendu »
UPDATE eleve SET id_utilisateur = 2 WHERE id_eleve = 1;

-- ---------- D. Vérifications positives (doivent RÉUSSIR) -------------

-- V1 : emploi du temps de la 1ère A
SELECT cr.jour, cr.heure_debut, cr.heure_fin, m.nom_matiere,
       CONCAT(p.prenom, ' ', p.nom) AS professeur, s.nom_salle
FROM planifier pl
JOIN cours c       ON c.id_cours = pl.id_cours
JOIN creneau cr    ON cr.id_creneau = pl.id_creneau
JOIN matiere m     ON m.id_matiere = c.id_matiere
JOIN professeur p  ON p.id_professeur = c.id_professeur
JOIN salle s       ON s.id_salle = pl.id_salle
JOIN classe cl     ON cl.id_classe = c.id_classe
WHERE cl.nom_classe = '1ère A'
ORDER BY pl.id_creneau;

-- V2 : bulletin de Momodou (moyenne par matière et moyenne générale pondérée)
SELECT m.nom_matiere, m.coefficient, ROUND(AVG(ev.note), 2) AS moyenne
FROM evaluer ev
JOIN cours c   ON c.id_cours = ev.id_cours
JOIN matiere m ON m.id_matiere = c.id_matiere
WHERE ev.id_eleve = 17
GROUP BY m.id_matiere, m.nom_matiere, m.coefficient
ORDER BY m.id_matiere;

SELECT ROUND(SUM(t.moy * t.coef) / SUM(t.coef), 2) AS moyenne_generale
FROM (SELECT AVG(ev.note) AS moy, m.coefficient AS coef
      FROM evaluer ev
      JOIN cours c   ON c.id_cours = ev.id_cours
      JOIN matiere m ON m.id_matiere = c.id_matiere
      WHERE ev.id_eleve = 17
      GROUP BY m.id_matiere, m.coefficient) AS t;

-- V3 : heures planifiées par cours comparées au volume horaire prévu
SELECT cl.nom_classe, m.nom_matiere, m.volume_horaire_hebdo AS prevu_h,
       SUM(TIME_TO_SEC(TIMEDIFF(cr.heure_fin, cr.heure_debut))) / 3600 AS planifie_h
FROM cours c
JOIN classe cl  ON cl.id_classe = c.id_classe
JOIN matiere m  ON m.id_matiere = c.id_matiere
JOIN planifier pl ON pl.id_cours = c.id_cours
JOIN creneau cr ON cr.id_creneau = pl.id_creneau
GROUP BY cl.nom_classe, m.nom_matiere, m.volume_horaire_hebdo
ORDER BY cl.nom_classe, m.nom_matiere;
