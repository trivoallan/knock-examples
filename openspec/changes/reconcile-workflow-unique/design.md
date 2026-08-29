## Context

Voir [proposal.md](proposal.md) — *Why*. Ce document fixe le *comment* : la forme du
workflow unique, la branche `version`, et l'élargissement de `verify.sh` aux 7 dossiers.

Contraintes relevées en explorant le code de knock, toutes vérifiées :

- `knock/use_cases/loader.py:13` fait `rglob("*")` et **lève** sur le premier YAML qui
  n'est pas un MirrorPolicy. `reconcile docs/examples` est donc impossible tant que
  `admission/` est là ; la sélection reste une liste de dossiers.
- `knock/use_cases/reconcile_git.py` ne contient **aucune** occurrence de `sbom` ni
  `attest`. Le chemin git (`artifactType: skill`) pose un stamp, et **ni SBOM ni
  signature**. Toute vérification uniforme sur les 7 dossiers échouerait à tort sur
  `skills/mcp-builder`.
- `on.schedule` ne peut pas passer d'`inputs`.

## Goals / Non-Goals

**Goals** — une seule copie de la logique ; le comportement planifié est le défaut, sans
détour par la chaîne cron ; `verify.sh` couvre ce que le workflow place.

**Non-Goals** — la matrice GitHub Actions (voir proposal.md — *Non-goals*, avec le
décompte). Le chemin transform (`hardened/`, `attested/`) : il entre le jour où un CA de
démo vit dans ce dépôt.

## Decisions

### D1 — `version` est le seul axe, et son défaut fait le travail

```
version == ""  (planifié)          version == "0.9.3"  (dispatch)
──────────────────────             ────────────────────────────
checkout knock@main                checkout knock@v0.9.3
docker build knock/  →  knock:ci   KNOCK_IMAGE=ghcr.io/<owner>/knock:0.9.3
```

Deux steps opposés sur `if: inputs.version == ''` / `!= ''`, une variable `KNOCK_IMAGE`
posée dans `$GITHUB_ENV`, et le reste du job inconditionnel.

*Alternative écartée* : garder deux modes et brancher sur `github.event.schedule ==
'41 2 * * *'`. Ça transforme une chaîne cron en clé sémantique — modifier l'heure du cron
changerait silencieusement le mode.

### D2 — `main` par défaut, donc échec bloquant

`continue-on-error: true` disparaît. Un job vert-avec-erreurs n'envoie aucune notification
GitHub ; sur le seul run qui existe désormais, ce serait un workflow qui n'informe personne.

### D3 — Boucle robuste, pas de matrice

Le bug réel est que `set -euo pipefail` coupe la boucle au premier dossier rouge :

```bash
fail=0
for folder in $FOLDERS; do
  echo "::group::$folder"
  docker run --rm ... "$KNOCK_IMAGE" reconcile "/knock/docs/examples/$folder" \
    || { echo "::error title=$folder::reconcile a échoué"; fail=1; }
  echo "::endgroup::"
done
exit $fail
```

Tous les dossiers sont tentés, chacun replié dans son groupe, une annotation par échec.
La justification qui portait la matrice est retirée dans le proposal.

### D4 — Le piège du dispatch en version ancienne, réglé par convention

`reconcile` converge sur le **contenu**, pas sur le stamp. Un dispatch `version=0.9.3`
republie sur les mêmes destinations avec le stamp de 0.9.3 ; le run quotidien suivant voit
un contenu identique, `skipped`, et **ne répare pas** le stamp périmé.

Sortie retenue : un input `namespace` (défaut `""`), documenté « rejouer une version
ancienne ? mets un namespace ». Zéro logique conditionnelle, le piège devient une
convention. *Alternative écartée* : dériver le namespace de `version` — ça ressuscite la
notion de mode qu'on vient de supprimer.

### D5 — `verify.sh` : une table d'attentes par référence

Le script cesse de porter une liste plate. Chaque entrée déclare ce qui *doit* être là,
parce que les 7 dossiers n'ont pas tous les mêmes garanties :

| Référence | stamp | SBOM | signature | note |
|---|---|---|---|---|
| `demo/busybox:latest` | ✓ | ✓ | ✓ | copie |
| `demo/debian:bookworm-slim-eu` | ✓ | ✓ | ✓ | rebuild, `io.knock.transform.*` |
| `demo/debian:bookworm-slim-us` | ✓ | ✓ | ✓ | second variant |
| `demo/redis:latest` | ✓ | ✓ | ✓ | copie |
| `demo/mongo:8.0` | ✓ | ✓ | ✓ | copie |
| `demo/redis-retention:<découvert>` | ✓ | ✓ | ✓ | pas d'alias — voir plus bas |
| `demo/redis-delegated:<découvert>` | ✓ | ✓ | ✓ | pas d'alias |
| `skills/mcp-builder:sha-3b3fad96…` | ✓ | — | — | chemin git : ni SBOM ni signature |

Trois conséquences de forme :

1. **Les alias plutôt que les tags concrets.** `demo/busybox:1.38.0` est en dur aujourd'hui
   alors que la policy sélectionne `^1\.3[78]\.\d+$` : le jour où busybox publie 1.38.1, la
   référence vérifiée n'est plus la plus récente. Les alias `latest` / `8.0` sont stables
   par construction.
2. **Deux repos sans alias.** `retention` et `pending-deletion` ne déclarent aucun alias :
   leurs tags sont les versions concrètes `7.2.x` et dérivent. Il faut les découvrir —
   `regctl tag ls`, filtré sur `^7\.2\.` (GHCR force des tags de repli `sha256-…` dans la
   liste, ils ne sont pas des dommages mais du bruit), puis prendre le plus haut.
3. **Le skill est une exception, pas un échec.** Vérifié dans le code, pas supposé.
   L'entrée porte `sbom=no sig=no` et le script le dit à l'écran, sinon la prochaine
   personne « corrigera » un faux négatif.

`--certificate-identity-regexp '^https://github.com/<owner>/knock-examples/\.github/workflows/'`
reste valable tel quel : il matche `reconcile.yml` comme il matchait les deux précédents.

*Option non retenue pour l'instant* : `retention` et `pending-deletion` sont les deux seuls
exemples qui produisent un referrer `pending-deletion`. Sans l'asserter, ce sont deux copies
de redis de plus. Une quatrième colonne les distinguerait — à faire quand quelqu'un se
plaindra qu'ils ne prouvent rien.

### D6 — `knock.env` supprimé, sans remplaçant

La cohérence binaire↔policies tenait du fichier ; elle tient maintenant de la branche D1
(`main`↔`main`, `tag`↔`tag`). Renovate perd son ancrage et rien ne le remplace : `main`
n'a pas de version à suivre. C'est une perte assumée, pas un oubli.

## Risks / Trade-offs

- **Une régression sur knock `main` rougit la vitrine publique.** → Accepté explicitement
  (proposal — *BREAKING*). Le README doit le dire, pas le taire.
- **Un dispatch en version ancienne laisse un stamp périmé que rien ne répare.** → D4, par
  convention plutôt que par mécanisme. Si ça mord, dériver le namespace.
- **7 dossiers = beaucoup plus de pull depuis Docker Hub** (`mongo` et `redis` sont d'un
  autre ordre de grandeur que `busybox`). Le login Docker Hub existe déjà et lève le
  throttling anonyme ; le run s'allonge, il ne casse pas.
- **`retention` marque des tags `pending-deletion` sur ses propres copies.** → `verify.sh`
  vérifie un tag présent et récent, pas l'absence de marque.
- **`regctl tag ls` renvoie les tags de repli `sha256-…` de GHCR.** → filtre `^7\.2\.` à la
  découverte, jamais un `tail -1` nu.

## Migration Plan

1. `reconcile.yml` créé et exercé en `workflow_dispatch` avec `namespace: staging` — les 7
   dossiers, `verify.sh` élargi, sans toucher la vitrine publique.
2. Un dispatch `namespace: ""` pour publier réellement.
3. `showcase.yml`, `canary.yml`, `knock.env` supprimés dans le même commit que la
   réécriture du README — la page ne doit jamais décrire un workflow qui n'existe plus.
4. **Rollback** : `git revert`. Les images déjà publiées restent valides ; un `reconcile`
   depuis un tag les réécrit avec le stamp de ce tag (voir D4).

## Open Questions

- La suppression du namespace `canary` laisse `ghcr.io/<owner>/canary/**` derrière elle.
  Purge manuelle ou abandon ? Sans effet sur la vitrine ni sur les tâches.
