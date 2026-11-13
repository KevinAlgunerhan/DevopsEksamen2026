# PGR301 – Eksamen 2026
## Wishif.ai – Eksamenbesvarelse

# Task 1 – Container og CI

## 1.1 Containerisering med Docker

Wishif.ai er en Spring Boot-applikasjon utviklet med Java 21 og Spring Boot 3.3.4. For å gjøre applikasjonen enklere å distribuere og kjøre i ulike miljøer har jeg valgt å containerisere den med Docker.

Jeg har implementert en multi-stage Dockerfile med to separate steg:

**Build stage:**
- Bruker `maven:3.9.9-eclipse-temurin-21`.
- Kopierer inn prosjektets `pom.xml` og kildekode.
- Bygger applikasjonen med Maven.
- Produserer en kjørbar JAR-fil.

**Runtime stage:**
- Bruker `eclipse-temurin:21-jre`.
- Kopierer kun den ferdigbygde JAR-filen fra build-steget.
- Eksponerer port 8080.
- Starter applikasjonen med `java -jar app.jar`.

Jeg valgte multi-stage build fordi byggeprosessen og produksjonsmiljøet har forskjellige behov. Maven og byggeavhengighetene er nødvendige under kompilering, men ikke når applikasjonen kjører. Ved å bruke et separat runtime-image unngår jeg å inkludere unødvendige byggeverktøy i den ferdige containeren.

Dette gir et mer kompakt runtime-image, færre unødvendige komponenter og et tydeligere skille mellom bygging og kjøring.

## 1.2 Testing av Docker-containeren

Etter implementasjonen bygget jeg Docker-imaget lokalt og startet applikasjonen i en container.

Jeg testet at Spring Boot startet korrekt, og at containeren kunne kommunisere med AWS-tjenestene som applikasjonen er avhengig av.

Applikasjonen bruker AWS SDK sin default credential provider chain for autentisering. Under lokal testing ble AWS-legitimasjonen gjort tilgjengelig for containeren gjennom en read-only mount av AWS-konfigurasjonen.

Jeg verifiserte at følgende funksjonalitet fungerte fra Docker-containeren:

- Opplasting av bilder til Amazon S3.
- Bildeanalyse med Amazon Rekognition.
- Generering av gaveforslag med Amazon Bedrock.

Dette var viktig fordi det ikke er tilstrekkelig å bare bekrefte at containeren starter. Den må også kunne utføre de faktiske oppgavene applikasjonen er utviklet for.

## 1.3 GitHub Actions – Continuous Integration

Jeg har implementert en GitHub Actions-workflow i:

`.github/workflows/docker-build.yml`

Workflowen trigges automatisk ved push til `main` og ved pull requests mot `main`.

Pipeline består av følgende steg:

1. Checkout av GitHub-repositoriet.
2. Oppsett av Java 21 med Eclipse Temurin.
3. Kjøring av automatiserte tester med `mvn clean test`.
4. Bygging av applikasjonen med Maven.
5. Verifisering av at forventet JAR-artifakt eksisterer.
6. Bygging av Docker-imaget.

Jeg har valgt å kjøre testene før Docker-imaget bygges. Dette gjør at feil i applikasjonen oppdages tidlig i CI-prosessen, og hindrer at et image bygges dersom testene feiler.

Workflowen bruker også Maven caching gjennom `setup-java` for å redusere unødvendig nedlasting av avhengigheter ved senere kjøringer.

GitHub Actions-workflowen ble kjørt med grønt resultat, og alle stegene fullførte.

**Avgrensning:** Den implementerte workflowen tester og bygger Docker-imaget, men publiserer ikke automatisk imaget til ECR. Publiseringen til ECR ble utført separat.

## 1.4 Automatiserte tester

Jeg har implementert totalt 11 automatiserte tester ved hjelp av JUnit og Spring Boot Test.

Testene er fordelt mellom `WishlistServiceTest` og `AppControllerTest`.

### WishlistServiceTest – 4 tester

Disse testene verifiserer behandlingsflyten i applikasjonens servicelag.

| Test | Hva som verifiseres |
|---|---|
| Normal behandlingsflyt | At S3, Rekognition og Bedrock kalles i riktig rekkefølge og gir forventet resultat. |
| S3-feil | At videre behandling stoppes dersom opplasting til S3 feiler. |
| Rekognition-feil | At Bedrock ikke kalles dersom Rekognition feiler. |
| Bedrock-feil | At feil fra Bedrock håndteres og videresendes korrekt. |

Disse testene er viktige fordi applikasjonen er avhengig av flere eksterne AWS-tjenester. Ved å teste feilscenarioene verifiserer jeg også at applikasjonen ikke fortsetter behandlingen når et nødvendig steg har feilet.

### AppControllerTest – 7 tester

Disse testene verifiserer REST API-et og valideringen av opplastede bilder.

| Test | Hva som verifiseres |
|---|---|
| Health endpoint | At health-endpointet fungerer. |
| Gyldig JPEG | At gyldige JPEG-bilder aksepteres. |
| Gyldig PNG | At gyldige PNG-bilder aksepteres. |
| Tom fil | At tomme bildefiler avvises. |
| GIF | At filformatet GIF avvises. |
| Ugyldig JPEG-signatur | At filer med feil filsignatur avvises. |
| Ugyldig bildeinnhold | At filer med gyldig signatur, men ugyldig bildeinnhold, avvises. |

Samtlige 11 tester bestod.

## 1.5 Input-validering og feilhåndtering

Jeg har implementert en egen `ImageValidator` for å kontrollere bilder før de sendes videre til AWS-tjenestene.

Valideringen kontrollerer:

- At filen ikke er tom.
- At filtypen er JPEG eller PNG.
- At filens faktiske signatur samsvarer med forventet format.
- At bildet kan dekodes som et gyldig bilde.

Jeg har valgt å kontrollere både MIME-type, filsignatur og faktisk bildeinnhold. Dette er fordi filendelser og MIME-type alene ikke er tilstrekkelig for å bekrefte at en opplastet fil faktisk er et gyldig bilde.

Applikasjonen har også en `ApiExceptionHandler` som håndterer `IllegalArgumentException` og returnerer HTTP 400 med en JSON-feilmelding.

I tillegg er maksimal filstørrelse konfigurert til 10 MB gjennom Spring Boot sine multipart-innstillinger.

Dette reduserer risikoen for at ugyldige eller uønskede filer behandles av applikasjonen og sendes videre til eksterne tjenester.

---

# Task 2 – ECS Express og Infrastructure as Code

## 2.1 Valg av AWS ECS Express Gateway

Jeg har valgt Amazon ECS Express Gateway for å distribuere Wishif.ai som en containerbasert applikasjon.

ECS Express Gateway gjør det mulig å eksponere en containerbasert tjeneste gjennom en offentlig HTTPS-endpoint uten at jeg trenger å konfigurere alle komponentene rundt ECS-tjenesten manuelt.

Dette passer godt til applikasjonen fordi den allerede er containerisert og lytter på port 8080.

Jeg har konfigurert følgende ressurser for tjenesten:

- CPU: 1024.
- Memory: 2048 MiB.
- Container port: 8080.
- AWS-region: eu-west-1.
- Health check path: `/api/health`.

Jeg valgte disse ressursverdiene som et utgangspunkt for en relativt liten Spring Boot-applikasjon. De gir applikasjonen tilgjengelige CPU- og minneressurser samtidig som ressursbruken holdes moderat.

## 2.2 Infrastructure as Code med Terraform

Jeg har valgt Terraform for å definere og administrere AWS-infrastrukturen.

Terraform-konfigurasjonen er organisert i en egen `terraform/`-mappe:

- `main.tf` – definisjon av AWS-ressurser.
- `variables.tf` – variabler for konfigurasjon.
- `outputs.tf` – utdata fra infrastrukturen.
- `providers.tf` – Terraform- og AWS-provider-konfigurasjon.

AWS Provider er konfigurert med versjon 6.x.

Jeg valgte Infrastructure as Code fremfor manuell opprettelse av ressursene i AWS Console fordi infrastrukturen da blir dokumentert som kode og kan gjenskapes og vedlikeholdes på en mer konsistent måte.

Terraform gir også mulighet til å kontrollere planlagte endringer før de utføres gjennom `terraform plan`.

Eksisterende ressurser ble importert til Terraform state der det var nødvendig. Dette gjaldt blant annet ECR-repositoriet og den eksisterende S3-bucketen. På denne måten kunne jeg administrere eksisterende infrastruktur uten å opprette duplikater eller risikere å overskrive eksisterende data.

Jeg brukte `terraform validate` og `terraform plan` før endringene ble utført med `terraform apply`.

## 2.3 Amazon ECR – Container Registry

Jeg bruker Amazon Elastic Container Registry (ECR) for lagring av Docker-imaget.

ECR-repositoriet er konfigurert med:

- Immutable image tags.
- AES256-kryptering.
- Image scanning ved push.

Jeg valgte immutable image tags fordi et publisert image ikke skal kunne overskrives med et annet image under samme tag. Dette gjør det enklere å identifisere og kontrollere hvilken versjon som faktisk er distribuert.

Image scanning er aktivert for å kunne identifisere potensielle sårbarheter i container-imaget.

Docker-imaget ble publisert med Git commit-basert tag `54d3fee`.

Dette gir en kobling mellom en bestemt kodeversjon og container-imaget som ble distribuert til AWS.

## 2.4 Amazon S3 – Lagring og sikkerhet

Wishif.ai bruker Amazon S3 til lagring av opplastede bilder.

Den eksisterende bucket-en `wishifai-uploads` ble importert til Terraform og konfigurert videre.

Jeg har implementert følgende sikkerhetsinnstillinger:

- Public access block aktivert.
- Blokkering av offentlige ACL-er og bucket policies.
- Server-side encryption med AES256.
- S3 Versioning aktivert.
- Terraform `prevent_destroy = true`.

Jeg valgte å blokkere offentlig tilgang fordi bildene ikke trenger å være tilgjengelige direkte fra internett. Applikasjonen kommuniserer med S3 gjennom AWS SDK og IAM-rettigheter.

AES256-kryptering beskytter objektene ved lagring.

S3 Versioning gjør det mulig å bevare tidligere objektversjoner dersom et objekt overskrives. Dette gir bedre beskyttelse mot utilsiktede endringer.

Jeg har også konfigurert `prevent_destroy = true` i Terraform for å redusere risikoen for at den eksisterende bucket-en slettes gjennom en utilsiktet Terraform-endring.

## 2.5 IAM – Tilgangskontroll

Jeg har opprettet separate IAM-roller for ECS Express Gateway.

Dette skiller mellom tillatelsene som trengs for å starte infrastrukturen og tillatelsene som trengs av selve applikasjonen.

### ECS Execution Role

Execution role brukes av ECS til å:

- Hente container-imaget fra ECR.
- Sende containerlogger til CloudWatch.

Rollen bruker AWS sin administrerte `AmazonECSTaskExecutionRolePolicy`.

### ECS Infrastructure Role

Infrastructure role brukes av ECS Express Gateway til å administrere den nødvendige infrastrukturen.

Rollen er konfigurert med AWS sin administrerte policy:

`AmazonECSInfrastructureRoleforExpressGatewayServices`

### ECS Task Role

Task role brukes av Spring Boot-applikasjonen når den kommuniserer med AWS-tjenestene.

Jeg har gitt rollen følgende tillatelser:

| AWS-tjeneste | IAM-action | Formål |
|---|---|---|
| S3 | `s3:PutObject` | Laste opp bilder. |
| Rekognition | `rekognition:DetectLabels` | Analysere bilder. |
| Bedrock | `bedrock:InvokeModel` | Generere gaveforslag. |

Jeg har valgt separate roller fordi applikasjonen ikke skal ha de samme tillatelsene som ECS trenger for å administrere infrastrukturen.

Dette følger prinsippet om minste privilegium ved at applikasjonen får egne tillatelser for AWS-operasjonene den faktisk utfører.

## 2.6 CloudWatch Logging

Jeg har opprettet en CloudWatch Log Group:

`/ecs/wishifai`

Log retention er satt til 30 dager.

ECS Express Gateway er konfigurert til å sende containerlogger til denne loggruppen med log stream prefix `wishifai`.

Dette gjør det mulig å undersøke oppstartsproblemer, runtime-feil og hendelser i applikasjonen uten å måtte koble seg direkte til containeren.

## 2.7 Health checks og deployment

Applikasjonen har et health endpoint implementert i `AppController`:

`GET /api/health`

Endpointet returnerer HTTP 200 og JSON med status `UP` når applikasjonen kjører.

Under første deployment oppdaget jeg at health check var konfigurert med `/health`, mens controlleren har en felles mapping på `/api`.

Dette førte til HTTP 404 fra health check.

Jeg undersøkte ECS-status, target group health og CloudWatch-logger for å identifisere årsaken. Deretter korrigerte jeg Terraform-konfigurasjonen til `/api/health`.

Jeg valgte å oppdatere ECS Express Gateway gjennom Terraform i stedet for å endre ressursene manuelt i AWS. Terraform-planen viste at endringen kunne utføres in-place uten å slette den eksisterende tjenesten.

Etter oppdateringen returnerte health endpoint HTTP 200.

ECS-tjenesten ble også verifisert med følgende status:

- Service status: `ACTIVE`.
- Desired tasks: 1.
- Running tasks: 1.
- Pending tasks: 0.
- Deployment rollout state: `COMPLETED`.

Dette bekreftet at tjenesten var stabil etter deployment.

## 2.8 Ende-til-ende-testing i AWS

Etter deployment testet jeg hele applikasjonen gjennom den offentlige HTTPS-endpointen som ECS Express Gateway opprettet.

Jeg sendte et PNG-bilde til:

`POST /api/analyze`

Forespørselen ble sendt med `multipart/form-data` og parameteren `image`.

Testen returnerte HTTP 200 og bekreftet at alle integrasjonene fungerte i det deployede miljøet.

Behandlingsflyten var:

1. Spring Boot mottok og validerte bildet.
2. Bildet ble lastet opp til Amazon S3.
3. Amazon Rekognition identifiserte objekter og labels i bildet.
4. Amazon Bedrock genererte romanalyse, mottakerprofil og fem gaveforslag.
5. Applikasjonen returnerte resultatet som JSON.

Jeg verifiserte også S3-opplastingen separat med `aws s3api head-object`.

Resultatet bekreftet at objektet eksisterte i bucket-en, hadde forventet filstørrelse og MIME-type, var kryptert med AES256 og hadde en VersionId.

Dette var en viktig verifikasjon fordi det bekrefter at løsningen fungerer ende-til-ende i AWS, og ikke bare lokalt.

---

## Task 3 – Observability 

### 3.1 Mål og tilnærming

Målet med observability-implementasjonen er å gjøre Wishifai-applikasjonen målbar og enklere å feilsøke i produksjon. Løsningen skal gi innsikt i applikasjonens tilgjengelighet, ytelse, ressursbruk og feil i integrasjonene mot AWS-tjenestene.

Jeg har implementert observability ved hjelp av **Spring Boot Actuator, Micrometer og Amazon CloudWatch**. Dette gir både applikasjonsspesifikke målinger og tekniske driftsmålinger fra Spring Boot og JVM.

### 3.2 Spring Boot Actuator og Micrometer

Spring Boot Actuator er konfigurert for å eksponere relevante endepunkter:

- `health` – viser applikasjonens helsetilstand.
- `info` – gir applikasjonsinformasjon.
- `metrics` – eksponerer tilgjengelige applikasjonsmålinger.
- `prometheus` – eksponerer målinger i Prometheus-format.

Micrometer brukes til å samle inn målinger fra applikasjonen. CloudWatch-registry publiserer målingene til AWS CloudWatch under namespace `wishifai`, med publisering omtrent hvert minutt.

Dette gir mulighet til å overvåke applikasjonen uten å implementere et separat overvåkingssystem.

### 3.3 Applikasjonsmålinger

Jeg har instrumentert sentrale deler av bildeanalyseprosessen for å kunne følge med på både funksjonalitet og ytelse.

Følgende egendefinerte målinger publiseres til CloudWatch:

| Måling | Beskrivelse |
|---|---|
| `wishifai.images.analyzed.count` | Antall analyserte bilder |
| `wishifai.gifts.generated.count` | Antall genererte gaveforslag |
| `wishifai.bedrock.duration.*` | Måling av responstid fra Amazon Bedrock |
| `wishifai.rekognition.duration.*` | Måling av responstid fra Amazon Rekognition |
| `wishifai.bedrock.parse.failures.count` | Antall feil ved parsing av Bedrock-svar |
| `wishifai.analysis.count.count` | Antall analyseoperasjoner |
| `wishifai.gifts.per.request.*` | Målinger av antall gaveforslag per forespørsel |

I tillegg samles HTTP-målinger fra Spring Boot, blant annet antall forespørsler, responstid, HTTP-status og endepunkt.

Dette gjør det mulig å identifisere om en eventuell ytelsesflaskehals ligger i selve applikasjonen eller i en ekstern AWS-integrasjon.

### 3.4 CloudWatch Dashboard

Jeg har opprettet et eget CloudWatch-dashboard kalt **Wishifai-Observability**. Dashboardet gir en samlet oversikt over applikasjonens viktigste driftsmålinger.

Dashboardet inneholder ni grafer:

1. **Successful Image Analysis Requests** – antall vellykkede bildeanalyseforespørsler.
2. **Image Analysis Response Time** – gjennomsnittlig responstid for bildeanalyse.
3. **JVM Heap Memory – G1 Eden Space** – overvåking av JVM-minnebruk.
4. **Process CPU Usage** – prosessens CPU-bruk.
5. **Images Analyzed** – antall analyserte bilder.
6. **Gifts Generated** – antall genererte gaveforslag.
7. **Bedrock Parse Failures** – antall feil ved parsing av Bedrock-svar.
8. **Bedrock Response Time** – responstid fra Bedrock.
9. **Rekognition Response Time** – responstid fra Rekognition.

Dashboardet bruker CloudWatch-målinger med relevante dimensjoner, blant annet HTTP-metode, endepunkt og statuskode for å skille vellykkede analyseforespørsler fra andre HTTP-kall.

For å sikre at også målinger med lav trafikk blir synlige, er de fleste grafene konfigurert med en periode på én time. Dashboardet kan undersøkes over en tidsperiode på sju dager for å få et bedre bilde av utviklingen.

**Verifisering:** Dashboardet er deployet gjennom Terraform. Jeg har åpnet dashboardet i AWS CloudWatch, valgt tidsperioden «Last 7 days» og bekreftet at alle ni grafene viser måledata fra den kjørende applikasjonen.

### 3.5 CloudWatch Logs

Applikasjonens logger sendes til Amazon CloudWatch Logs gjennom ECS-konfigurasjonen.

Log group:

`/ecs/wishifai`

Loggene har en konfigurert retention-periode på **30 dager**.

Dette gjør det mulig å undersøke oppstartsproblemer, applikasjonsfeil og problemer med AWS-integrasjonene uten å måtte koble seg direkte til containeren.

En sentral fordel er at loggene er samlet på ett sted, uavhengig av hvilken ECS-container som håndterer forespørselen.

### 3.6 CloudWatch Alarm

Jeg har konfigurert en CloudWatch-alarm for feil ved parsing av svar fra Amazon Bedrock.

Alarm:

`wishifai-bedrock-parse-failures`

Konfigurasjonen overvåker målingen:

`wishifai.bedrock.parse.failures.count`

Alarmen bruker følgende betingelser:

- Namespace: `wishifai`
- Metric: `wishifai.bedrock.parse.failures.count`
- Statistic: `Sum`
- Period: 60 sekunder
- Threshold: Større enn eller lik 1
- Evaluation periods: 1
- Treat missing data: `notBreaching`

Dersom minst én parse-feil registreres i evalueringsperioden, går alarmen til `ALARM`-tilstand.

Jeg valgte denne målingen fordi ugyldige eller uventede svar fra Bedrock kan føre til at applikasjonen ikke klarer å generere gaveforslag, selv om selve AWS-kallet blir gjennomført.

Alarmen ble verifisert i AWS CloudWatch og viste `OK` når den siste observerte målingen var 0.

Det er ikke konfigurert SNS-varsling. Alarmens tilstand kan overvåkes direkte i CloudWatch.

### 3.7 Infrastructure as Code

CloudWatch-dashboardet, alarmen og log group er definert i Terraform under `terraform/main.tf`.

Dette gir flere fordeler:

- Overvåkingsressursene kan gjenskapes fra kode.
- Konfigurasjonen kan versjonskontrolleres sammen med resten av infrastrukturen.
- Endringer kan kontrolleres med `terraform plan` før de gjennomføres.
- Dashboard og alarmer blir en del av samme infrastruktur som ECS-tjenesten.

Etter oppdateringen av dashboardet ble følgende resultat bekreftet:

`Apply complete! Resources: 0 added, 1 changed, 0 destroyed.`

Dette viser at dashboardet ble oppdatert uten å opprette, slette eller endre andre AWS-ressurser.

### 3.8 Resultat og vurdering

Observability-løsningen gir innsyn i tre viktige områder:

**Tilgjengelighet og funksjonalitet:** HTTP-målingene og antall vellykkede bildeanalyseforespørsler viser om API-et behandler forespørsler som forventet.

**Ytelse og ressursbruk:** Responstider fra Bedrock og Rekognition, CPU-bruk og JVM-minne gjør det mulig å identifisere potensielle flaskehalser.

**Feil og feilsøking:** CloudWatch Logs og alarmen for Bedrock parse-feil gjør det enklere å oppdage og undersøke problemer.

Jeg har valgt CloudWatch fordi applikasjonen allerede kjører på AWS ECS og bruker AWS-tjenester som S3, Rekognition og Bedrock. Ved å bruke CloudWatch får vi en integrert overvåkingsløsning uten å måtte drifte en separat monitoreringsplattform.

Løsningen kan videreutvikles med blant annet SNS-varsling, flere alarmer for HTTP 5xx-feil og høy responstid, samt mer avanserte dashboards for trafikk og feilrater.

Se bilder av dashboard graf docs/screenshots



# Task 4 – Drøftingsoppgave

