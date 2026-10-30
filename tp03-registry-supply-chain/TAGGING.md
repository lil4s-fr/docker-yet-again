# Politique de tags Shop SAS

## Conventions

| Tag | Exemple | Usage | Immuable ? |
|---|---|---|---|
| Version SemVer | `1.4.2` | Publication d'une release | Oui, ne jamais republier sous le même tag |
| Commit | `sha-a1b2c3d4` | Traçabilité d'un build CI | Oui |
| Branche | `main` | Tests et intégration continue | Non |
| Environnement | `staging` | Promotion opérationnelle | Non ; ne pas le déployer sans résolution préalable du digest |
| `latest` | `latest` | Développement uniquement | Non, interdit en production |

Le registre `registry:2` ne fournit pas de règle native d'immutabilité des tags. Pour l'imposer plutôt que de compter sur la convention, utiliser un registre d'entreprise avec une politique d'immutabilité (par exemple Harbor) ou un contrôle d'autorisation dédié. Le processus CI doit publier une version une seule fois et échouer si le tag existe déjà.

## Déploiement par digest

Un déploiement de production référence le digest vérifié, et non un tag mutable :

```yaml
services:
  api:
    image: registry.local:5000/shopapi@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

Le digest d'un index multi-architecture identifie l'index ; le runtime sélectionne ensuite le manifeste de plateforme correspondant. Conserver le tag de version dans les métadonnées de release pour la lisibilité, mais utiliser le digest comme référence de déploiement.

## Retag sans `docker pull`

`crane tag` ajoute un tag dans le même dépôt sans charger l'image dans le daemon Docker. Après un `docker login` interactif, les identifiants sont lus dans la configuration Docker :

```bash
crane tag registry.local:5000/shopapi:1.4.2 release-candidate
```

Pour copier entre dépôts ou registres, `skopeo copy` communique directement avec les deux registres et n'utilise pas le daemon Docker. `--all` préserve les images multi-architecture et `--preserve-digests` demande de conserver les digests :

```bash
skopeo copy --all --preserve-digests \
  --authfile "$REGISTRY_AUTH_FILE" \
  docker://registry.local:5000/shopapi:1.4.2 \
  docker://registry.local:5000/release/shopapi:1.4.2
```

Ne passez pas de mots de passe dans les arguments de commande ; utilisez un authfile protégé ou un credential helper.

## Signature

Cosign associe la signature au digest du manifeste, pas au nom du tag. Retagger le même digest conserve la signature. Si un tag est déplacé vers une image différente, l'ancienne signature ne valide pas le nouveau digest ; il faut signer le nouveau contenu. Vérifier la signature à partir du digest résolu avant déploiement.
