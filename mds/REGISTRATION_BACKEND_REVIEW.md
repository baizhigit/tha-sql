# Registration — Backend Review (`api-master`)

Companion to `REGISTRATION_REVIEW.md` (frontend `census` web-app:
`RegistrationController`, `customer.register` view, `RegistrationRequest`,
`register.js`).

> Terminology: `GetNewRegistrationFields`, `AttemptCustomerRegistration`,
> `census_can_create`, `bypass_reg_check` do **not** exist in this repo
> (verified zero grep hits). They are frontend names. Backend equivalents are
> `OPTIONS /customer` (form descriptor) and `POST /customer` (create).
> `core/` submodule is empty in this checkout.

---

## 1. Entry points

`src/App/Applications/Api/Config/Module/Module.php:77-88`:

```php
/customer        -> POST,OPTIONS -> customers/one
/customer/{id}   -> GET,PUT,DELETE -> customers/one
```

* Controller: `src/App/Applications/Api/Modules/Main/Controller/CustomersController.php:10-109`
  `oneAction() -> getServiceResponse()`,
  `serviceClass = CustomersService::class` (`App\Model\Service\Customers`).
* Dispatch: `src/App/Model/Service/Base.php:105-177` maps
  `post -> create`, `options -> options` onto
  `App\Model\Service\Customers\Handlers\One`.
* Service: `src/App/Model/Service/Customers.php:9-18` →
  repository `App\Model\Repository\Customers`.
* Handler: `src/App/Model/Service/Customers/Handlers/One.php:35-48`
  (`configuratorClass = 'Customer'`). `create():115-168`, `update():178-234`,
  `read():56-106`, `options()` inherited.

Frontend mapping:

| Frontend | Backend |
|---|---|
| `viewRegistrationForm` → `OPTIONS customer` + `X-New-Customer:true` | `One::options()` → `BaseHandler::options()` → `Configurator\Customer` |
| `processRegistrationForm` → `POST customer` + `X-IIN-Validation:false\|true` | `One::create()` → `createCustomer()` + sub-processors |
| `RegistrationRequest` rules | `Entity\Customers::validation()` + `Entity\Customer\Concessions::validation()` + file/additional-field validators |
| `customerConcessionExpiresAt`, `parentConcessionCustomerId` | `One::createConcession()` expiry resolution |

---

## 2. `OPTIONS /customer` (= frontend `GetNewRegistrationFields`)

`src/App/Model/Service/BaseHandler.php:476-494`:

```php
fields = configurator->getFields('Customer', header('X-Form-Type'), header('X-Debug') ? true : false)
return 200 {fields}
+ Access-Control-Allow-Methods: GET, POST, OPTIONS
```

Configurator `src/App/Model/Configurator/Customer.php:22-468`:

* Dynamic `additionalFields` (`:22-68`): loads `inst_add_fields` for operator's
  institutions, emits `addField{order}_{id}_{text|date|list}`
  (`Types::TEXT_STRING/DATE_STRING/LIST_STRING`), `required:true`,
  list values via `AddFieldList::get(fieldId)`.
* `FORM_CREATE.fields` include: `file_photo` (FILE, `CUSTOMER_MAX_FILE_SIZE`,
  jpeg/gif/jpg/png/tiff, `maxInputs=CUSTOMER_MAX_FILES`, `webcam:true`,
  entity `Customer\Photos`), `iin` (`PresenceOf + @Iin`),
  `file_iin` (`maxInputs:1, webcam`), `institutionId`
  (`Filter\Institution::get`), `institutionConcessions`
  (`PSEUDO_MULTIDIMENSIONAL`, `Filter\Institution\Type\Concessions::get`),
  `phones/externalPhone` (`@Phone`), documents/addresses.
* Frontend `Accept-Language:ru-RU` / hardcoded locale has no backend effect;
  backend translate prefix is `configurator.customer.`.

Concession scoping for create —
`src/App/Model/Configurator/Filter/Institution/Type/Concessions.php:25-72,152-199`:

```php
$isNewCustomer = request->getHeader('X-New-Customer'); // frontend sends true
conditions = 'isHidden = :isHidden: AND id IN ({concessionIds})'
if ($isNewCustomer) conditions .= ' AND showOnCreate = true';
```

Then intersects with operator's allowed institutions → institution types →
`institution_type_concessions` → `concessions` rows, enriching each with
`{name, period{min,max}, parent[], types[], category{}, expireDate{from,months}?,
endDate{from,months,fixedDate,fixedMonth}?}` (`:212-254`, rules grouped by
`concessionGroupId`).

Note: frontend 120-min cache `reg_user_{id}_1` has no backend counterpart —
concession/institution changes are invisible until frontend cache expires.

---

## 3. Auth — no `census_can_create` on backend

`src/App/Applications/Api/Modules/Main/Controller/BaseController.php:131-202` +
`src/App/Component/Security/Access.php:70-186`:
`X-Application-Token + X-User-Token` JWT `validateAll()`, else
`forward(error/noAccess)`. No role-string check.

Institution scoping instead:

* `src/App/Model/Configurator/Filter/Institution.php:179-212` `getIdentifiers()`:
  allowed institution ids from JWT; empty array = superuser (sees all).
* `src/App/Model/Entity/Customers.php:1235-1292` `isUserBelongsToCustomerInstitution()`:
  superuser OR `userCanViewCustomerCity` OR `isUserBelongsToDuis` OR
  `institutionId in identifiers`.
* `Entity\Customers.php:1749-1773` `validation()`: `InclusionIn institutionId`
  with the same exemptions.
* `One.php:60-68` returns `403 forbidden` on `read()` mismatch. `create()`
  relies on entity validation only — no explicit pre-check in `createCustomer()`.

---

## 4. `POST /customer` flow (= frontend `AttemptCustomerRegistration`)

`One.php:115-168`:

```php
create(): createEntry(function (Transaction $t) {
  requestData = (array) request->getJsonRawBody(); // JSON; documentTypeId already object
  customerId = createCustomer(t, requestData);     // §5, sets iinFileId + byPassIin
  if (customerId) {
    addCustomerFilesIdentifiers(ids, requestData);
    processCustomerDocuments(t, cid, req, ids);    // §7, rollback if no documentTypeId
    processCustomerAddress(t, cid, req);
    processAdditionalFields(t, cid, req);          // §8
    concessionCost = processConcessions(t, cid, req, logger); // §6
  }
  processPhotoFiles(t, cid, req, ids);             // §7
  unlockFiles(t, ids);                             // files.isLocked=false
  initiatePrintJob(t, cid, req);                   // customer_card_print_jobs
  return 201 {customerId, concessionCost} + validator messages
})
catch: if repository messages -> 200 {validator}; else 500 message
```

Status-code mismatch to frontend: backend is `201` on success,
`200 + validator` on business-rule failure, `500` on exception. Frontend
`RegistrationController.php:135-149` normalizes everything to `200`.
Whole create is one DB transaction — `rollback()` anywhere aborts the customer row.

Update path (`One.php:178-234,561-638`) differs: `prepareRequestData`,
`validateIinAndFileId`, `processInstitutionId` (institution change → clear
additional fields + transfer), `updateOne`, then address/concessions/
additional-fields/photos, `addPrintJobIfNeeded`.

---

## 5. Customer row + IIN (`X-IIN-Validation`)

`One.php:1551-1587`:

```php
createCustomer(): setIinData(req); byPass = (header('X-IIN-Validation') === 'false');
  repository->createOne(req, true, false, ['byPassIin' => byPass]);
setIinData(): preg_grep('/^file_iin_([0-9]+)_data/', keys) -> req['iinFileId'] = first match;
```

`src/App/Model/Entity/Customers.php:1624-1717`:

* Always (unless `isAnonymous`): `Uniqueness(iin) + PresenceOf(iin)`.
* If `byPassIin == false`: `Numericality + StringLength(12,12) + Validator\Iin`
  (or egov `Callback` via `IinApi::getAddressByIin` if `validateIinByAddress`,
  which sets `egovAddress='[Е] ...'`).
* If `byPassIin == true` (frontend `checkIgnoreChecks`): checksum/birthDate
  skipped, uniqueness still enforced. No audit flag beyond `customers.byPassIin`.

`src/App/Component/Validation/Validator/Iin.php:70-152`: two-pass checksum
(`[1..11]`, fallback `[3..1,2]` when `%11==10`), then IIN-derived
`YYMMDD + century(3,4→19xx else 20xx)` must equal `birthDate Y-m-d`.
Failure appends messages to both `iin` and `birthDate` keys.
`validateIinAndFileId()` (`One.php:381-389`, update only):
`iin && !iinFileId → error emptyIinFile`. Create relies on configurator
`file_iin` required.

Watch: egov callback contains `echo "Error during validation."` — stdout leak
in API context.

---

## 6. Concessions (`institutionConcessions`, `customerConcessionExpiresAt`, `parentConcessionCustomerId`)

`One.php:1642-1669,930-1050`:

```php
processConcessions(): if (!empty(req['institutionConcessions'])) { // empty(0)/empty('0') == true
  ccId = createConcession(t, req, cid, false, {customerBirthDate: req['birthDate']});
  cost = Concession\Costs where concessionId ORDER issueCost ASC;
}
createConcession(): expire = +5 years default;
  if parentConcessionCustomerId -> getParentConcessionExpireDate(parent) ?? default;
  elsif customerConcessionExpiresAt -> Carbon::createFromFormat('Y-m-d');
  createCustomerConcession({customerId, concessionId, isActive:!nextDay,
    activatedAt: now | 1900-01-01, startedAt: today | +1day, expiresAt, isScheduled:nextDay});
  if parentConcessionCustomerId && ccId -> createConcessionTree(active ?? scheduled -> {parentId, childId});
```

Correction to `REGISTRATION_REVIEW.md §9`: backend `0` creates **no**
`customer_concessions` row (guard skips). Frontend DUIS `hidden 0 + today/+10y`
therefore stores no concession; `customerConcessionExpiresAt` is ignored when
id is `0`. Non-zero creates exactly one active row on register.

Update path (`One.php:561-638,649-713,1061-1094`): deactivates old
non-`ETK`/`EXCLUSION` rows, `transferCardFromSameConcessionType`,
`isApplyConcessionNextDay` currently always `false`.

Validation `src/App/Model/Entity/Customer/Concessions.php:570-682`:

* `InclusionIn concessionId in InstitutionTypeConcessionsFilter::get()`.
* Group rules: `age` vs birthDate, `expireDate[birthday]`, `endDate[schoolkid|student]`
  (`Validator\Concessions\Rules\Age/ExpireDate/EndDate/ParentChild/InactiveConcessionAllowed`).
* `Validator\Concessions` maxPeriod (`expiresAt in [today, now+max]`).
* Skipped only for `Cli && !isActive` (cron `deactivateConcession`).

---

## 7. Documents / photos / files (IDs, not uploads)

Upload is separate: `POST /upload/file → FilesService::One::create()`
(`UploadController.php:68-76`, `Module.php:583-587`). Registration passes only
IDs — matches frontend `numeric` rule. Example:
`tests/api/CustomersCest.php:135-254` (`file_photo_0_data`, `iinFileId`,
`documentTypeId[1].fields{docSeries,docNumber,validFrom,validUntil,file_document}`).

`One.php:1840-1902,1727-1776`:

* `addCustomerFilesIdentifiers`: collects `iinFileId`.
* `processCustomerDocuments`: per `documentTypeId` entry
  `createCustomerDocument({customerId, customerDocumentTypeId:0, ...fields})` +
  `createDocumentFile` per `file_document`; else rollback.
* `processPhotoFiles`: `preg_grep('/^file_photo_([0-9]+)_data/') →
  customer_photos{fileId,customerId,isPrimary:true}`.
* `unlockFiles`: `files.updateOne(isLocked=>false)`. Files stay locked if the
  transaction rolls back before this step.
* `Validator\Customer\Photo.php:23-55`: photo must be `<4y` and `>=2018-11-01`.

---

## 8. Additional fields

* Definition: `2.0.2/inst_add_fields.php` (`inst_add_fields{institutionId FK,
  nameFront, instAddFiledTypeId FK, fieldOrder}`), values in
  `inst_add_fields_values`, list options in `inst_add_fields_list`.
* `One.php:1681-1715`: `preg_grep('/^addField[0-9]+/')`,
  `explode('_') → [order,id,type]`, `DATE_STRING: d.m.Y→Y-m-d` via Carbon
  (throws 500 on bad format), skip falsy, `checkForDuplicateUniqueFields`
  (`UNIQUE_FIELD_IDS` → `RuntimeException`), `createOne{customerId,instAddFieldId,value}`.
* Update: upsert by `customerId+instAddFieldId`; institution change →
  `clearAdditionalFields` (delete all values) (`One.php:724-774,1158-1339`).
* Validator `src/App/Component/Validation/Validator/Customer/AdditionalFields.php:19-60`:
  all required fields for the institution must have a `Values` row.

---

## 9. Database

### 9.1 Tables written on create

| # | Table (migration) | Columns |
|---|---|---|
| 1 | `customers` (`1.0.0/customers.php`) | `id bigserial PK, institutionId int FK institutions, iin varchar(20), iinFileId bigint FK files, lastName/firstName varchar(45) NOT NULL, middleName varchar(45), birthDate date NOT NULL, citizenshipCountryId FK countries, regionId FK regions, codeword varchar(25), phones/email varchar(50), isSigned/isDeleted bool NOT NULL default false, createdAt/updatedAt timestamptz NOT NULL default now, createdBy/lastUpdatedBy varchar(50) NOT NULL, rstkId bigint, note text, byPassIin bool default false, deliveryInstitutionId int default -1`. Indexes on `createdAt, citizenshipCountryId, iin, iinFileId, institutionId, regionId, rstkId`. All FKs `CASCADE`. |
| 2 | `customer_documents` (`1.0.0/customer_documents.php`) + `customer_document_files` (`1.0.0/customer_document_files.php`) | `customer_documents{id bigserial, customerId FK NOT NULL, customerDocumentTypeId FK NOT NULL, docSeries(15), docNumber(20) NOT NULL, validFrom date NOT NULL, validUntil date, issuedBy(200) NOT NULL, note(100), isDeleted/isPrimary bool NOT NULL, createdAt/By}` + link `{fileId FK files, customerDocumentId FK}`. |
| 3 | `customer_addresses` (`1.0.0/customer_addresses.php`) | `{id bigserial, customerId FK NOT NULL, name varchar(255), updatedAt timestamptz NOT NULL, lastUpdatedBy(50) NOT NULL}`. `on_update_current_timestamp_updatedat` trigger (also on `customers`). |
| 4 | `inst_add_fields_values` (`2.0.2/inst_add_fields_values.php`) | `{customerId, instAddFieldId FK inst_add_fields, value}`; definition in `inst_add_fields` (`2.0.2/inst_add_fields.php`), types `2.0.1/2.0.3`, list `2.0.2/inst_add_fields_list.php`. |
| 5 | `customer_concessions` (`1.0.0/customer_concessions.php`) + `customer_concessions_tree` (`1.2.0/customer_concessions_tree.php`) | `customer_concessions{id bigserial, customerId FK NOT NULL, concessionId FK NOT NULL, isActive bool NOT NULL, activatedAt timestamptz NOT NULL, activatedBy(50) NOT NULL, startedAt date NOT NULL, expiresAt date, deactivatedAt timestamptz, deactivatedBy(50)}` (+ `isScheduled` added later); tree `{id bigserial, parentId FK customer_concessions NOT NULL UNIQUE, childId FK NOT NULL UNIQUE}` both `RESTRICT`. |
| 6 | `customer_photos` (`1.0.0/customer_photos.php`) | `{id bigserial, fileId FK files NOT NULL, customerId FK customers NOT NULL, isPrimary bool NOT NULL, name(100)}`. |
| 7 | `files` (`1.0.0/files.php`) | `{id bigserial, userId bigint, isLocked bool NOT NULL default true, createdAt/By, isDeleted bool NOT NULL, isUploaded bool}`. |
| side | `customer_card_print_jobs` (`1.0.0/customer_card_print_jobs.php`) | populated by `initiatePrintJob()`. |

Reference reads: `concessions{id,name(100) NOT NULL,minPeriod,maxPeriod,rstkValue,isHidden/canBlock bool} + showOnCreate` (`1.0.0/concessions.php` + later delta), `institution_type_concessions{institutionTypeId,concessionId}` (`1.0.0/institution_type_concessions.php`), `concession_costs{concessionId,cardTypeId,issueCost,reIssueCost}` (`1.0.0/concession_costs.php`), `concession_rules/groups/categories/subcategories` (`1.4.2/concession_rules.php`, `1.3.9`, `2.1.3`), `institutions/institution_types/cities/regions/countries`, `customer_document_types`, `customer_card_deliveries`.

### 9.2 Constraints / indexes

* No DB-level unique on `customers.iin` — only plain `idx_22194_iin`. Uniqueness
  is application-level (`Entity\Customers` validator) → concurrent duplicate
  POSTs can race.
* `customer_concessions` indexed on `customerId/concessionId` only; tree
  enforces `UNIQUE(parentId) + UNIQUE(childId)` (one parent / one child max).
* Date columns are `date`, timestamps `timestamptz default CURRENT_TIMESTAMP`.

### 9.3 Triggers / history / search

* `data/db/migrations/1.3.6/external_users.php:16-54`: `BEFORE DELETE ...
  EXECUTE backup_deleted()` on `customers, customer_concessions(+tree),
  customer_documents(+files/types), customer_photos, customer_addresses,
  customer_cards(+deliveries/print_jobs/transfers), customer_funds(+tx), ...`
  → mirror rows into `census_history`. Schema changes need paired history
  migrations (see `readme.md §Triggers`).
* Audit: `field_history_changes`, `actions_history`, `deleted_rows`;
  `Entity\Base.php:180-365` snapshots `columnMap()/previousValues`.
* Search: `data/elasticsearch/census/mapping-customers.json` + indexed via
  `Component/Data/Customers.php:27,143`.

---

## 10. Risks / gaps

1. `!empty(institutionConcessions)` treats `0/'0'` as absent — frontend §9
   "stores period even for 0" does not hold backend-side.
2. Uncaught `Carbon::createFromFormat` (additional fields, `customerConcessionExpiresAt`)
   → 500 on bad date; relies on frontend `date_format:d.m.Y`.
3. `byPassIin` skips checksum but keeps uniqueness; only persisted as
   `customers.byPassIin`, no separate audit.
4. Locked-file orphans when transaction rolls back before `unlockFiles()`.
5. `echo` in egov IIN callback; `Cli && !isActive` concession-validation bypass
   (cron) — check log/monitor noise.
6. Frontend cache (`reg_user_*` 120 min) vs no backend cache — stale
   concession/institution descriptors possible.
7. IIN uniqueness without DB constraint — add partial unique index
   `WHERE isDeleted=false` if duplicates observed.
