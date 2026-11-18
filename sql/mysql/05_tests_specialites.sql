-- =====================================================================
--  Démonstration du cas Momodou / Fatou + tests des nouvelles règles
--  À exécuter APRÈS 04_evolution_specialites.sql
--  Partie A : requêtes de démonstration (doivent RÉUSSIR)
--  Partie B : tests qui DOIVENT ÉCHOUER (un par un, Ctrl+Entrée)
--  Remplace le fichier 03 pour la version avec spécialités
--  (ses requêtes V1 et T10 utilisaient l'ancienne colonne cours.id_classe).
-- =====================================================================
USE gestion_scolaire;

-- ---------- A. Démonstration -----------------------------------------

-- D1 : emploi du temps de Momodou et de Fatou côte à côte.
-- Même classe, partie commune (tronc commun, Spé PC) et partie différente
-- (mardi et jeudi 14 h : Spé Maths pour Momodou, Spé SVT pour Fatou).
SELECT t.jour, t.heure_debut, t.momodou, t.fatou,
       CASE WHEN t.momodou IS NULL AND t.fatou IS NULL THEN '—'
            WHEN t.momodou = t.fatou                   THEN 'commun'
            ELSE 'différent' END AS comparaison
FROM (
  SELECT cr.id_creneau, cr.jour, cr.heure_debut,
         MAX(CASE WHEN v.id_eleve = 17 THEN CONCAT(m.nom_matiere,
             IF(g.type_groupe = 'specialite', ' (spé)', '')) END) AS momodou,
         MAX(CASE WHEN v.id_eleve = 18 THEN CONCAT(m.nom_matiere,
             IF(g.type_groupe = 'specialite', ' (spé)', '')) END) AS fatou
  FROM creneau cr
  LEFT JOIN planifier p      ON p.id_creneau = cr.id_creneau
  LEFT JOIN cours c          ON c.id_cours = p.id_cours
  LEFT JOIN groupe g         ON g.id_groupe = c.id_groupe
  LEFT JOIN matiere m        ON m.id_matiere = c.id_matiere
  LEFT JOIN v_eleve_cours v  ON v.id_cours = c.id_cours AND v.id_eleve IN (17, 18)
  GROUP BY cr.id_creneau, cr.jour, cr.heure_debut
) AS t
ORDER BY t.id_creneau;

-- D2 : emploi du temps de toute la 1ère A. Mardi et jeudi 14 h, la
-- classe a DEUX cours en même temps : c'était impossible dans la
-- version de base.
SELECT cr.jour, cr.heure_debut, vg.libelle AS groupe, m.nom_matiere,
       CONCAT(pr.prenom, ' ', pr.nom) AS professeur, s.nom_salle,
       (SELECT COUNT(*) FROM v_eleve_groupe x WHERE x.id_groupe = c.id_groupe) AS effectif
FROM planifier p
JOIN cours c       ON c.id_cours = p.id_cours
JOIN v_groupe vg   ON vg.id_groupe = c.id_groupe
JOIN creneau cr    ON cr.id_creneau = p.id_creneau
JOIN matiere m     ON m.id_matiere = c.id_matiere
JOIN professeur pr ON pr.id_professeur = c.id_professeur
JOIN salle s       ON s.id_salle = p.id_salle
WHERE c.id_groupe IN (SELECT DISTINCT m2.id_groupe
                      FROM v_eleve_groupe m2 JOIN eleve e ON e.id_eleve = m2.id_eleve
                      WHERE e.id_classe = 3)
ORDER BY p.id_creneau, vg.libelle;

-- D3 : les spécialités choisies par chaque élève de 1ère A
SELECT e.prenom, e.nom,
       GROUP_CONCAT(g.nom_groupe ORDER BY g.nom_groupe SEPARATOR ' + ') AS specialites,
       COUNT(i.id_groupe) AS nb
FROM eleve e
LEFT JOIN inscrire i ON i.id_eleve = e.id_eleve
LEFT JOIN groupe g   ON g.id_groupe = i.id_groupe
WHERE e.id_classe = 3
GROUP BY e.id_eleve, e.prenom, e.nom
ORDER BY e.nom;

-- D4 : contrôle : élèves de Première qui n'ont pas encore 2 spécialités
-- (le minimum ne peut pas être imposé à l'insertion ; on le contrôle ici)
SELECT e.id_eleve, e.prenom, e.nom, COUNT(i.id_groupe) AS nb_specialites
FROM eleve e
JOIN classe cl       ON cl.id_classe = e.id_classe
LEFT JOIN inscrire i ON i.id_eleve = e.id_eleve
WHERE cl.niveau = 'Première'
GROUP BY e.id_eleve, e.prenom, e.nom
HAVING COUNT(i.id_groupe) < 2;

-- D5 : les notes d'avant la migration sont toujours là
SELECT COUNT(*) AS nb_notes FROM evaluer;   -- 288 + 8 = 296

-- ---------- B. Tests qui doivent échouer -----------------------------

-- T1 : Momodou veut ajouter la Spé SVT. Elle tombe à la même heure que
--      sa Spé Maths -> « Conflit d'emploi du temps »
INSERT INTO inscrire VALUES (17, 6);

-- T2 : un élève de 2nde s'inscrit dans une spécialité de 1ère
--      -> « Cette spécialité n'est pas ouverte au niveau de l'élève »
INSERT INTO inscrire VALUES (1, 4);

-- T3 : inscrire Fatou à la main dans le groupe classe entière
--      -> « Inscription réservée aux spécialités »
INSERT INTO inscrire VALUES (18, 3);

-- T4 : noter Fatou en Spé Maths, qu'elle ne suit pas
--      -> « Cet élève ne suit pas ce cours »
INSERT INTO evaluer VALUES (18, 19, '2026-11-03', 15, 'Erreur de saisie');

-- T5 : une 3e spécialité -> « Un élève suit au plus 2 spécialités »
START TRANSACTION;
  INSERT INTO groupe (type_groupe, nom_groupe, niveau) VALUES ('specialite', 'Spé Test 1ère', 'Première');
  INSERT INTO inscrire VALUES (17, LAST_INSERT_ID());
ROLLBACK;

-- T6 : planifier la Spé Maths le mardi 8 h, pendant le Français de la 1ère A
--      -> « Un élève de ce groupe a déjà cours sur ce créneau »
START TRANSACTION;
  INSERT INTO etre_disponible VALUES (1, 4);
  INSERT INTO planifier VALUES (19, 4, 5);
ROLLBACK;

-- T7 : modifier une inscription au lieu de la supprimer
--      -> « Pour changer de spécialité : supprimer l'inscription puis réinscrire »
UPDATE inscrire SET id_groupe = 6 WHERE id_eleve = 17 AND id_groupe = 4;

-- T8 : un groupe classe entière ne peut pas porter de nom propre
--      -> Check constraint 'chk_groupe_type' is violated
INSERT INTO groupe (type_groupe, nom_groupe, id_classe) VALUES ('classe', 'Doublon', 1);

-- ---------- C. Bonus : création automatique du groupe d'une classe ---
START TRANSACTION;
  INSERT INTO classe (nom_classe, niveau, filiere, effectif_max) VALUES ('Tle A', 'Terminale', 'Générale', 35);
  SELECT * FROM v_groupe WHERE libelle = 'Tle A';   -- le groupe existe déjà
ROLLBACK;
