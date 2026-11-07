# Fabrique les paquets d'une version, lus par WowUp (« Installer depuis une URL »).
# Lancé par .github/workflows/publier.yml à chaque push sur main ; marche aussi en local :
#   python outils/publier.py 2026.11.08.1 dist
# Sortie dans <dossier> :
#   addons-wow-<version>.zip          les addons pour Retail (Interface >= 100000)
#   addons-wow-<version>-forever.zip  les addons pour WoW Forever (Interface 1xxxx)
#   release.json                      la fiche que WowUp lit pour choisir le bon zip
#   notes.md                          la liste des addons et de leurs versions
import json
import os
import re
import sys
import zipfile

version, sortie = sys.argv[1], sys.argv[2]
racine = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.makedirs(sortie, exist_ok=True)

# Un addon = un dossier qui contient <dossier>.toc.
addons = []
for nom in sorted(os.listdir(racine)):
    toc = os.path.join(racine, nom, nom + ".toc")
    if not os.path.isfile(toc):
        continue
    texte = open(toc, encoding="utf-8-sig").read()
    interfaces = [int(n) for n in re.findall(r"\d+", re.search(r"^## Interface:(.*)$", texte, re.M).group(1))]
    v = re.search(r"^## Version:\s*(.+)$", texte, re.M)
    addons.append({"nom": nom, "interfaces": interfaces, "version": v.group(1).strip() if v else "?"})

saveurs = {
    # saveur WowUp : (suffixe du zip, test sur le numéro d'Interface)
    "mainline": ("", lambda i: i >= 100000),
    "forever": ("-forever", lambda i: 10000 <= i < 20000),
}

releases = []
for saveur, (suffixe, garde) in saveurs.items():
    choisis = [a for a in addons if any(garde(i) for i in a["interfaces"])]
    if not choisis:
        continue
    nomZip = "addons-wow-%s%s.zip" % (version, suffixe)
    with zipfile.ZipFile(os.path.join(sortie, nomZip), "w", zipfile.ZIP_DEFLATED) as z:
        for a in choisis:
            dossier = os.path.join(racine, a["nom"])
            for base, _, fichiers in os.walk(dossier):
                for f in sorted(fichiers):
                    chemin = os.path.join(base, f)
                    z.write(chemin, os.path.relpath(chemin, racine).replace(os.sep, "/"))
    interface = max(i for a in choisis for i in a["interfaces"] if garde(i))
    releases.append({"filename": nomZip, "nolib": False,
                     "metadata": [{"flavor": saveur, "interface": interface}]})
    print("%s : %s" % (nomZip, ", ".join(a["nom"] for a in choisis)))

with open(os.path.join(sortie, "release.json"), "w", encoding="utf-8") as f:
    json.dump({"releases": releases}, f, indent=2)

with open(os.path.join(sortie, "notes.md"), "w", encoding="utf-8") as f:
    f.write("| Addon | Version | Retail | Forever |\n|---|---|---|---|\n")
    for a in addons:
        r = "oui" if any(i >= 100000 for i in a["interfaces"]) else "non"
        fo = "oui" if any(10000 <= i < 20000 for i in a["interfaces"]) else "non"
        f.write("| %s | %s | %s | %s |\n" % (a["nom"], a["version"], r, fo))
