# PGR301 – Eksamen 2026

# Wishif.ai – Eksamenbesvarelse

---

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

Containeren eksponerer port 8080 internt. For å gjøre applikasjonen tilgjengelig på localhost-port 9999 kan containeren startes med følgende kommando:

```bash
docker run --rm -p 9999:8080 <image-name>
```

Dette gjør at applikasjonen kan testes gjennom `http://localhost:9999`.

Applikasjonen bruker AWS SDK sin default credential provider chain for autentisering. Under lokal testing ble AWS-legitimasjonen gjort tilgjengelig for containeren gjennom en read-only mount av AWS-konfigurasjonen.

Jeg verifiserte at følgende funksjonalitet fungerte fra Docker-containeren:

- Opplasting av bilder til Amazon S3.
- Bildeanalyse med Amazon Rekognition.
- Generering av gaveforslag med Amazon Bedrock.

Dette var viktig fordi det ikke er tilstrekkelig å bare bekrefte at containeren starter. Den må også kunne utføre de faktiske oppgavene applikasjonen er utviklet for.

## 1.3 GitHub Actions – Continuous Integration og Continuous Deployment

Jeg har implementert en GitHub Actions-workflow i:

`.github/workflows/docker-build.yml`

Workflowen trigges automatisk ved push til `main`.

Workflowen består av to jobs:

**Job 1 – Build, test and push Docker image**

1. Checkout av GitHub-repositoriet.
2. Oppsett av Java 21 med Eclipse Temurin.
3. Kjøring av automatiserte tester med `mvn clean test`.
4. Bygging av applikasjonen med Maven.
5. Verifisering av at forventet JAR-artifakt eksisterer.
6. Generering av en Docker image-tag basert på Git commit SHA.
7. Konfigurering av AWS credentials gjennom GitHub Secrets.
8. Innlogging til Amazon ECR.
9. Bygging og publisering av Docker-imaget til ECR.

Jeg har valgt å bruke Git commit SHA som image-tag. Dette gjør det mulig å identifisere nøyaktig hvilken kodeversjon som er bygget og publisert. ECR-repositoriet bruker immutable image tags, slik at publiserte tags ikke kan overskrives.

**Job 2 – Deploy infrastructure with Terraform**

Den andre jobben kjører Terraform etter at container-jobben er ferdig.

Dette er konfigurert gjennom:

```yaml
needs: build
```

Terraform-jobben utfører følgende:

1. Checkout av repositoriet.
2. Oppsett av Terraform.
3. Konfigurering av AWS credentials fra GitHub Secrets.
4. Kontroll av Terraform-format med `terraform fmt -check -recursive`.
5. Initialisering av Terraform med `terraform init`.
6. Validering med `terraform validate`.
7. Deployment med `terraform apply`.

Image-taggen fra build-jobben sendes videre til Terraform-jobben som en output. Dermed deployes det samme imaget som nettopp ble bygget og publisert til ECR.

AWS-legitimasjonen lagres som GitHub Secrets:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

Jeg har valgt å kjøre Terraform etter container-build og ikke parallelt. Terraform trenger image-taggen fra build-jobben for å vite hvilket image ECS skal deploye. Dersom Terraform kjøres før imaget er publisert, kan ECS forsøke å hente et image som ennå ikke eksisterer i ECR.

Denne rekkefølgen sikrer derfor en kontrollert deployeringsprosess.

Workflowen er kjørt med grønt resultat, og både container-jobben og Terraform-jobben fullførte.

## 1.4 Automatiserte tester

Jeg har implementert totalt 11 automatiserte tester ved hjelp av JUnit og Spring Boot Test.

Testene er fordelt mellom `WishlistServiceTest` og `AppControllerTest`.

**WishlistServiceTest – 4 tester**

Disse testene verifiserer behandlingsflyten i applikasjonens servicelag.

| Test | Hva som verifiseres |
|---|---|
| Normal behandlingsflyt | At S3, Rekognition og Bedrock kalles i riktig rekkefølge og gir forventet resultat. |
| S3-feil | At videre behandling stoppes dersom opplasting til S3 feiler. |
| Rekognition-feil | At Bedrock ikke kalles dersom Rekognition feiler. |
| Bedrock-feil | At feil fra Bedrock håndteres og videresendes korrekt. |

Disse testene er viktige fordi applikasjonen er avhengig av flere eksterne AWS-tjenester. Ved å teste feilscenarioene verifiserer jeg også at applikasjonen ikke fortsetter behandlingen når et nødvendig steg har feilet.

**AppControllerTest – 7 tester**

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

Testene dekker både normal funksjonalitet og ugyldig input.

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
- AWS-region: `eu-west-1`.
- Health check path: `/api/health`.

Jeg valgte disse ressursverdiene som et utgangspunkt for en relativt liten Spring Boot-applikasjon. De gir applikasjonen tilgjengelige CPU- og minneressurser samtidig som ressursbruken holdes moderat.

## 2.2 Infrastructure as Code med Terraform

Jeg har valgt Terraform for å definere og administrere AWS-infrastrukturen.

Terraform-konfigurasjonen ligger i `infra/`-mappen:

- `main.tf` – definisjon av AWS-ressurser.
- `variables.tf` – variabler for konfigurasjon.
- `outputs.tf` – utdata fra infrastrukturen.
- `providers.tf` – Terraform- og AWS-provider-konfigurasjon.
- `backend.tf` – konfigurasjon av remote state i S3.
- `.terraform.lock.hcl` – låste provider-versjoner.

AWS Provider er konfigurert med versjon 6.x.

Jeg valgte Infrastructure as Code fremfor manuell opprettelse av ressursene i AWS Console fordi infrastrukturen da blir dokumentert som kode og kan gjenskapes og vedlikeholdes på en mer konsistent måte.

Terraform gir også mulighet til å kontrollere planlagte endringer før de utføres gjennom `terraform plan`.

Jeg brukte `terraform validate` og `terraform plan` før endringene ble utført med `terraform apply`.

## 2.3 Remote Terraform State

Terraform-state lagres i en sentral S3-bucket i stedet for lokalt.

Jeg bruker den delte bucketen:

`pgr301-terraform-state`

For å unngå at flere kandidater overskriver hverandres state-filer har jeg valgt en unik nøkkel basert på kandidatnummeret mitt:

`wishifai/21/terraform.tfstate`

Backend-konfigurasjonen ligger i `infra/backend.tf`.

```hcl
terraform {
  backend "s3" {
    bucket  = "pgr301-terraform-state"
    key     = "wishifai/21/terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }
}
```

Jeg valgte S3 remote state fordi dette gjør at Terraform-state lagres sentralt og kan brukes av både lokale Terraform-kjøringer og GitHub Actions-workflowen.

Dette gir en mer konsistent infrastrukturprosess og reduserer risikoen for at ulike kjøringer arbeider med forskjellige lokale state-filer.

## 2.4 Amazon ECR – Container Registry

Jeg bruker Amazon Elastic Container Registry (ECR) for lagring av Docker-imaget.

ECR-repositoriet heter:

`wishifai`

Repositoriet er konfigurert med:

- Immutable image tags.
- AES256-kryptering.
- Image scanning ved push.

Jeg valgte immutable image tags fordi et publisert image ikke skal kunne overskrives med et annet image under samme tag. Dette gjør det enklere å identifisere og kontrollere hvilken versjon som faktisk er distribuert.

Image scanning er aktivert for å kunne identifisere potensielle sårbarheter i container-imaget.

Docker-imaget ble publisert med Git commit-basert tag:

`54d3fee`

Dette gir en kobling mellom en bestemt kodeversjon og container-imaget som ble distribuert til AWS.

GitHub Actions genererer nye SHA-baserte tags ved hver push til `main` og sender taggen videre til Terraform-jobben.

## 2.5 Amazon S3 – Lagring og sikkerhet

Wishif.ai bruker Amazon S3 til lagring av opplastede bilder.

Bucket:

`wishifai-uploads`

Bucket-en er administrert gjennom Terraform og har følgende sikkerhetsinnstillinger:

- Public access block aktivert.
- Blokkering av offentlige ACL-er og bucket policies.
- AES256-kryptering.
- S3 Versioning aktivert.
- Terraform `prevent_destroy = true`.

Jeg valgte å blokkere offentlig tilgang fordi bildene ikke trenger å være tilgjengelige direkte fra internett. Applikasjonen kommuniserer med S3 gjennom AWS SDK og IAM-rettigheter.

AES256-kryptering beskytter objektene ved lagring.

S3 Versioning gjør det mulig å bevare tidligere objektversjoner dersom et objekt overskrives. Dette gir bedre beskyttelse mot utilsiktede endringer.

Jeg har også konfigurert `prevent_destroy = true` i Terraform for å redusere risikoen for at den eksisterende bucket-en slettes gjennom en utilsiktet Terraform-endring.

Terraform setter automatisk miljøvariabelen `S3_BUCKET` til navnet på bucket-en. Dette sikrer at applikasjonen bruker riktig bucket i AWS-miljøet uten at verdien må hardkodes i applikasjonen.

## 2.6 IAM – Tilgangskontroll

Jeg har brukt de eksisterende IAM-rollene som er tilgjengelige i klassens AWS-konto, i tråd med eksamenskravet.

Dette skiller mellom tillatelsene som trengs for å starte infrastrukturen og tillatelsene som trengs av selve applikasjonen.

**ECS Execution Role**

Execution role brukes av ECS til å:

- Hente container-imaget fra ECR.
- Sende containerlogger til CloudWatch.

Jeg refererer til den eksisterende rollen:

`arn:aws:iam::244530008913:role/ecsTaskExecutionRole`

**ECS Infrastructure Role**

Infrastructure role brukes av ECS Express Gateway til å administrere den nødvendige infrastrukturen.

Jeg refererer til den eksisterende rollen:

`arn:aws:iam::244530008913:role/service-role/ecsInfrastructureRoleForExpressServices`

Begge rollene hentes i Terraform gjennom `data "aws_iam_role"` i stedet for å opprette nye roller.

**ECS Task Role**

Task role brukes av Spring Boot-applikasjonen når den kommuniserer med AWS-tjenestene.

Jeg har opprettet én egen task role gjennom Terraform med kandidatnummeret som suffiks:

`wishifai-task-role-21`

Rollen har følgende tillatelser:

| AWS-tjeneste | IAM-action | Formål |
|---|---|---|
| S3 | `s3:PutObject` | Laste opp bilder til Wishifai-bucket-en. |
| Rekognition | `rekognition:DetectLabels` | Analysere bilder. |
| Bedrock | `bedrock:InvokeModel` | Generere gaveforslag. |

Jeg har valgt separate roller fordi applikasjonen ikke skal ha de samme tillatelsene som ECS trenger for å administrere infrastrukturen.

Dette følger prinsippet om minste privilegium ved at applikasjonen får egne tillatelser for AWS-operasjonene den faktisk utfører.

## 2.7 CloudWatch Logging

Jeg har opprettet en CloudWatch Log Group:

`/ecs/wishifai`

Log retention er satt til 30 dager.

ECS Express Gateway er konfigurert til å sende containerlogger til denne loggruppen med log stream prefix `wishifai`.

Dette gjør det mulig å undersøke oppstartsproblemer, runtime-feil og hendelser i applikasjonen uten å måtte koble seg direkte til containeren.

## 2.8 Health checks og deployment

Applikasjonen har et health endpoint implementert i `AppController`:

`GET /api/health`

Endpointet returnerer HTTP 200 og JSON med status `UP` når applikasjonen kjører.

Under første deployment oppdaget jeg at health check var konfigurert med `/health`, mens controlleren har en felles mapping på `/api`.

Dette førte til HTTP 404 fra health check.

Jeg undersøkte ECS-status, target group health og CloudWatch-logger for å identifisere årsaken. Deretter korrigerte jeg Terraform-konfigurasjonen til `/api/health`.

Jeg valgte å oppdatere ECS Express Gateway gjennom Terraform i stedet for å endre ressursene manuelt i AWS.

Etter oppdateringen returnerte health endpoint HTTP 200.

ECS-tjenesten ble verifisert med følgende status:

- Service status: `ACTIVE`.
- Desired tasks: 1.
- Running tasks: 1.
- Pending tasks: 0.
- Deployment rollout state: `COMPLETED`.

Dette bekreftet at tjenesten var stabil etter deployment.

Den offentlige tjeneste-URL-en er:

`https://wi-c14173a7ab6a4ad2aa6b791e77712036.ecs.eu-west-1.on.aws`

## 2.9 Ende-til-ende-testing i AWS

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

# Task 3 – Observability

## 3.1 Mål og tilnærming

Målet med observability-implementasjonen er å gjøre Wishifai-applikasjonen målbar og enklere å feilsøke i produksjon. Løsningen skal gi innsikt i applikasjonens tilgjengelighet, ytelse, ressursbruk og feil i integrasjonene mot AWS-tjenestene.

Jeg har implementert observability ved hjelp av **Spring Boot Actuator, Micrometer og Amazon CloudWatch**. Dette gir både applikasjonsspesifikke målinger og tekniske driftsmålinger fra Spring Boot og JVM.

## 3.2 Spring Boot Actuator og Micrometer

Spring Boot Actuator er konfigurert for å eksponere relevante endepunkter:

- `health` – viser applikasjonens helsetilstand.
- `info` – gir applikasjonsinformasjon.
- `metrics` – eksponerer tilgjengelige applikasjonsmålinger.
- `prometheus` – eksponerer målinger i Prometheus-format.

Micrometer brukes til å samle inn målinger fra applikasjonen. CloudWatch-registry publiserer målingene til AWS CloudWatch under namespace `wishifai`, med publisering omtrent hvert minutt.

Dette gir mulighet til å overvåke applikasjonen uten å implementere et separat overvåkingssystem.

## 3.3 Applikasjonsmålinger

Jeg har instrumentert sentrale deler av bildeanalyseprosessen for å kunne følge med på både funksjonalitet og ytelse.

Følgende egendefinerte målinger publiseres til CloudWatch:

| Måling | Beskrivelse |
|---|---|
| `wishifai.images.analyzed.count` | Antall analyserte bilder. |
| `wishifai.gifts.generated.count` | Antall genererte gaveforslag. |
| `wishifai.bedrock.duration.*` | Måling av responstid fra Amazon Bedrock. |
| `wishifai.rekognition.duration.*` | Måling av responstid fra Amazon Rekognition. |
| `wishifai.bedrock.parse.failures.count` | Antall feil ved parsing av Bedrock-svar. |
| `wishifai.analysis.count.count` | Antall analyseoperasjoner. |
| `wishifai.gifts.per.request.*` | Målinger av antall gaveforslag per forespørsel. |

Jeg har valgt å måle responstiden fra både Rekognition og Bedrock fordi disse tjenestene utgjør sentrale deler av bildeanalyseprosessen. Ved å måle dem separat kan jeg identifisere hvilken integrasjon som eventuelt står for mesteparten av behandlingstiden.

Business-metrikkene `wishifai.images.analyzed.count` og `wishifai.gifts.generated.count` gir innsikt i faktisk bruk av tjenesten, og ikke bare teknisk helse.

Målingen av gaveforslag per forespørsel gir også informasjon om hvor mye verdi applikasjonen produserer for hver analyse.

I tillegg samles HTTP-målinger fra Spring Boot, blant annet antall forespørsler, responstid, HTTP-status og endepunkt.

Dette gjør det mulig å identifisere om en eventuell ytelsesflaskehals ligger i selve applikasjonen eller i en ekstern AWS-integrasjon.

## 3.4 CloudWatch Dashboard

Jeg har opprettet et eget CloudWatch-dashboard kalt **Wishifai-Observability**. Dashboardet gir en samlet oversikt over applikasjonens viktigste driftsmålinger.

Dashboardet inneholder tolv grafer:

1. **Successful Image Analysis Requests** – antall vellykkede bildeanalyseforespørsler.
2. **Image Analysis Response Time** – gjennomsnittlig responstid for bildeanalyse.
3. **JVM Heap Memory – G1 Eden Space** – overvåking av JVM-minnebruk.
4. **Process CPU Usage** – prosessens CPU-bruk.
5. **Images Analyzed** – antall analyserte bilder.
6. **Gifts Generated** – antall genererte gaveforslag.
7. **Bedrock Parse Failures** – antall feil ved parsing av Bedrock-svar.
8. **Bedrock Response Time** – responstid fra Bedrock.
9. **Rekognition Response Time** – responstid fra Rekognition.
10. **ECS CPU Utilization** – CPU-utnyttelse for ECS-tjenesten.
11. **ECS Memory Utilization** – minneutnyttelse for ECS-tjenesten.
12. **ECS Live Task Count** – antall aktive ECS tasks.

Dashboardet dekker dermed både applikasjonsnivå og infrastruktur.

De applikasjonsspesifikke grafene bruker namespace `wishifai`, mens ECS-grafene bruker AWS sitt innebygde namespace `AWS/ECS`.

ECS-grafene bruker dimensjonene `ClusterName=default` og `ServiceName=wishifai`.

For ECS-målingene benytter jeg:

- `CPUUtilization`
- `MemoryUtilization`
- `LiveTaskCount`

Jeg aktiverte også Container Insights på ECS-clusteret for å utvide mulighetene for infrastrukturmonitorering.

Dashboardet bruker CloudWatch-målinger med relevante dimensjoner, blant annet HTTP-metode, endepunkt og statuskode for å skille vellykkede analyseforespørsler fra andre HTTP-kall.

For å sikre at også målinger med lav trafikk blir synlige, er de fleste grafene konfigurert med en periode på én time. ECS-grafene bruker en periode på fem minutter.

Dashboardet kan undersøkes over en tidsperiode på sju dager for å få et bedre bilde av utviklingen.

**Verifisering:**

Dashboardet er deployet gjennom Terraform. Jeg har åpnet dashboardet i AWS CloudWatch, valgt tidsperioden «Last 7 days» og bekreftet at grafene viser måledata fra den kjørende applikasjonen og ECS-tjenesten.

De tre ECS-grafene viser blant annet:

- ECS CPU Utilization: omtrent 3,45 % ved avlesningen.
- ECS Memory Utilization: omtrent 12,76 % ved avlesningen.
- ECS Live Task Count: datapunkter fra ECS-tjenesten.

Dette bekrefter at ECS-metrikkene blir publisert og kan visualiseres i CloudWatch.

## 3.5 CloudWatch Logs

Applikasjonens logger sendes til Amazon CloudWatch Logs gjennom ECS-konfigurasjonen.

Log group:

`/ecs/wishifai`

Loggene har en konfigurert retention-periode på **30 dager**.

Dette gjør det mulig å undersøke oppstartsproblemer, applikasjonsfeil og problemer med AWS-integrasjonene uten å måtte koble seg direkte til containeren.

En sentral fordel er at loggene er samlet på ett sted, uavhengig av hvilken ECS-container som håndterer forespørselen.

## 3.6 CloudWatch Alarm

Jeg har konfigurert en CloudWatch-alarm for feil ved parsing av svar fra Amazon Bedrock.

Alarm:

`wishifai-bedrock-parse-failures`

Konfigurasjonen overvåker målingen:

`wishifai.bedrock.parse.failures.count`

Alarmen bruker følgende betingelser:

- Namespace: `wishifai`.
- Metric: `wishifai.bedrock.parse.failures.count`.
- Statistic: `Sum`.
- Period: 60 sekunder.
- Threshold: Større enn eller lik 1.
- Evaluation periods: 1.
- Treat missing data: `notBreaching`.

Dersom minst én parse-feil registreres i evalueringsperioden, går alarmen til `ALARM`-tilstand.

Jeg valgte denne målingen fordi ugyldige eller uventede svar fra Bedrock kan føre til at applikasjonen ikke klarer å generere gaveforslag, selv om selve AWS-kallet blir gjennomført.

Alarmen ble verifisert i AWS CloudWatch og viste `OK` når den siste observerte målingen var 0.

Det er ikke konfigurert SNS-varsling. Alarmens tilstand kan overvåkes direkte i CloudWatch.

## 3.7 Infrastructure as Code

CloudWatch-dashboardet, alarmen og log group er definert i Terraform under:

`infra/main.tf`

Dette gir flere fordeler:

- Overvåkingsressursene kan gjenskapes fra kode.
- Konfigurasjonen kan versjonskontrolleres sammen med resten av infrastrukturen.
- Endringer kan kontrolleres med `terraform plan` før de gjennomføres.
- Dashboard og alarmer blir en del av samme infrastruktur som ECS-tjenesten.

Etter oppdateringen av dashboardet ble følgende resultat bekreftet:

```text
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

Dette viser at dashboardet ble oppdatert uten å opprette, slette eller endre andre AWS-ressurser.

## 3.8 Resultat og vurdering

Observability-løsningen gir innsyn i tre viktige områder:

**Tilgjengelighet og funksjonalitet:**

HTTP-målingene og antall vellykkede bildeanalyseforespørsler viser om API-et behandler forespørsler som forventet.

**Ytelse og ressursbruk:**

Responstider fra Bedrock og Rekognition, CPU-bruk, ECS-minnebruk og JVM-minne gjør det mulig å identifisere potensielle flaskehalser.

**Feil og feilsøking:**

CloudWatch Logs og alarmen for Bedrock parse-feil gjør det enklere å oppdage og undersøke problemer.

Jeg har valgt CloudWatch fordi applikasjonen allerede kjører på AWS ECS og bruker AWS-tjenester som S3, Rekognition og Bedrock. Ved å bruke CloudWatch får vi en integrert overvåkingsløsning uten å måtte drifte en separat monitoreringsplattform.

Løsningen kan videreutvikles med blant annet SNS-varsling, flere alarmer for HTTP 5xx-feil og høy responstid, samt mer avanserte dashboards for trafikk og feilrater.

# Task 4 – Drøftingsoppgave

## 4.1 Generativ AI sin påvirkning på DevOps

Generativ AI og store språkmodeller (LLM-er) påvirker hvordan moderne applikasjoner utvikles, testes, deployeres og overvåkes. I Wishif.ai brukes Amazon Bedrock til å generere gaveforslag basert på bilder som først analyseres med Amazon Rekognition. Dette introduserer nye utfordringer sammenlignet med tradisjonelle applikasjoner.

### Testing av AI-funksjonalitet

En sentral utfordring med generativ AI er at modellene er ikke-deterministiske. Den samme prompten kan gi forskjellige svar ved flere kjøringer. Derfor er det ikke alltid hensiktsmessig å bruke tradisjonelle tester som forventer identisk tekstlig respons hver gang.

For Wishif.ai kan jeg bruke et fast evalueringsdatasett med representative bilder og forventede egenskaper ved resultatene. Testene kan for eksempel kontrollere at svaret inneholder fem gaveforslag, at responsen følger forventet JSON-struktur, og at forslagene er relevante for objektene Rekognition har identifisert.

Det kan også brukes LLM-as-a-judge for å evaluere relevans og kvalitet. Slike evalueringer bør kombineres med deterministiske tester av API-kontrakter, input-validering og feilhåndtering. På denne måten kan man teste både teknisk korrekthet og kvaliteten på AI-resultatene.

### Continuous Delivery og utrulling

Generative AI-modeller og prompts bør behandles som versjonerte komponenter. En endring i prompt eller modellversjon kan påvirke resultatkvaliteten selv om applikasjonskoden er uendret.

I Wishif.ai bør derfor modell-ID, promptversjon og applikasjonsversjon kunne spores separat. Før en ny versjon settes i produksjon, bør den testes mot et evalueringsdatasett. Ved større endringer kan man bruke canary deployment eller A/B-testing for å sammenligne kvaliteten mellom versjoner.

Feature flags kan gjøre det mulig å aktivere en ny prompt eller modell for en begrenset andel brukere. Dersom kvaliteten faller eller feilraten øker, bør man kunne rulle tilbake til en tidligere versjon.

### Monitoring og observability

Tradisjonell overvåking av CPU, minne og HTTP-responstid er fortsatt nødvendig, men er ikke tilstrekkelig for AI-baserte tjenester. Man bør også overvåke antall tokens, kostnad per forespørsel, modellens responstid, feil, avvisninger og kvaliteten på genererte svar.

For Wishif.ai er måling av Bedrock- og Rekognition-responstid spesielt viktig. Dersom Bedrock bruker betydelig lengre tid enn Rekognition, kan dette identifiseres gjennom de egendefinerte CloudWatch-metrikkene. Business-metrikker som antall analyserte bilder og genererte gaveforslag gir i tillegg innsikt i faktisk bruk av tjenesten.

### Risiko og ansvarlig bruk av AI

Generativ AI kan produsere feilaktige, irrelevante eller uønskede anbefalinger. Bilder som lastes opp kan også inneholde personopplysninger. Derfor bør man begrense datalagring, beskytte S3-bucketen med IAM og blokkere offentlig tilgang. AI-resultater bør valideres før de returneres til brukeren.

Automatiserte kvalitetskontroller bør suppleres med menneskelig vurdering ved kritiske endringer. Det er også viktig å være oppmerksom på kostnader, datasikkerhet og utilsiktet eksponering av informasjon.

### Konklusjon

Generativ AI gjør DevOps mer komplekst fordi man må overvåke både teknisk drift og kvaliteten på AI-resultatene. Ved å kombinere automatiserte tester, versjonering av modeller og prompts, kontrollert utrulling og utvidet observability kan Wishif.ai utvikles og driftes på en mer pålitelig, kostnadseffektiv og ansvarlig måte.

**Dokumentasjon:**

Skjermbilder av dashboardet og AWS-ressursene legges i `docs/screenshots/` og refereres til i den endelige innleveringen.

---