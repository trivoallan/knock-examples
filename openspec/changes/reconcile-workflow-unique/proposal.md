## Why

Deux workflows — `showcase.yml` et `canary.yml` — partagent 90 % de leur corps (buildkitd,
logins, l'invocation `docker run … reconcile`, le push bypass) et ne diffèrent que sur
« quel knock, quel ref, quel namespace ». Cette duplication a déjà coûté : quatre des six
derniers commits corrigent un même bug dans un seul des deux fichiers.

Le pin de `knock.env` a par ailleurs un effet que personne n'a choisi : la vitrine publique
ne peut montrer que ce qu'une release porte, donc l'exemple `skills/` — documenté sur la
page — n'y a jamais tourné. Le canary existait pour combler ce trou, et le README doit
expliquer aux visiteurs pourquoi une ligne de son propre tableau ne tourne pas là où il
la montre.

## What Changes

- **Un seul workflow `reconcile.yml`** remplace `showcase.yml` et `canary.yml`. Un cron
  quotidien, un `workflow_dispatch`.
- **`main` par défaut.** L'input `version` est vide au planifié → checkout de knock@main +
  `docker build`. Renseigné (ex. `0.9.3`) → checkout du tag + pull de l'image publiée.
  Comme `on.schedule` ne peut pas passer d'input, le défaut *est* le comportement
  planifié : aucun switch sur la chaîne cron n'est nécessaire.
- **BREAKING — la vitrine publique publie du code non releasé.** Une régression sur knock
  `main` rougit désormais la page. C'était exactement la garantie que le pin préservait ;
  elle est abandonnée sciemment, au profit d'une vitrine qui montre enfin tout ce qu'elle
  documente.
- **`continue-on-error` supprimé.** Non-bloquant, ce run n'alerterait personne.
- **7 dossiers d'exemples par défaut** au lieu de 2–3 :
  `reference/busybox reference/debian-tz skills redis retention pending-deletion brownfield`,
  pilotables par un input `folders`.
- **Input `namespace`** (défaut `""`), pour rejouer une version ancienne hors de la vitrine.
- **`knock.env` supprimé.** Il n'y a plus de pin : la cohérence binaire↔policies tient
  d'elle-même (`main`↔`main`, `tag`↔`tag`).
- **`KNOCK_ATTEST_FULCIO_URL` / `_REKOR_URL` supprimés.** Vides, ils résolvent vers
  Sigstore public depuis knock 0.9.3 ; les nommer était un contournement de knock #252.
- **README réécrit** autour de « la dernière version du code, tous les jours, et elle peut
  rougir ». La note « skill row runs in the canary, not here » disparaît. La section
  « What is not here » est conservée telle quelle (voir Non-goals).

### Ce que la fusion révèle

`knock/use_cases/loader.py:13` utilise `rglob("*")` : `reconcile` **est** récursif. Le
commentaire présent dans les deux workflows (« hence two invocations rather than one
recursive walk ») est faux. Mais une invocation unique sur `docs/examples` échoue quand
même : le loader lève sur le premier YAML qui n'est pas un MirrorPolicy. Vérifié en
exécutant le loader sur chaque dossier :

| Dossier | Parse | Décision |
|---|---|---|
| `reference/busybox`, `reference/debian-tz` | OK | inclus |
| `skills`, `redis`, `retention`, `pending-deletion`, `brownfield` | OK | inclus |
| `admission/` | **FAIL** — Kyverno, 9 erreurs de validation | exclu (empoisonne tout parent) |
| `reference/debian-xz` | OK | exclu — upstream `registry.knock.svc.cluster.local:5000` |
| `hardened/`, `attested/` | OK | exclu — `KNOCK_TRANSFORM_CA_CERTS`/`_MIRRORS` absents |
| `oracles/`, `scan/` | OK, 0 policy | sans objet |

Destinations vérifiées disjointes (`demo/busybox`, `demo/debian`, `demo/redis`,
`demo/redis-retention`, `demo/redis-delegated`, `demo/mongo`) : aucune collision entre les
7 dossiers.

## Non-goals

### Pas de matrice GitHub Actions

Envisagée, puis retirée. Elle était justifiée par : « la page Actions devient le tableau de
couverture que le README dit ne pas pouvoir produire ». Cette phrase ne tient pas.

| Ce qui était dit | Ce que ça nomme |
|---|---|
| « la page Actions **est** le rapport de couverture » | 7 cases écrites par celui qui les compte, dans `examples.json` |
| « ✓ 7/7 » | un taux fixé par le dessinateur du tableau, jamais par le registre |
| ce que mesurerait `knock audit` | le **dénominateur** — ce qui est dans le registre et n'est pas estampillé |
| ce que mesure la matrice | le **numérateur**, et seulement celui qu'on a déclaré |

Décompte : 7 sur 7, toujours, par construction. Un tableau qui ne peut pas descendre sous
100 % ne mesure rien. Et `bypass/busybox` — le seul objet de ce repo qui **démontre** un
angle mort — n'a de ligne dans aucune case : le tableau censé mesurer la couverture est
précisément celui d'où l'unique preuve de non-couverture est absente. Le coût est porté par
le visiteur, qui lit sept verts comme une absence d'angle mort deux sections après avoir lu
que ce compte est impossible sur GHCR.

<!-- incongru-voix: debord — "le rapport de couverture" nomme 7 cases écrites par celui qui
     les compte, jamais le dénominateur — coût: le visiteur lit 7/7 comme une absence
     d'angle mort, et bypass/busybox, le seul angle mort démontré, n'a pas de ligne -->

Restaient les mérites secs de la matrice : isolation des échecs, parallélisme, retry par
dossier. Ce sont des raisons de CI, et pour des raisons de CI elles ne valent pas un job de
build amont, un transport d'image de ~300 Mo entre étages et un DAG à trois niveaux. Le bug
réel qu'elles visaient — `set -euo pipefail` coupe la boucle au premier dossier rouge, donc
un échec masque tous les suivants — se corrige en trois lignes : `::group::` par dossier,
accumulation de `fail`, `exit $fail`.

### La section « What is not here » du README reste

C'est la phrase la plus intègre de la page. Elle ne doit pas être remplacée par un tableau
qui prétend répondre à ce qu'elle déclare hors de portée.

## Capabilities

### New Capabilities
Aucune. Ce changement porte sur la configuration CI et la documentation ; aucun
comportement produit n'est spécifié dans ce dépôt (`openspec/specs/` est vide et le dépôt
n'expose que des workflows, `verify.sh` et le README). `.openspec.yaml` porte
`skip_specs: true`.

### Modified Capabilities
Aucune.

## Impact

- `.github/workflows/showcase.yml`, `.github/workflows/canary.yml` → supprimés
- `.github/workflows/reconcile.yml` → créé
- `knock.env` → supprimé. **Renovate perd son ancrage** `datasource=docker
  depName=ghcr.io/trivoallan/knock` ; rien ne le remplace, `main` n'ayant pas de version à
  suivre.
- `README.md` → thèse réécrite (pin → `main` quotidien), tableau « What runs here » étendu
  aux 7 dossiers, note « canary only » supprimée
- `verify.sh` → sa liste `IMAGES` est en dur sur 2 références et ne couvrira plus qu'un
  tiers de ce qui est publié. **À trancher** : l'élargir aux 7, ou assumer qu'il
  échantillonne un chemin de copie et un chemin de rebuild, et l'écrire dans le script.
- Secrets inchangés : `DOCKERHUB_USER`, `DOCKERHUB_TOKEN`, `GITHUB_TOKEN`, OIDC.
