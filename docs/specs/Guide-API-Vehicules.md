
    # Guide d'exécution — API REST Véhicules (PostgreSQL)

    

    Ce guide décrit comment lancer et tester le CRUD Véhicules aligné sur le schéma SQL `service_vehicles.vehicles`.

    

    ## 1) État actuel du service

    

    Le service expose les routes suivantes :

    

    -  `GET /vehicles`

    -  `POST /vehicles`

    -  `GET /vehicles/{id}`

    -  `PUT /vehicles/{id}`

    -  `DELETE /vehicles/{id}`

    

    Validation côté API :

    

    -  `id` path en UUID

    - payload JSON obligatoire pour `POST` et `PUT`

    - champs obligatoires : `immatriculation`, `marque`, `modele`, `statut`

    -  `statut` autorisé : `AVAILABLE`, `IN_USE`, `MAINTENANCE`, `RETIRED`

    - conflit immatriculation unique : HTTP `409`

    

    ## 2) Prérequis

    

    - Docker installé

    - Node.js (version 18+ recommandée)

    - npm

    

    ## 3) Démarrer PostgreSQL local de test

    

    Depuis la racine du projet :

    

    ```bash

    docker  rm  -f  fleet-pg-test >/dev/null 2>&1 || true

    docker  run  -d  \

    --name fleet-pg-test \

    -e  POSTGRES_PASSWORD=postgres  \

    -e POSTGRES_USER=postgres \

    -e  POSTGRES_DB=fleet  \

    -p 55432:5432 \

    postgres:16

    ```

    

    ## 4) Appliquer la migration SQL

    

    ```bash

    docker  exec  -i  fleet-pg-test  psql  -U  postgres  -d  fleet < "docs/bdd/fleet-microservices-sql/V001_initial_setup.sql"

    ```

    

    ## 5) Installer les dépendances du service

    

    ```bash

    cd  services/vehicule-service

    npm  install

    ```

    

    ## 6) Lancer l'API Véhicules

    

    ```bash

    POSTGRES_HOST=127.0.0.1  \

    POSTGRES_PORT=55432  \

    POSTGRES_DB=fleet  \

    POSTGRES_USER=postgres  \

    POSTGRES_PASSWORD=postgres  \

    npm  start

    ```

    

    Le service écoute sur `http://127.0.0.1:3000`.

    

    ## 7) Tester le CRUD rapidement

    

    ### 7.1 Créer un véhicule

    

    ```bash

    curl  -i  -X  POST  http://127.0.0.1:3000/vehicles  \

    -H "Content-Type: application/json" \

    -d  '{

    "id": "11111111-1111-4111-8111-111111111111",

    "immatriculation": "AA-123-BB",

    "marque": "Renault",

    "modele": "Clio",

    "statut": "AVAILABLE"

    }'

    ```

    

    ### 7.2 Lister les véhicules

    

    ```bash

    curl  -i  http://127.0.0.1:3000/vehicles

    ```

    

    ### 7.3 Lire un véhicule par ID

    

    ```bash

    curl  -i  http://127.0.0.1:3000/vehicles/11111111-1111-4111-8111-111111111111

    ```

    

    ### 7.4 Mettre à jour un véhicule

    

    ```bash

    curl  -i  -X  PUT  http://127.0.0.1:3000/vehicles/11111111-1111-4111-8111-111111111111  \

    -H "Content-Type: application/json" \

    -d  '{

    "immatriculation": "AA-123-BB",

    "marque": "Renault",

    "modele": "Clio V",

    "statut": "MAINTENANCE"

    }'

    ```

    

    ### 7.5 Supprimer un véhicule

    

    ```bash

    curl  -i  -X  DELETE  http://127.0.0.1:3000/vehicles/11111111-1111-4111-8111-111111111111

    ```

    

    ### 7.6 Vérifier le 404 après suppression

    

    ```bash

    curl  -i  http://127.0.0.1:3000/vehicles/11111111-1111-4111-8111-111111111111

    ```

    

    ## 8) Cas d'erreur à vérifier

    

    - UUID invalide dans l'URL => `400`

    -  `statut` invalide => `400`

    - champ manquant (`immatriculation`, `marque`, `modele`, `statut`) => `400`

    - immatriculation déjà existante => `409`

    - ID inexistant en GET/PUT/DELETE => `404`

    

    ## 9) Arrêt propre du service

    Si le service Node.js tourne au premier plan (commande `npm start`), arrête-le avec :

    ```bash
    Ctrl+C
    ```

    Si le port `3000` est encore occupé :

    ```bash
    lsof -i :3000
    kill <PID>
    ```

    ## 10) Nettoyage

    Arrêter puis supprimer PostgreSQL de test :

    ```bash
    docker stop fleet-pg-test
    docker rm fleet-pg-test
    ```

    ## 11) Exporter ce guide en PDF (optionnel)

    Option avec Pandoc (si installé) :

    ```bash
    pandoc Guide-API-Vehicules.md -o Guide-API-Vehicules.pdf
    ```

    ---

    ## Références projet

    - Contrat API : `docs/api/véhicules-api.yaml`
    - Schéma SQL principal : `docs/bdd/fleet-microservices-sql/V001_initial_setup.sql`
    - Service Node.js : `services/vehicule-service`
