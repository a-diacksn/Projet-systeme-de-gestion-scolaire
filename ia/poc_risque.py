"""
Preuve de concept IA — Repérer tôt les élèves en difficulté
=============================================================
Problématique 3 du projet : exploiter les données de la base pour aider
la direction et le professeur principal à décider qui accompagner.

Fonctionnement
  1. La requête SQL indicateurs_requete.sql calcule, pour chaque élève :
     moyenne pondérée, matières sous 10, tendance des notes, absences, retards.
  2. Ce script transforme ces indicateurs en un score de risque sur 100,
     avec des règles pondérées transparentes (pas de « boîte noire »).
  3. Il classe les élèves en trois niveaux et explique chaque alerte.

Pourquoi des règles et pas un modèle entraîné ?
  Avec 24 élèves et un seul trimestre, aucun modèle d'apprentissage ne serait
  fiable. Les règles sont lisibles et vérifiables. Quand l'école aura plusieurs
  années d'historique (notes + qui a réellement décroché), on pourra entraîner
  un modèle (régression logistique, arbre de décision) sur ces mêmes indicateurs.

Utilisation
  python3 poc_risque.py ecole.db            # base SQLite
  python3 poc_risque.py ecole.db --demo     # + scénario de démonstration
  Pour MySQL : remplacer connecter() par mysql.connector.connect(...),
  la requête est identique.
"""

import argparse
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

import pandas as pd

# --------------------------------------------------------------------------
# Règles du score (total sur 100). Chaque poids est un choix explicable.
# --------------------------------------------------------------------------
POIDS = {
    "resultats": 35,   # moyenne générale basse
    "matieres": 15,    # nombre de matières sous 10
    "tendance": 20,    # baisse plus forte que celle de la classe
    "assiduite": 30,   # absences et retards non justifiés
}
SEUIL_ROUGE = 45   # à rencontrer cette semaine
SEUIL_ORANGE = 25  # à surveiller
ABSENCES_ALERTE = 3  # absences non justifiées qui déclenchent une alerte immédiate

NIVEAUX = {
    "rouge": "À rencontrer",
    "orange": "À surveiller",
    "vert": "Pas d'alerte",
}


def borne(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def connecter(chemin):
    con = sqlite3.connect(chemin)
    con.execute("PRAGMA foreign_keys = ON")
    return con


def lire_indicateurs(con, fichier_sql):
    """Exécute la requête d'indicateurs (un seul SELECT, aucune vue à créer)."""
    requete = Path(fichier_sql).read_text(encoding="utf-8")
    return pd.read_sql_query(requete, con)


def scorer(df):
    df = df.copy()
    # La tendance est comparée à celle de la classe : si un devoir était plus
    # difficile pour tout le monde, ce n'est pas un signal individuel.
    df["tendance_classe"] = df.groupby("nom_classe")["tendance"].transform("mean")
    df["tendance_relative"] = (df["tendance"] - df["tendance_classe"]).round(2)

    pts_res, pts_mat, pts_tend, pts_ass, raisons = [], [], [], [], []
    for _, e in df.iterrows():
        r = []
        # Résultats : 0 point à 12 de moyenne ou plus, maximum à 8 ou moins
        p1 = POIDS["resultats"] * borne((12 - e.moyenne) / 4)
        if e.moyenne < 12:
            r.append(f"moyenne {e.moyenne:.2f}")
        # Matières sous 10 : 5 points par matière, plafonné
        p2 = min(POIDS["matieres"], 5 * e.nb_matieres_sous_10)
        if e.nb_matieres_sous_10:
            r.append(f"{int(e.nb_matieres_sous_10)} matière(s) sous 10")
        # Tendance : maximum si la baisse dépasse de 2 points celle de la classe
        p3 = POIDS["tendance"] * borne(-e.tendance_relative / 2)
        if e.tendance_relative <= -0.5:
            r.append(f"baisse de {abs(e.tendance_relative):.1f} pt de plus que la classe")
        # Assiduité : 10 par absence non justifiée, 4 par retard non justifié,
        # 2 par absence justifiée (une absence, même excusée, fait perdre des cours)
        p4 = min(POIDS["assiduite"],
                 10 * e.absences_non_justifiees
                 + 4 * e.retards_non_justifies
                 + 2 * e.absences_justifiees)
        if e.absences_non_justifiees:
            r.append(f"{int(e.absences_non_justifiees)} absence(s) non justifiée(s)")
        if e.retards_non_justifies:
            r.append(f"{int(e.retards_non_justifies)} retard(s) non justifié(s)")
        pts_res.append(p1); pts_mat.append(p2); pts_tend.append(p3); pts_ass.append(p4)
        raisons.append(", ".join(r) if r else "—")

    df["pts_resultats"] = pts_res
    df["pts_matieres"] = pts_mat
    df["pts_tendance"] = pts_tend
    df["pts_assiduite"] = pts_ass
    df["score"] = (df[["pts_resultats", "pts_matieres", "pts_tendance", "pts_assiduite"]]
                   .sum(axis=1).round(0).astype(int))
    df["niveau"] = pd.cut(df["score"], [-1, SEUIL_ORANGE - 1, SEUIL_ROUGE - 1, 100],
                          labels=["vert", "orange", "rouge"]).astype(str)
    # Règle d'alerte immédiate : l'absentéisme répété est le premier signe de
    # décrochage, il déclenche un rendez-vous quel que soit le niveau scolaire.
    absent = df["absences_non_justifiees"] >= ABSENCES_ALERTE
    df.loc[absent, "niveau"] = "rouge"
    raisons = [r + (" (alerte immédiate : absentéisme répété)" if a else "")
               for r, a in zip(raisons, absent)]
    df["raisons"] = raisons
    return df.sort_values("score", ascending=False).reset_index(drop=True)


def afficher(df, titre):
    print(f"\n{titre}")
    print("=" * len(titre))
    for niv in ["rouge", "orange"]:
        sous = df[df.niveau == niv]
        print(f"\n{NIVEAUX[niv]} ({len(sous)})")
        for _, e in sous.iterrows():
            print(f"  {e.score:>3}/100  {e.prenom} {e.nom} ({e.nom_classe}) : {e.raisons}")
    print(f"\n{NIVEAUX['vert']} : {(df.niveau == 'vert').sum()} élève(s)")


def graphique(df, fichier, titre, surligner=None):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Patch

    couleurs = {"rouge": "#d03b3b", "orange": "#fab219", "vert": "#0ca30c"}
    texte, texte2, grille = "#0b0b0b", "#52514e", "#e1e0d9"

    d = df.sort_values("score")
    noms = [f"{p} {n[0]}. ({c})" for p, n, c in zip(d.prenom, d.nom, d.nom_classe)]
    fig, ax = plt.subplots(figsize=(11, 9), dpi=150)
    fig.patch.set_facecolor("#fcfcfb"); ax.set_facecolor("#fcfcfb")
    bars = ax.barh(noms, d.score, color=[couleurs[n] for n in d.niveau],
                   height=0.62, edgecolor="#fcfcfb", linewidth=2)
    for b, s, niv, absn in zip(bars, d.score, d.niveau, d.absences_non_justifiees):
        y = b.get_y() + b.get_height() / 2
        if niv != "vert":
            lab = f"{s}"
            if absn >= ABSENCES_ALERTE:
                lab += f"   alerte immédiate : {int(absn)} absences non justifiées"
            ax.text(b.get_width() + 0.6, y, lab, va="center", fontsize=10,
                    color=texte, fontweight="bold", zorder=5,
                    bbox=dict(facecolor="#fcfcfb", edgecolor="none", pad=1.5))
        elif s == 0:
            ax.text(0.6, y, "0", va="center", fontsize=9, color=texte2)
    for seuil, lab in [(SEUIL_ORANGE, "seuil « à surveiller »"),
                       (SEUIL_ROUGE, "seuil « à rencontrer »")]:
        ax.axvline(seuil, color=texte2, linestyle=(0, (4, 3)), linewidth=1)
        ax.text(seuil + 0.6, len(d) - 0.2, lab, fontsize=9, color=texte2, va="bottom")
    if surligner is not None:
        for lbl, idx in zip(ax.get_yticklabels(), d.id_eleve):
            if idx == surligner:
                lbl.set_fontweight("bold")
    ax.set_xlim(0, min(100, max(70, d.score.max() + 25)))
    ax.set_xlabel("Score de risque (sur 100)", color=texte2)
    ax.tick_params(colors=texte2, labelsize=10)
    for lbl in ax.get_yticklabels():
        lbl.set_color(texte)
    ax.xaxis.grid(True, color=grille, linewidth=0.8); ax.set_axisbelow(True)
    for s in ["top", "right", "left"]:
        ax.spines[s].set_visible(False)
    ax.spines["bottom"].set_color("#c3c2b7")
    ax.set_title(titre, loc="left", fontsize=14, color=texte, fontweight="bold", pad=28)
    ax.legend(handles=[Patch(color=couleurs[k], label=NIVEAUX[k]) for k in ["rouge", "orange", "vert"]],
              loc="lower right", frameon=False, fontsize=10)
    fig.tight_layout()
    fig.savefig(fichier, facecolor=fig.get_facecolor())
    plt.close(fig)


def scenario_demo(chemin_db):
    """Copie la base et simule trois semaines difficiles pour Adama Sall (2nde B) :
    deux absences non justifiées pendant les récoltes et un 6/20 en maths.
    Les insertions passent par les déclencheurs de la vraie base."""
    tmp = Path(tempfile.mkdtemp()) / "demo.db"
    shutil.copy(chemin_db, tmp)
    con = connecter(tmp)
    con.executescript("""
        INSERT INTO s_absenter (id_eleve, id_cours, date_absence, type_absence, minutes_retard, motif, justifiee)
        VALUES (12, 11, '2026-11-04', 'absence', NULL, 'Aide aux récoltes', 0),
               (12, 9,  '2026-11-06', 'absence', NULL, NULL, 0);
        INSERT INTO evaluer (id_eleve, id_cours, date_evaluation, note, appreciation)
        VALUES (12, 7, '2026-11-05', 6, 'Insuffisant');
    """)
    con.commit()
    return con


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("base", help="fichier SQLite de la base école")
    ap.add_argument("--sql", default=str(Path(__file__).with_name("indicateurs_requete.sql")))
    ap.add_argument("--demo", action="store_true", help="ajoute le scénario de démonstration")
    ap.add_argument("--sortie", default=".", help="dossier des fichiers produits")
    a = ap.parse_args()
    out = Path(a.sortie); out.mkdir(parents=True, exist_ok=True)

    con = connecter(a.base)
    res = scorer(lire_indicateurs(con, a.sql))
    afficher(res, "Situation actuelle")
    res.drop(columns=["tendance_classe"]).to_csv(out / "scores_eleves.csv", index=False, encoding="utf-8-sig")
    graphique(res, out / "scores_eleves.png", "Score de risque par élève — situation actuelle")

    if a.demo:
        avant = res.set_index("id_eleve").loc[12]
        con_d = scenario_demo(a.base)
        apres_df = scorer(lire_indicateurs(con_d, a.sql))
        apres = apres_df.set_index("id_eleve").loc[12]
        print("\nScénario de démonstration : Adama Sall, 2nde B")
        print("  + 2 absences non justifiées (récoltes), + un 6/20 en mathématiques")
        print(f"  Avant : {avant.score}/100 ({NIVEAUX[avant.niveau]})")
        print(f"  Après : {apres.score}/100 ({NIVEAUX[apres.niveau]}) — {apres.raisons}")
        graphique(apres_df, out / "scores_eleves_demo.png",
                  "Score de risque — après le scénario Adama Sall", surligner=12)


if __name__ == "__main__":
    sys.exit(main())
