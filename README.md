# Meridian Tire & Rubber — CoCo Analyst Demo

**"What's in flight, and who's exposed?"**

A 15–20 minute demo for business analysts. An analyst gets an ambiguous request: *a customer is complaining, so what part is it, are there open engineering or manufacturing changes on it, and does anything in flight explain the complaint?* The answer is spread across four systems that disagree on names, part numbers, status values and time zones. Cortex Code finds the tables, works through the ambiguity with the analyst, and produces an answer with caveats. Then it turns the session into a reusable skill.

All company, customer, part and plant names are fictional.

## Five-minute overview
- **Four source systems in one database:**
  - `CRM`: accounts, contacts, support cases
  - `ERP`: customers, items, orders and lines with lot numbers
  - `PLM`: parts, BOM, engineering change requests
  - `MES`: manufacturing change requests, production lots, quality holds
- **Built-in quirks the analyst runs into:** mismatched names, a decoy company, three part-number formats, revisions, supersession, two status vocabularies, a plant that stores local time, a duplicate ECR, changes hidden on BOM components, and a missing ECR link.
- **Three scenarios:**
  - A: customer entry point, the main walkthrough
  - B: part entry point, rerun with the skill
  - C: a clean result

## Run it
1. Open `sql/setup.sql` and fill in the variables block (`DEMO_WH`, `DEMO_ROLE`; `DEMO_DB` defaults to `SKILL_DEMO_PLM_20261019`). The script stops with an error if any value is blank.
2. Run `sql/setup.sql`. It's re-runnable, and the dates are relative to the run date.
3. Run `sql/validate.sql` and compare the results with `demo/demo_script.md`.
4. Present from `demo/demo_script.md`.
5. When you're done, run `sql/teardown.sql`.

## Layout
```
sql/setup.sql        variables block, schemas, tables + comments, seed data, STATUS_MAP
sql/validate.sql     ground-truth queries for every scenario
sql/teardown.sql     drops the database
demo/demo_script.md  prompts, talking points, expected answers
skills/change-exposure-lookup/SKILL.md                    reference copy of the skill
skills/change-exposure-lookup/references/known-quirks.md  what to watch for
```
