# Demo script — "What's in flight, and who's exposed?"

Runtime: 15–20 minutes. Database: `SKILL_DEMO_PLM_20261019`. Type the prompts in plain language and confirm whenever CoCo asks. CoCo may take the steps in a different order than written here; the expected answers below come from `sql/validate.sql`.

## Setup (before the audience arrives)
- Run `sql/setup.sql`, then `sql/validate.sql`. Check the results against the numbers below.
- Copy `skills/change-exposure-lookup/` into your CoCo skills folder **under a different name** (for example `change-exposure-lookup-ref`). If live skill creation runs long, you can switch to this copy.
- Start a fresh CoCo session.

---

## Part 1 — Answer the request (about 10 min)

**1.**
```
I need to understand what's going on with Northfield Fleet. They have a bunch of support cases about a tire. Data is in SKILL_DEMO_PLM_20261019 across a few schemas. Where should I look?
```
- **Talking point:** CoCo discovers the tables across four systems with nothing set up in advance. The table and column comments help it.
- **Expected:** it names the CRM, ERP, PLM and MES schemas and the key tables in each.

**2.**
```
Find Northfield in CRM and ERP. The names won't match exactly.
```
- **Talking point:** CoCo proposes matches, explains why, and asks you to confirm.
- **Expected:**
  - CRM `CRM-A-1007` Northfield Fleet Services, Inc. maps to ERP `100457` NORTHFIELD FLEET SVCS and `100458` NORTHFIELD FLEET (WEST). Both share the `northfieldfleet.example` email domain.
  - Northfield Farm Supply (`CRM-A-1012` / `100512`) is a different company. Its name scores about 85 against "FLEET", but the domain doesn't match.
  - `CRM-A-1044` is an inactive duplicate.

**3.**
```
What product are their cases about, and which part number is that in engineering?
```
- **Talking point:** CoCo pulls the product out of free text and reconciles three part-number formats.
- **Expected:** 6 cases in the last 60 days, with mentions like "48210 LT", "LT all-terrain 48210" and "the light truck tire". ERP items `48210A` and `0048210` both normalize to PLM `MT-48210-A`.

**4.**
```
Are there open engineering or manufacturing changes on that part, including its components?
```
- **Talking point:** a BOM walk, two status vocabularies mapped to one meaning, and a duplicate caught.

| ID | Type | Status → normalized | Part | Via |
|---|---|---|---|---|
| ECR-2026-014 | ECR | Approved → In progress (pending implementation) | MT-48210-A, rev A→B | Finished part |
| MCR-VC-021 | MCR | WIP → In progress | MT-C-7712 (tread compound) at VC | BOM component, no LINKED_ECR |

- **Expected exclusions:**
  - ECR-2026-009 is Cancelled and is a duplicate of 014.
  - ECR-2026-003 is Implemented.
  - MCR-VC-015 is CLOSED.

**5.**
```
Did they actually receive any affected product? Any quality holds?
```
- **Talking point:** lot traceability from order line to production lot to hold.
- **Expected:** 6 order lines, 720 units, 6 lots in total. 520 of those units (5 lines) shipped in the last 12 months; the other 200 units are an older order on the legacy item `0048210`. Either total is defensible, so let CoCo say which one it used. Five lots came from Valcourt (VC) and one older lot from Harlow Valley (HV). **3 lots are on ACTIVE hold** (L-VC-0102, 0103, 0105) for "Uniformity out of spec", which is **304 units**.

**6.**
```
Does anything in the change descriptions explain what customers are reporting?
```
- **Talking point:** the link sits in the text, not in a key.
- **Expected:** the case notes describe "vibration at highway speed" and "shimmy over 60 mph". ECR-014 addresses "high-speed uniformity (radial force variation)", and the holds cite uniformity. So the cases are *consistent with* ECR-014. MCR-021 (compound viscosity at VC) is a possible related factor.

**7.**
```
Give me a short summary I can send to the account team, with assumptions called out.
```
- **Expected caveats:**
  - Rev B is not effective until the ECR-014 target date (about 25 days out).
  - The link from MCR-021 to ECR-014 is inferred.
  - The West ship-to is assumed to be the same customer.

---

## Part 2 — Make it repeatable (about 8 min)

**8.**
```
I get this kind of request every week. Turn what we just did into a skill called change-exposure-lookup. It should work whether I start from a customer or a part, and it should ask me to confirm fuzzy matches.
```
- **Talking point:** CoCo's built-in skill-development workflow turns the session into a reusable skill. The rules the analyst just discovered become instructions.
- **Note:** the skill CoCo writes here is the one used in steps 9 and 10. `skills/change-exposure-lookup/` in this repo is only a reference for what a good result looks like.

**9.**
```
$change-exposure-lookup MT-61500
```
- **Talking point:** the same shape of answer from a different entry point, including a clarifying question.
- **Expected:**
  - MT-61500-A is **Superseded** by MT-61520-A.
  - **ECR-2026-022** (In Review) is on MT-61520-A.
  - **MCR-LM-007** (OPEN) is on MT-61500-A at Lindmark. `MES.PLANTS` shows Lindmark records local time (Europe/Berlin). If CoCo assumes UTC, ask "which time zone do the plants record in?". That's a good live moment. Its effective time is stored as 06:00 Lindmark local time, 12 days after setup ran, and it should be flagged as a future date. The UTC value depends on daylight saving (04:00 in summer, 05:00 in winter); check `validate.sql` B2 for the value on the day you present.
  - Buyers in the last 90 days:

| ERP customer | CRM match | Confidence |
|---|---|---|
| 100702 BRIGHTWATER AUTO GROUP | Brightwater Auto Group | High (name 100) |
| 100703 CASTLN MTR HLDGS | Castellan Motor Holdings LLC | Medium (abbreviation; name 86; no ERP email to compare) |
| 100704 KMG RETAIL HOLDINGS | Kestrel Motor Group | Low (name 58; only the email domain matches) |

  - The skill should ask you to confirm the Kestrel match.

**10.** (Optional)
```
$change-exposure-lookup Alder Creek Logistics
```
- **Expected:** **Nothing in flight.** Checked: MT-55120-A and its components MT-C-7720, MT-C-7745 and MT-C-7760.
- **Talking point:** the skill doesn't invent problems.

---

## Be candid about
- The data is built so that every ambiguity has a clean tie-breaker (the email domain). Real data will need more confirmation steps. The point is that CoCo *proposes and explains* the matches, and the analyst decides.
- The link from the cases to the change is *consistent with*, not proven. The analyst still confirms it with engineering.

## Extras / next steps (one slide at most)
Semantic views, Cortex Agents, Snowflake Intelligence, dashboards, real entity resolution / MDM, pipelines, and governance.
