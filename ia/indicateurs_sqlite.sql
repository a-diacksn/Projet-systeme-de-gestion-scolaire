-- =====================================================================
-- Preuve de concept IA — Indicateurs de risque par élève (SQLite Cloud)
-- À exécuter après 01_creation_sqlite.sql, 02_jeu_de_test_sqlite.sql
-- et 04_evolution_specialites_sqlite.sql (fonctionne aussi sur la v1).
-- Rien n'est stocké : la vue recalcule tout à chaque lecture,
-- comme les moyennes (aucune redondance).
-- OPTIONNEL : le script Python et la soutenance utilisent indicateurs_requete.sql.
-- Si la console n'exécute qu'un ordre à la fois (SQLite Cloud), sélectionnez
-- et exécutez d'abord le bloc CREATE VIEW seul, puis le SELECT de vérification.
-- =====================================================================
DROP VIEW IF EXISTS v_indicateurs_eleve;
CREATE VIEW v_indicateurs_eleve AS
WITH
-- 1. Moyenne de chaque élève dans chaque matière
moy_matiere AS (
  SELECT ev.id_eleve, c.id_matiere, AVG(ev.note) AS moy
  FROM evaluer ev
  JOIN cours c ON c.id_cours = ev.id_cours
  GROUP BY ev.id_eleve, c.id_matiere
),
-- 2. Moyenne générale pondérée par les coefficients + matières sous 10
generale AS (
  SELECT mm.id_eleve,
         SUM(mm.moy * m.coefficient) / SUM(m.coefficient)  AS moyenne,
         SUM(CASE WHEN mm.moy < 10 THEN 1 ELSE 0 END)      AS nb_matieres_sous_10
  FROM moy_matiere mm
  JOIN matiere m ON m.id_matiere = mm.id_matiere
  GROUP BY mm.id_eleve
),
-- 3. Tendance : dernière note moins première note, dans chaque cours
--    où l'élève a au moins deux notes, puis moyenne sur ses cours
bornes AS (
  SELECT id_eleve, id_cours,
         MIN(date_evaluation) AS d_premiere,
         MAX(date_evaluation) AS d_derniere
  FROM evaluer
  GROUP BY id_eleve, id_cours
  HAVING COUNT(*) >= 2
),
tendance AS (
  SELECT b.id_eleve, AVG(e2.note - e1.note) AS tendance
  FROM bornes b
  JOIN evaluer e1 ON e1.id_eleve = b.id_eleve AND e1.id_cours = b.id_cours
                 AND e1.date_evaluation = b.d_premiere
  JOIN evaluer e2 ON e2.id_eleve = b.id_eleve AND e2.id_cours = b.id_cours
                 AND e2.date_evaluation = b.d_derniere
  GROUP BY b.id_eleve
),
-- 4. Assiduité
assiduite AS (
  SELECT id_eleve,
         SUM(CASE WHEN type_absence = 'absence' AND justifiee = 0 THEN 1 ELSE 0 END) AS absences_non_justifiees,
         SUM(CASE WHEN type_absence = 'absence' AND justifiee = 1 THEN 1 ELSE 0 END) AS absences_justifiees,
         SUM(CASE WHEN type_absence = 'retard'  AND justifiee = 0 THEN 1 ELSE 0 END) AS retards_non_justifies,
         COALESCE(SUM(minutes_retard), 0)                                           AS minutes_retard
  FROM s_absenter
  GROUP BY id_eleve
)
-- Une ligne par élève, même sans note ni absence
SELECT el.id_eleve,
       el.prenom,
       el.nom,
       cl.nom_classe,
       ROUND(g.moyenne, 2)                     AS moyenne,
       COALESCE(g.nb_matieres_sous_10, 0)      AS nb_matieres_sous_10,
       ROUND(COALESCE(t.tendance, 0), 2)       AS tendance,
       COALESCE(a.absences_non_justifiees, 0)  AS absences_non_justifiees,
       COALESCE(a.absences_justifiees, 0)      AS absences_justifiees,
       COALESCE(a.retards_non_justifies, 0)    AS retards_non_justifies,
       COALESCE(a.minutes_retard, 0)           AS minutes_retard
FROM eleve el
JOIN classe cl         ON cl.id_classe = el.id_classe
LEFT JOIN generale g   ON g.id_eleve  = el.id_eleve
LEFT JOIN tendance t   ON t.id_eleve  = el.id_eleve
LEFT JOIN assiduite a  ON a.id_eleve  = el.id_eleve;

-- Vérification
SELECT * FROM v_indicateurs_eleve ORDER BY moyenne;
