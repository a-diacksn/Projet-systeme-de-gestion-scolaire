-- Requête d'alerte (SQLite Cloud) : 3 absences non justifiées ou plus,
-- ou une moyenne en baisse de 2 points entre deux périodes.
-- La période se calcule depuis la date : aucune colonne ajoutée à evaluer.
WITH Notes AS (SELECT id_eleve, note,
         CASE WHEN date_evaluation < '2026-10-15' THEN 1 ELSE 2 END AS periode
       FROM evaluer),
CalculAbsences AS (SELECT id_eleve, COUNT(*) AS nb_absences
                   FROM s_absenter WHERE type_absence = 'absence' AND justifiee = 0
                   GROUP BY id_eleve),
NotesAnciennes AS (SELECT id_eleve, AVG(note) AS moyenne_t1 FROM Notes WHERE periode = 1 GROUP BY id_eleve),
NotesRecentes  AS (SELECT id_eleve, AVG(note) AS moyenne_t2 FROM Notes WHERE periode = 2 GROUP BY id_eleve)
SELECT e.id_eleve, e.nom, e.prenom,
       COALESCE(c.nb_absences, 0)                    AS absences_non_justifiees,
       ROUND(nr.moyenne_t2 - na.moyenne_t1, 1)        AS tendance
FROM eleve e
LEFT JOIN CalculAbsences c ON e.id_eleve = c.id_eleve
LEFT JOIN NotesAnciennes na ON e.id_eleve = na.id_eleve
LEFT JOIN NotesRecentes  nr ON e.id_eleve = nr.id_eleve
WHERE COALESCE(c.nb_absences, 0) >= 3
   OR COALESCE(nr.moyenne_t2 - na.moyenne_t1, 0) <= -2
ORDER BY absences_non_justifiees DESC, tendance ASC;
