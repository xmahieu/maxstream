# Serveur de licences MaxStream

Petit serveur (Cloudflare Worker) qui gère l'essai gratuit de 7 jours par appareil et la licence à vie à 15 € payée avec PayPal.

## Fonctionnement

- Au lancement, l'application envoie le **code de l'appareil**. Ce code ressemble à une adresse MAC, par exemple `0A:3F:91:C2:7E:15`. Il est calculé à partir de l'identifiant de l'appareil (ANDROID_ID ou MachineGuid sous Windows) puis haché. Aucun identifiant matériel ne quitte l'appareil.
- Le serveur retient la date du premier lancement. Pendant 7 jours, l'application est complète. Ensuite, l'écran de licence s'affiche.
- Le bouton PayPal (ou le QR code sur une TV) ouvre `/pay?d=CODE`. Le serveur crée une commande PayPal de 15 € dont le champ `custom_id` contient le code de l'appareil, puis redirige vers PayPal.
- Après le paiement, PayPal renvoie le client vers `/paypal/return`. Le serveur encaisse la commande et vérifie le montant et le statut. L'appareil passe alors en licence à vie et se débloque tout seul en quelques secondes.
- Le webhook `/paypal/webhook` sert de secours : si le client ferme la page avant le retour, la commande est quand même encaissée et l'appareil activé. Le serveur relit toujours la commande auprès de PayPal au lieu de croire le message reçu.
- Seuls sont enregistrés : le code de l'appareil, la plateforme (android ou windows), la date du premier lancement et les références du paiement.

## Installation (une fois)

1. **Cloudflare**, dans Workers & Pages :
   - Créer un Worker nommé `maxstream-licence` et y coller `worker.js`.
   - Dans Storage › KV, créer un espace de noms `LICENCES`, puis le lier au Worker sous le nom `LICENCES` (Settings › Bindings).
   - Ajouter les variables `PAYPAL_ENV` = `live`, `PRICE` = `15.00` et `TRIAL_DAYS` = `7`.
   - Ajouter les secrets `PAYPAL_CLIENT_ID`, `PAYPAL_SECRET` et `ADMIN_KEY` (un mot de passe long que vous choisissez).
2. **PayPal**, sur developer.paypal.com › Apps & Credentials › Live › votre app :
   - Copier le Client ID et le Secret dans les secrets Cloudflare ci-dessus.
   - Ajouter un webhook vers `https://maxstream-licence.<vous>.workers.dev/paypal/webhook`, avec les événements *Checkout order approved* et *Payment capture completed*.
3. **GitHub**, dans maxstreamkodi-cyber/maxstream › Settings › Secrets and variables › Actions :
   - Variable `LICENCE_URL` = l'adresse du Worker, sans `/` final.
   - Secrets `ANDROID_KEYSTORE_B64` et `ANDROID_KEYSTORE_PASSWORD`, qui se trouvent dans `_prive/SECRETS-GITHUB.txt` sur le PC et ne doivent jamais être publiés.
4. Lancer **Actions › MaxStream apps (release) › Run workflow**. L'APK et l'installateur Windows sont publiés dans les Releases.

## Administration

Remplacer `CLE` par la valeur du secret `ADMIN_KEY` :

- Voir un appareil : `https://…workers.dev/admin?key=CLE&d=0A:3F:91:C2:7E:15`
- L'activer à la main (geste commercial, paiement hors PayPal) : ajouter `&action=activate`
- Retirer une licence (remboursement) : `&action=revoke`
- Offrir une nouvelle semaine d'essai : `&action=reset`
- Lister les appareils : `?key=CLE&action=list`

## Tests

`node test/test.mjs` simule PayPal et KV, puis vérifie les étapes suivantes : essai, expiration, paiement, retour, webhook, administration et refus des codes invalides.
