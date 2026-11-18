-- =====================================================================
--  L10 — Script d'alimentation : jeu de données de test
--  École rurale, 3 classes, année 2026-2027 (version de base)
--  À exécuter APRÈS 01_creation.sql
--  Toutes les personnes et adresses sont fictives.
-- =====================================================================
USE gestion_scolaire;

-- ---------------------------------------------------------------------
-- Comptes utilisateurs
-- Mot de passe de démonstration pour tous : Demo2026!
-- SHA2 sert uniquement pour la démo : en production, l'application
-- calcule un hash bcrypt/argon2 avec sel, jamais la base.
-- ---------------------------------------------------------------------
INSERT INTO utilisateur (id_utilisateur, login, mot_de_passe_hash, email, role) VALUES
(1,  'direction',   SHA2('Demo2026!', 256), 'direction@ecole.example',   'admin'),
(2,  'm.diop',      SHA2('Demo2026!', 256), 'm.diop@ecole.example',      'professeur'),
(3,  'a.ndiaye',    SHA2('Demo2026!', 256), 'a.ndiaye@ecole.example',    'professeur'),
(4,  'o.sarr',      SHA2('Demo2026!', 256), 'o.sarr@ecole.example',      'professeur'),
(5,  'i.fall',      SHA2('Demo2026!', 256), 'i.fall@ecole.example',      'professeur'),
(6,  'm.ba',        SHA2('Demo2026!', 256), 'm.ba@ecole.example',        'professeur'),
(7,  'c.sow',       SHA2('Demo2026!', 256), 'c.sow@ecole.example',       'professeur'),
(8,  'momodou.diallo',  SHA2('Demo2026!', 256), 'momodou.diallo@ecole.example',  'eleve'),
(9,  'fatou.sene',      SHA2('Demo2026!', 256), 'fatou.sene@ecole.example',      'eleve'),
(10, 'awa.gueye',       SHA2('Demo2026!', 256), 'awa.gueye@ecole.example',       'eleve'),
(11, 'pape.thiam',      SHA2('Demo2026!', 256), 'pape.thiam@ecole.example',      'eleve'),
(12, 'ndeye.faye',      SHA2('Demo2026!', 256), 'ndeye.faye@ecole.example',      'eleve'),
(13, 'serigne.mbaye',   SHA2('Demo2026!', 256), 'serigne.mbaye@ecole.example',   'eleve'),
(14, 'khady.ciss',      SHA2('Demo2026!', 256), 'khady.ciss@ecole.example',      'eleve'),
(15, 'babacar.niang',   SHA2('Demo2026!', 256), 'babacar.niang@ecole.example',   'eleve');

-- ---------------------------------------------------------------------
-- Professeurs (un par matière)
-- ---------------------------------------------------------------------
INSERT INTO professeur (id_professeur, nom, prenom, date_naissance, telephone, specialite, id_utilisateur) VALUES
(1, 'Diop',   'Mamadou',  '1982-03-14', '+221 77 123 45 01', 'Mathématiques',        2),
(2, 'Ndiaye', 'Aminata',  '1987-07-02', '+221 77 123 45 02', 'Français',             3),
(3, 'Sarr',   'Ousmane',  '1990-11-25', '+221 76 123 45 03', 'Anglais',              4),
(4, 'Fall',   'Ibrahima', '1979-01-09', '+221 78 123 45 04', 'Physique-Chimie',      5),
(5, 'Ba',     'Mariama',  '1985-05-30', '+221 77 123 45 05', 'SVT',                  6),
(6, 'Sow',    'Cheikh',   '1983-09-18', '+221 70 123 45 06', 'Histoire-Géographie',  7);

-- ---------------------------------------------------------------------
-- Classes (prof principal : 0 ou 1 par classe, une classe max par prof)
-- ---------------------------------------------------------------------
INSERT INTO classe (id_classe, nom_classe, niveau, filiere, effectif_max, id_professeur_principal) VALUES
(1, '2nde A', 'Seconde',  'Générale', 35, 2),
(2, '2nde B', 'Seconde',  'Générale', 35, 6),
(3, '1ère A', 'Première', 'Générale', 35, 1);

-- ---------------------------------------------------------------------
-- Élèves : 8 par classe. Momodou et Fatou sont en 1ère A
-- (ils serviront pour le cas des spécialités).
-- ---------------------------------------------------------------------
INSERT INTO eleve (id_eleve, nom, prenom, date_naissance, lieu_naissance, sexe, adresse, id_classe, id_utilisateur) VALUES
-- 2nde A
(1,  'Ndour',   'Aliou',      '2011-02-11', 'Ndiaganiao', 'M', 'Quartier Escale, Ndiaganiao', 1, NULL),
(2,  'Diouf',   'Mame Diarra','2010-09-03', 'Thiès',      'F', 'Village de Sessène',          1, NULL),
(3,  'Kane',    'Ibrahima',   '2011-05-27', 'Mbour',      'M', 'Quartier Médine, Ndiaganiao', 1, NULL),
(4,  'Sy',      'Coumba',     '2010-12-19', 'Ndiaganiao', 'F', 'Village de Ngoyé',            1, NULL),
(5,  'Faye',    'Modou',      '2011-07-08', 'Fatick',     'M', 'Village de Sessène',          1, NULL),
(6,  'Mbengue', 'Astou',      '2011-01-30', 'Ndiaganiao', 'F', 'Quartier Escale, Ndiaganiao', 1, NULL),
(7,  'Tine',    'Joseph',     '2010-10-14', 'Khombole',   'M', 'Village de Ngoyé',            1, NULL),
(8,  'Dione',   'Rokhaya',    '2011-04-22', 'Ndiaganiao', 'F', 'Village de Pout',             1, NULL),
-- 2nde B
(9,  'Gaye',    'Mor',        '2010-08-16', 'Thiès',      'M', 'Village de Pout',             2, NULL),
(10, 'Camara',  'Seynabou',   '2011-03-05', 'Ndiaganiao', 'F', 'Quartier Médine, Ndiaganiao', 2, NULL),
(11, 'Wade',    'Lamine',     '2011-06-29', 'Tivaouane',  'M', 'Village de Sessène',          2, NULL),
(12, 'Sall',    'Adama',      '2010-11-11', 'Ndiaganiao', 'F', 'Village de Ngoyé',            2, NULL),
(13, 'Diatta',  'Ousmane',    '2011-02-02', 'Mbour',      'M', 'Quartier Escale, Ndiaganiao', 2, NULL),
(14, 'Seck',    'Bineta',     '2010-12-24', 'Fatick',     'F', 'Village de Pout',             2, NULL),
(15, 'Ndao',    'Cheikh',     '2011-08-17', 'Ndiaganiao', 'M', 'Village de Sessène',          2, NULL),
(16, 'Badji',   'Marie',      '2011-05-09', 'Khombole',   'F', 'Quartier Médine, Ndiaganiao', 2, NULL),
-- 1ère A (élèves ayant un compte)
(17, 'Diallo',  'Momodou',    '2010-01-12', 'Ndiaganiao', 'M', 'Village de Ngoyé',            3, 8),
(18, 'Sene',    'Fatou',      '2009-10-21', 'Thiès',      'F', 'Quartier Escale, Ndiaganiao', 3, 9),
(19, 'Gueye',   'Awa',        '2010-04-03', 'Ndiaganiao', 'F', 'Village de Sessène',          3, 10),
(20, 'Thiam',   'Pape',       '2009-12-28', 'Mbour',      'M', 'Village de Pout',             3, 11),
(21, 'Faye',    'Ndeye',      '2010-06-15', 'Fatick',     'F', 'Quartier Médine, Ndiaganiao', 3, 12),
(22, 'Mbaye',   'Serigne',    '2010-02-07', 'Ndiaganiao', 'M', 'Village de Ngoyé',            3, 13),
(23, 'Ciss',    'Khady',      '2009-11-30', 'Tivaouane',  'F', 'Village de Sessène',          3, 14),
(24, 'Niang',   'Babacar',    '2010-03-19', 'Ndiaganiao', 'M', 'Quartier Escale, Ndiaganiao', 3, 15);

-- ---------------------------------------------------------------------
-- Matières, salles, créneaux
-- Journée 8 h – 16 h avec pause méridienne 12 h – 14 h, sans samedi
-- (à ajuster selon votre proposition d'organisation L5)
-- ---------------------------------------------------------------------
INSERT INTO matiere (id_matiere, nom_matiere, coefficient, volume_horaire_hebdo, description) VALUES
(1, 'Mathématiques',       4, 6.0, 'Algèbre, analyse, géométrie'),
(2, 'Français',            3, 4.0, 'Langue, littérature, expression écrite'),
(3, 'Anglais',             2, 4.0, 'Langue vivante 1'),
(4, 'Physique-Chimie',     3, 4.0, 'Cours et travaux pratiques en laboratoire'),
(5, 'SVT',                 3, 4.0, 'Sciences de la vie et de la Terre'),
(6, 'Histoire-Géographie', 2, 4.0, 'Histoire, géographie, éducation civique');

INSERT INTO salle (id_salle, nom_salle, type_salle, capacite) VALUES
(1, 'Salle 1',            'standard', 40),
(2, 'Salle 2',            'standard', 40),
(3, 'Salle 3',            'standard', 40),
(4, 'Labo Sciences',      'labo',     30),
(5, 'Salle Informatique', 'info',     20);

INSERT INTO creneau (id_creneau, jour, heure_debut, heure_fin) VALUES
(1,  'lundi',    '08:00:00', '10:00:00'),
(2,  'lundi',    '10:00:00', '12:00:00'),
(3,  'lundi',    '14:00:00', '16:00:00'),
(4,  'mardi',    '08:00:00', '10:00:00'),
(5,  'mardi',    '10:00:00', '12:00:00'),
(6,  'mardi',    '14:00:00', '16:00:00'),
(7,  'mercredi', '08:00:00', '10:00:00'),
(8,  'mercredi', '10:00:00', '12:00:00'),
(9,  'mercredi', '14:00:00', '16:00:00'),
(10, 'jeudi',    '08:00:00', '10:00:00'),
(11, 'jeudi',    '10:00:00', '12:00:00'),
(12, 'jeudi',    '14:00:00', '16:00:00'),
(13, 'vendredi', '08:00:00', '10:00:00'),
(14, 'vendredi', '10:00:00', '12:00:00'),
(15, 'vendredi', '14:00:00', '16:00:00');

-- ---------------------------------------------------------------------
-- Cours (le pivot) : 6 matières x 3 classes = 18 cours
-- id_cours 1-6 : 2nde A, 7-12 : 2nde B, 13-18 : 1ère A
-- ---------------------------------------------------------------------
INSERT INTO cours (id_cours, type_cours, annee_scolaire, id_matiere, id_professeur, id_classe) VALUES
(1,  'cours', '2026-2027', 1, 1, 1),
(2,  'cours', '2026-2027', 2, 2, 1),
(3,  'cours', '2026-2027', 3, 3, 1),
(4,  'cours', '2026-2027', 4, 4, 1),
(5,  'cours', '2026-2027', 5, 5, 1),
(6,  'cours', '2026-2027', 6, 6, 1),
(7,  'cours', '2026-2027', 1, 1, 2),
(8,  'cours', '2026-2027', 2, 2, 2),
(9,  'cours', '2026-2027', 3, 3, 2),
(10, 'cours', '2026-2027', 4, 4, 2),
(11, 'cours', '2026-2027', 5, 5, 2),
(12, 'cours', '2026-2027', 6, 6, 2),
(13, 'cours', '2026-2027', 1, 1, 3),
(14, 'cours', '2026-2027', 2, 2, 3),
(15, 'cours', '2026-2027', 3, 3, 3),
(16, 'cours', '2026-2027', 4, 4, 3),
(17, 'cours', '2026-2027', 5, 5, 3),
(18, 'cours', '2026-2027', 6, 6, 3);

-- ---------------------------------------------------------------------
-- Disponibilités des professeurs (à insérer AVANT la planification,
-- sinon le déclencheur refuse les cours)
-- ---------------------------------------------------------------------
INSERT INTO etre_disponible (id_professeur, id_creneau) VALUES
(1, 1), (1, 3), (1, 5), (1, 7), (1, 9), (1, 11), (1, 13), (1, 15),
(2, 2), (2, 4), (2, 6), (2, 8), (2, 10), (2, 12), (2, 14),
(3, 1), (3, 3), (3, 5), (3, 7), (3, 9), (3, 11), (3, 13), (3, 15),
(4, 2), (4, 4), (4, 6), (4, 8), (4, 10), (4, 12), (4, 14),
(5, 1), (5, 3), (5, 5), (5, 7), (5, 9), (5, 11), (5, 13), (5, 15),
(6, 2), (6, 4), (6, 6), (6, 8), (6, 10), (6, 12), (6, 14);

-- ---------------------------------------------------------------------
-- Emploi du temps (PLANIFIER) : 45 séances de 2 h, sans aucun conflit
-- de salle, de professeur ni de classe. Physique-Chimie et SVT ont
-- lieu au Labo Sciences (salle 4).
-- ---------------------------------------------------------------------
INSERT INTO planifier (id_cours, id_creneau, id_salle) VALUES
-- 2nde A
(1, 1, 1), (1, 7, 1), (1, 13, 1),
(2, 2, 1), (2, 8, 1), (2, 14, 1),
(3, 3, 1), (3, 9, 1), (3, 15, 1),
(4, 4, 4), (4, 10, 4),
(5, 5, 4), (5, 11, 4),
(6, 6, 1), (6, 12, 1),
-- 2nde B
(7, 5, 2), (7, 11, 2),
(8, 6, 2), (8, 12, 2),
(9, 1, 2), (9, 7, 2), (9, 13, 2),
(10, 2, 4), (10, 8, 4), (10, 14, 4),
(11, 3, 4), (11, 9, 4), (11, 15, 4),
(12, 4, 2), (12, 10, 2),
-- 1ère A
(13, 3, 3), (13, 9, 3), (13, 15, 3),
(14, 4, 3), (14, 10, 3),
(15, 5, 3), (15, 11, 3),
(16, 6, 4), (16, 12, 4),
(17, 1, 4), (17, 7, 4), (17, 13, 4),
(18, 2, 3), (18, 8, 3), (18, 14, 3);

-- ---------------------------------------------------------------------
-- Notes (ÉVALUER) : 2 devoirs par cours pour chaque élève de la classe
-- = 24 élèves x 6 matières x 2 = 288 notes.
-- Générées par INSERT ... SELECT : la jointure élève-cours sur la classe
-- garantit qu'on ne note un élève que dans les cours de sa classe.
-- Les notes sont calculées par une formule fixe : le résultat est le
-- même à chaque exécution.
-- ---------------------------------------------------------------------
INSERT INTO evaluer (id_eleve, id_cours, date_evaluation, note, appreciation)
SELECT t.id_eleve, t.id_cours, t.d, t.n,
       CASE WHEN t.n >= 16 THEN 'Très bien'
            WHEN t.n >= 14 THEN 'Bien'
            WHEN t.n >= 12 THEN 'Assez bien'
            WHEN t.n >= 10 THEN 'Passable'
            ELSE 'Insuffisant, doit fournir plus d''efforts' END
FROM (
  -- Devoir 1 : semaine du 5 octobre 2026
  SELECT e.id_eleve, c.id_cours,
         DATE(ELT(c.id_matiere, '2026-10-05', '2026-10-06', '2026-10-07',
                                '2026-10-08', '2026-10-09', '2026-10-12')) AS d,
         ROUND(6 + MOD(e.id_eleve * 37 + c.id_cours * 11, 13)
                 + MOD(e.id_eleve + c.id_cours, 4) * 0.5, 2) AS n
  FROM eleve e JOIN cours c ON c.id_classe = e.id_classe
  UNION ALL
  -- Devoir 2 : deux semaines plus tard
  SELECT e.id_eleve, c.id_cours,
         DATE(ELT(c.id_matiere, '2026-10-19', '2026-10-20', '2026-10-21',
                                '2026-10-22', '2026-10-23', '2026-10-26')) AS d,
         ROUND(5 + MOD(e.id_eleve * 29 + c.id_cours * 7, 14)
                 + MOD(e.id_eleve * c.id_cours, 3) * 0.5, 2) AS n
  FROM eleve e JOIN cours c ON c.id_classe = e.id_classe
) AS t;

-- ---------------------------------------------------------------------
-- Absences et retards (S'ABSENTER) : chaque date tombe un jour où le
-- cours a vraiment lieu dans l'emploi du temps.
-- ---------------------------------------------------------------------
INSERT INTO s_absenter (id_eleve, id_cours, date_absence, type_absence, minutes_retard, motif, justifiee) VALUES
(3,  1,  '2026-10-14', 'absence', NULL, 'Maladie',              TRUE),   -- mer., Maths 2nde A
(3,  2,  '2026-10-14', 'absence', NULL, 'Maladie',              TRUE),   -- mer., Français 2nde A
(5,  4,  '2026-10-13', 'retard',  15,   'Transport',            FALSE),  -- mar., PC 2nde A
(10, 7,  '2026-10-15', 'retard',  10,   NULL,                   FALSE),  -- jeu., Maths 2nde B
(10, 9,  '2026-10-16', 'absence', NULL, NULL,                   FALSE),  -- ven., Anglais 2nde B
(12, 11, '2026-10-28', 'absence', NULL, 'Aide aux récoltes',    FALSE),  -- mer., SVT 2nde B
(17, 13, '2026-10-30', 'retard',  20,   'Transport',            TRUE),   -- ven., Maths 1ère A (Momodou)
(17, 15, '2026-10-27', 'absence', NULL, 'Rendez-vous médical',  TRUE),   -- mar., Anglais 1ère A (Momodou)
(18, 17, '2026-10-14', 'retard',  8,    'Transport',            FALSE),  -- mer., SVT 1ère A (Fatou)
(20, 16, '2026-10-29', 'absence', NULL, NULL,                   FALSE),  -- jeu., PC 1ère A
(22, 18, '2026-11-02', 'retard',  5,    NULL,                   FALSE);  -- lun., HG 1ère A

-- ---------------------------------------------------------------------
-- Contrôle rapide : nombre de lignes attendu par table
-- utilisateur 15 | professeur 6 | classe 3 | eleve 24 | matiere 6
-- salle 5 | creneau 15 | cours 18 | etre_disponible 45 | planifier 45
-- evaluer 288 | s_absenter 11
-- ---------------------------------------------------------------------
SELECT 'utilisateur' AS table_nom, COUNT(*) AS nb FROM utilisateur
UNION ALL SELECT 'professeur',      COUNT(*) FROM professeur
UNION ALL SELECT 'classe',          COUNT(*) FROM classe
UNION ALL SELECT 'eleve',           COUNT(*) FROM eleve
UNION ALL SELECT 'matiere',         COUNT(*) FROM matiere
UNION ALL SELECT 'salle',           COUNT(*) FROM salle
UNION ALL SELECT 'creneau',         COUNT(*) FROM creneau
UNION ALL SELECT 'cours',           COUNT(*) FROM cours
UNION ALL SELECT 'etre_disponible', COUNT(*) FROM etre_disponible
UNION ALL SELECT 'planifier',       COUNT(*) FROM planifier
UNION ALL SELECT 'evaluer',         COUNT(*) FROM evaluer
UNION ALL SELECT 's_absenter',      COUNT(*) FROM s_absenter;
