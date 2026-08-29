## 1. Le workflow unique

- [x] 1.1 Créer `.github/workflows/reconcile.yml` : un cron quotidien `41 2 * * *`, un
  `workflow_dispatch` avec les inputs `version` (défaut `""`), `namespace` (défaut `""`) et
  `folders` (défaut : les 7 dossiers). Vérifier avec `actionlint .github/workflows/reconcile.yml`
  (ou `gh workflow view reconcile` après push) que le fichier est accepté.
- [ ] 1.2 Implémenter la branche `version` (design D1) : deux steps `if: inputs.version == ''`
  / `!= ''`, l'un faisant `checkout knock@main` + `docker build knock/`, l'autre
  `checkout knock@v${version}` sans build, tous deux écrivant `KNOCK_IMAGE` dans
  `$GITHUB_ENV`. Vérifier par un dispatch dans chaque sens : le log affiche le bon
  `KNOCK_IMAGE` et un seul des deux steps s'exécute.
- [ ] 1.3 Reporter tels quels les steps partagés des deux anciens workflows : démarrage de
  buildkitd avec sa boucle d'attente, login GHCR, login Docker Hub, push de l'image bypass.
  Vérifier que `docker logs buildkitd` n'apparaît pas (la sonde `/dev/tcp` a réussi) et que
  `ghcr.io/<owner>/bypass/busybox:1.37.0` est poussé.
- [x] 1.4 Écrire la boucle robuste sur `$FOLDERS` (design D3) : `::group::` par dossier,
  accumulation de `fail`, `::error title=<dossier>::` par échec, `exit $fail`. Vérifier en
  dispatchant avec un dossier volontairement invalide dans `folders` : les dossiers suivants
  tournent quand même et le job finit rouge avec une annotation nommant le seul fautif.
- [ ] 1.5 Supprimer `KNOCK_ATTEST_FULCIO_URL` et `KNOCK_ATTEST_REKOR_URL` des variables
  passées à `docker run`. Vérifier qu'un run signe toujours : `cosign verify-attestation`
  passe sur `demo/busybox:latest` (c'est la preuve en conditions réelles que le défaut vide
  résout vers Sigstore public depuis knock 0.9.3).
- [ ] 1.6 Ajouter le re-run de convergence sur `skills` : second `reconcile … --report-json`,
  puis `jq -e '.policies[0].totals | .skipped == 1 and .imported == 0'`. Vérifier qu'un
  second dispatch consécutif sans changement amont passe cette assertion.
- [ ] 1.7 Ne PAS reporter `continue-on-error` (design D2). Vérifier qu'un échec de la boucle
  rend bien le job rouge dans l'onglet Actions.

## 2. `verify.sh` élargi aux 7 dossiers

- [x] 2.1 Remplacer le tableau `IMAGES` par une table d'attentes (design D5) : une entrée par
  référence portant `stamp/sbom/sig` attendus. Vérifier que le script liste bien 8 références
  au démarrage (les 7 dossiers, `debian` en comptant deux variants, `skills` en exception).
- [x] 2.2 Basculer sur les alias stables : `demo/busybox:latest` au lieu de `1.38.0`,
  `demo/redis:latest`, `demo/mongo:8.0`. Vérifier que `regctl manifest get` résout chacun.
- [x] 2.3 Découvrir les tags de `demo/redis-retention` et `demo/redis-delegated` (aucun alias
  déclaré) : `regctl tag ls` filtré sur `^7\.2\.` — jamais un `tail -1` nu, GHCR force des
  tags de repli `sha256-…` dans la liste — puis prendre le plus haut. Vérifier que la
  référence choisie a la forme `7.2.x` et pas `sha256-…`.
- [x] 2.4 Traiter `skills/mcp-builder:sha-3b3fad96af16a10759d930941b4520ba0c40edae` comme
  vérifiant le stamp seul. Le commentaire du script doit citer le constat de code —
  `reconcile_git.py` ne contient aucune occurrence de `sbom` ni `attest` — pour qu'un futur
  lecteur ne « corrige » pas un faux négatif. Vérifier que le script affiche explicitement
  « SBOM/signature non attendus sur le chemin git » et ne compte pas ça comme un échec.
- [ ] 2.5 Vérifier de bout en bout : `./verify.sh <owner> staging` après le dispatch de la
  tâche 4.1 sort `All checks passed.` et code 0.

## 3. Retraits

- [x] 3.1 Supprimer `.github/workflows/showcase.yml` et `.github/workflows/canary.yml`.
  Vérifier que `gh workflow list` ne montre plus que `reconcile`.
- [x] 3.2 Supprimer `knock.env` et toutes ses références (le step « Load the pin », le lien
  du README). Vérifier par `grep -rn "knock.env\|KNOCK_VERSION" .` qui ne doit rien renvoyer.

## 4. Mise en service et documentation

- [ ] 4.1 Dispatcher `reconcile` avec `namespace: staging` et les 7 dossiers par défaut.
  Vérifier que les 7 groupes sont verts et que `./verify.sh <owner> staging` passe — sans
  qu'aucune image de la vitrine publique n'ait bougé.
- [x] 4.2 Réécrire `README.md` autour de « la dernière version du code, tous les jours, et
  elle peut rougir » : retirer la promesse du tag épinglé, retirer la note « The skill row
  runs in the canary, not here », étendre le tableau « What runs here » aux 7 dossiers.
  Conserver **telle quelle** la section « What is not here ». Vérifier qu'aucune phrase du
  README ne décrit un workflow ou un fichier supprimé.
- [ ] 4.3 Dispatcher une fois avec `namespace: ""` pour publier réellement, puis lancer
  `./verify.sh <owner>` depuis un poste sans identifiants. Vérifier que les commandes que le
  README montre au visiteur donnent le résultat que le README annonce.
