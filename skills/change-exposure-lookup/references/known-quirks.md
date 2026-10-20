# Known quirks in the Meridian source systems

Things that look like the same data but aren't. Check each one on every lookup.

1. **Customer names don't match across CRM and ERP, and there's no shared key.** ERP names are uppercase and abbreviated ("NORTHFIELD FLEET SVCS"), and one customer can have several ERP records, such as a separate "(WEST)" ship-to. Match on the name and confirm with the email domain (CRM `CONTACTS.EMAIL` vs ERP `CUSTOMERS.BILL_TO_EMAIL`).
2. **Similar names can belong to different companies.** "Northfield Farm Supply" is not "Northfield Fleet Services". The email domain is the tie-breaker.
3. **Inactive CRM accounts.** Old duplicates are kept with `IS_ACTIVE = FALSE`. Ignore them, but mention them if they matched.
4. **Part numbers come in different formats.** ERP uses `48210A`, `0048210` and `48210-A`. PLM uses `MT-48210-A`, and components look like `MT-C-7712`. To normalize: remove `-`, strip leading zeros, take the 5 digits, and prefix `MT-`. A zero-padded ERP item with no revision letter is a legacy item for the same base part.
5. **Revisions matter.** An ECR moves a part from one revision to the next (A→B). Customers hold whatever revision their lot was built at, and an Approved ECR isn't in production yet.
6. **Different status vocabularies.** ECRs use Draft / In Review / Approved / Implemented / Cancelled. MCRs use OPEN / WIP / CLOSED / REJ. Use `PUBLIC.STATUS_MAP`.
7. **Supersession.** A part can be replaced (`LIFECYCLE = 'Superseded'`, `SUPERSEDED_BY`), and customers keep ordering the old one. Check changes on both the old and the new part number.
8. **Mixed time zones.** MES timestamps carry no zone. Each plant records in the zone given by `MES.PLANTS.TIMESTAMP_ZONE`, and some plants use local time. Convert before comparing, and flag effective dates that are still in the future.
9. **Duplicate ECRs.** A Cancelled ECR with `DUPLICATE_OF` set is a duplicate of another ECR. Report the surviving ECR only.
10. **The signal is in free text.** `SUPPORT_CASES.PRODUCT_MENTIONED` and `NOTES` are free text. Change descriptions say *why* the change is being made. Compare the two, but call a match "consistent with", never "caused by".
11. **Changes hide on components.** An MCR is often raised against a BOM child (for example a tread compound), not against the finished tire. Walk `PLM.BOM` one level down.
12. **Missing links.** `MCR.LINKED_ECR` is often NULL even when the MCR is related to an ECR. Infer the relationship from the part, the plant and the description, and label it as inferred.
