# RegistrationController + `customer.register` View — Detailed Review

## 1. Entry points

`routes/web.php:37` and `routes/web.php:375`:

```php
GET  customer/new -> RegistrationController@viewRegistrationForm // name: get.record.new
POST ajax/customer/save -> RegistrationController@processRegistrationForm // name: post.customer.new, middleware: ajax
```

Controller: `app/Http/Controllers/RegistrationController.php:9` extends `app/Http/Controllers/LoggedinController.php:12`.

`LoggedinController` injects `App\API $api`, `CensusApiClient`, `ReporterApiClient` and in `callAction():62-72` sets `$this->initApi` with `X-Application-Token + X-User-Token(Cookie:census)`.

---

## 2. `viewRegistrationForm():11-67` — render empty form

1. Gate: `!AuthUser::can('census_can_create') => view(errors.403)` — `RegistrationController.php:13-15`.
2. `$this->api->GetNewRegistrationFields(true)` — `app/Census/API.php:698`:
   `OPTIONS customer` with `Accept-Language:ru-RU`, `X-User-Token`, `X-New-Customer:true`, cached 120 min as `reg_user_{userId}_1`.
   Sorts `citizenshipCountryId.values` (puts `FIRST_COUNTRY_ID=26` first) and `institutionId.values`.
   Returns `APIResponse->payload = result->fields`.
3. On `!Success()` => `response()->view(errors.503,[],503)` — `RegistrationController.php:23-28`.
4. `$fields` is dynamic descriptor object: each `lastName,firstName,middleName,birthDate,iin,file_photo,file_iin,institutionId,institutionConcessions,documentTypeId,citizenshipCountryId,regionId,address,codeword,email,phones,deliveryInstitutionId,additionalFields[]` has `{name,label,type,values,selected,required,extra{maxInputs,webcam,pdf}}`.
5. Role tailoring:
   * `institutions` role: `unset(institutionConcessions.values->{0})` — hides `0` option — `RegistrationController.php:32-34`.
   * `auto_select_delivery` permission: replaces `deliveryInstitutionId.values` with `initApi->getRealInstitutions()->result->data`, removes `0,487,496,625` — `RegistrationController.php:36-46`.
6. `$institutionWithAddFields = unique(additionalFields[].institutionId)` — used to render per-institution hidden blocks — `RegistrationController.php:48-54`.
7. `autoSelect(institutionId|deliveryInstitutionId):74-91`: if `values` has exactly 1 entry, `selected=that_key`, else `selected=-2` (force "choose").
8. `view('customer.register', [fields, educationalInstitutionsTypes, institutionWithAddFields])`. Note: `$lang=['ru-RU']` at line 18-20 is dead code.

---

## 3. View `resources/views/customer/register.blade.php:1-393`

Extends `app`, loads `register.css`, `bootstrap-datepicker+ru locale`, `select2`, `js/registerDocuments.js`, `js/register.js`.

`form#mainCustomerForm.ui.form` (no `action/method` — submitted via JS):

Left `4 wide`:
* `file_photo` card + preview `img#file_photo_preview` via `fields/file` partial.
* `lastName/firstName/middleName:text` + `birthDate:date` all `disabled:true` (enabled only after IIN-autofill in JS, `autofillDateBtn` link).
* `iin:text` with spinner + `file_iin:file`.

Right `12 wide`:
* `institutionId:institutions` partial.
* If `duis` role: hidden `institutionConcessions=0 + _min=today(d.m.Y) + _max=+10y`; else `concessions` partial + hidden `allConcessions=json(values)` — `register.blade.php:89-98`.
* `documentTypeId:documents` partial (table `#docTable` + modal trigger).
* If `institutions` role: hidden `citizenshipCountryId,regionId`; else `select` partials — `register.blade.php:105-127`.
* If `can(census_can_create_address)`: `customer.edit.forms.partial.address`.
* If `!duis`: `codeword:text` gated by `census__customer_info__field__view_customer_email`, `email:email` gated by `view_customer_codeword`, `phones:text`; if `duis`: only `email` — `register.blade.php:133-150`.
* If `!institutions && !duis`: `deliveryInstitutionId:institutions` — `register.blade.php:156-160`.
* If `can(...edit_additional_fields)`: loops `institutionWithAddFields` => `<div#institutionWithAddFields-{id}.hidden>` with `fields.{type}` partials; shown by JS when `institutionId>1` in `register.js:17-21`.
* Mandatory `chkAccept` (disclaimer) + `checkLogging` (actions logged) checkboxes.
* If `can(bypass_reg_check)`: `checkIgnoreChecks` negative message — `register.blade.php:196-208`.
* `#btnSubmitForm + reset`.

Bottom `<script>:224-392`: defines `photoUploadURL/ajax.post.photo`, `saveCustomerURL/post.customer.new`, `fetchDocumentModalFormUrl/ajax.get.docform`, `activeFileField/setPhotoPreview` callbacks for popup windows (`pdf.viewer`, `dev.get.webcam`, `dev.get.cropper` via `calculateDesktopSize()`), and for every `$fields` of `type==file` registers `regionsButtonCallback({name}_{i}[_webcam|_pdf], {name}_{i}_data, {name}_preview)`; for `type==@include` fills `modalregistrations[{name}_modal]={name}_modal_data` used by `register.js:registerModalCall()`.

Field partials in `resources/views/customer/_partials/fields/`: `text, date, select, email, file, institutions, concessions, concession, concession-period, documents`.

---

## 4. `processRegistrationForm(RegistrationRequest $request):93-150`

Runs only after `RegistrationRequest` passes (see §5, AJAX + `census_can_create` required):

1. Strip UI-only fields: any key containing `chkAccept,checkLogging,documentTypeId_modal_data` dropped. `checkIgnoreChecks` not forwarded; if present and `can(bypass_reg_check)` => `$ignoreChecks=true` — `RegistrationController.php:99-114`.
2. Logs raw, then `Carbon::createFromFormat(d.m.Y)->format(Y-m-d)` for `birthDate, institutionConcessions_min/max` — will throw 500 if format wrong (but `RegistrationRequest` already enforces `date_format:d.m.Y`) — `RegistrationController.php:119-126`.
3. Copies `institutionConcessions_max => customerConcessionExpiresAt` — `RegistrationController.php:130`.
4. `$this->api->AttemptCustomerRegistration(data,'ru-RU',$ignoreChecks)` in `API.php:1092`: `POST customer` JSON body (`documentTypeId=jq(decoded)`), header `X-IIN-Validation: false|true` (=inverse of `$ignoreChecks`), re-checks `census_can_create`.
5. Maps backend `result->validator.{field}={isValid,message}` where invalid => `response.invalid[field]=[message]`; on success => `response={isValid:true,customerId:result->data{customerId,concessionCost}}`. Always `jsonResponse(response,'See body',200)` — `RegistrationController.php:135-149`.

---

## 5. Validation `app/Http/Requests/RegistrationRequest.php:18-148`

* `authorize()`: must be `ajax()` + `census_can_create`.
* `rules(API $api)`: re-fetches `GetNewRegistrationFields()` (no bypass cache), promotes matching `additionalFields` where `input(institutionId)==field.institutionId && can(edit_additional_fields)` to top-level, `unset(additionalFields)`. Base rules: `chkAccept+checkLogging:accepted`, `institutionConcessions_min:required|date_format:d.m.Y`, `_max:required|date_format:d.m.Y|after:_min`. Then per-field: `required=>required` + custom `field_required` message, `first/last/middleName=>ru_kk_sp`, `date=>date_format:d.m.Y`, `institutionId:required|numeric|min:0`, `file=>{name}_{i}_data:required|numeric|numeric` for `maxInputs`. Logged via `combinedLog`.
* `messages()`: `agree_termins/agree_log/invalid_file_attached/invalid_iin/concession_*/wrongInstitution` + per-file `Поле %s является обязательным!`.

---

## 6. Frontend `public/js/register.js:30-90,196-231`

`#btnSubmitForm.click => preventDefault + serializeArray + DisableForm + AttemptCustomerRegistration`: builds `FormData`, `confirm()` if `checkIgnoreChecks`, requires `DocumentStore.GetAllDocuments()!=null` (from `registerDocuments.js` modal, `documentTypeId`), `checkUserSession()`, `POST saveCustomerURL(processData:false)`. On `422` => `CreateAndDisplayModalErrors(xhr.responseJSON.errors)` via `POST window.variables.modalUrl`; on `200` => `ParseServerResponse`: if `result.isValid` => `alert(Регистрация прошла успешно! ID... [+concessionCost])` + `confirm(Открыть созданную анкету?) ? /customer/{id}/info : reload()`; else modal with `result.invalid`.

---

## 7. Notes / gotchas

* Hardcoded `ru-RU`, unused `$lang` variable.
* `Carbon::createFromFormat` assumes `birthDate/_min/_max` always present — `duis` path supplies hidden defaults, otherwise validated as required.
* File fields validated as `numeric` (file IDs from prior upload via `ajax.post.photo` / cropper/webcam/pdf popups), not actual uploads.
* `documentTypeId` comes from `DocumentStore` JS, not native form fields; `_modal_data` excluded server-side.
* `customerConcessionExpiresAt` derived server-side, not user input.

---

## 8. Concession binding — how the granted `institutionConcessions` is chosen

### 8.1 Source data

`OPTIONS customer` (`app/Census/API.php:698`) returns:

```text
fields.institutionConcessions.values:{id:{name,types:[int],parent:[int],expireDate:{from,months},endDate:{months,fixedMonth,fixedDate,from},category}}
fields.institutionId.values:{id:{name,type}}
```

Controller keeps full list, view duplicates it:

* `register.blade.php:95`: `<input#allConcessions=json(values)>` — master copy for JS filtering.
* `register.blade.php:96 + _partials/fields/concessions.blade.php:3-28`: `div.dropdown-concession > input#id_institutionConcessions + .menu>.item[data-value][data-parent][data-from][data-months][data-max-end-date-*]` — initial full render, `disabled` until IIN-autofill unlocks.
* `_partials/fields/institutions.blade.php:1-21`: `div.dropdown-institutions[data-educational-types=json(config/institutions.educational=[2,3,4,10,14])] > .item[data-value][data-type]` — `config/institutions.php:3-9`.

Role overrides server-side:

* `duis` role `register.blade.php:89-92`: no dropdown at all, hidden `institutionConcessions=0,_min=today,_max=+10y`.
* `institutions` role `RegistrationController.php:32-33`: `unset(values->{0})` — can't grant "no benefit".
* `concessions.blade.php:76-84`: if `isInstitutionsUser && !empty` => `dropdown('set selected', firstKey)` — operator's own concession pre-selected.

### 8.2 `institution -> concessions` filter (`static/application/frontend/src/js/modules/register.js:306-351`)

On `.dropdown-institutions.onChange(value,_,choice)`:

```js
type = parseInt(choice.data('type'))
values = []
for (id in JSON.parse(#allConcessions))
  if (concession.types.includes(type)) values.push({value:id,text,parent,expireDate,endDate})
refreshConcessions(values, Object.values(educational-types))
```

`refreshConcessions():112-150` wipes `.dropdown-concession .menu`, rebuilds `div.item` with same `data-*`, then `dropdown('refresh|set selected',selectedConcessions)` where `selectedConcessions` is set only if `$.inArray(key,educationalTypes) && item.value!=0` — intent: auto-pick educational benefit, otherwise leave placeholder (`-1/null`). Same handler also toggles `institutionWithAddFields-{id}` extra fields.

Same pattern for edits in `CustomerViewController.php:249-284`: filters `values` by `customer->institutionType in value->types`, errors `empty_concessions_list` if none left, removes `0` for `institutions` role / `$hasUtc`.

### 8.3 `concession -> dates + parent` (`register.js:273-303,100-225 + mixins.js:339-356`)

On `.dropdown-concession.onChange`:

* `handleParentConcessions(parent)`: if `parent.length>0` => unhide `#id_parentIin` wrapper, hide `#id_institutionConcessions_max`, store `JSON(parent)` in `#id_parentConcessionId`; else reverse. Child benefit then requires `parentIin` lookup in `searchByIin.js:180-236`: `GET ajax/customer/{id}`, checks `activeConcession in parentIds`, copies its `expiresAt -> #id_..._max`, sets `#id_parentConcessionCustomerId`, blocks submit if no match.
* `autoSetConcessionExpireDate(from,months)`: if `from==birthday` => `date=getDateByIin(iin)||#id_birthDate`, `+months -1day => #id_..._max.setDate`.
* `setMaxEndDate(max-end-date-*, fetchDataForMaxEndDate(source))`: clamps datepicker `setEndDate`. `source=schoolkid|student` => from `#id_..._min`; `regSchkid` => from birthday; then `+monthsToAdd`, snap to `fixedMonth/fixedDate` or `-1day`. Re-run on `#id_..._min.changeDate:257-271`. `#id_..._min` defaults to `today:257`.

### 8.4 Grant = what is POSTed (`RegistrationController.php:119-133`)

`institutionConcessions=<selected data-value>`, `..._min/_max=d.m.Y->Y-m-d`, `customerConcessionExpiresAt=_max`, `parentConcessionCustomerId?` + `documentTypeId` from `DocumentStore`. `RegistrationRequest.php:58-59` enforces `_min/_max:required|date_format:d.m.Y|after`, backend `POST customer (X-IIN-Validation)` does final `validator` check, returns `customerId+concessionCost`.

---

## 9. Is a concession applied on every registration, or can it be empty?

It can be "empty", but not absent — `0 == no benefit`:

* `RegistrationRequest.php:58-59`: `institutionConcessions_min/max:required|date_format` unconditional. `register.blade.php:90-92` (`duis`) / `concessions.blade.php:31-58` (others) always render them.
* `institutionConcessions` id itself only `required` if backend `fields.institutionConcessions.required==true` (`RegistrationRequest.php:62-64`, generic loop). Practical "empty" is `value=0`, not missing key.
* `RegistrationController.php:32-33` + `CustomerViewController.php:261-267`: `institutions` role `unset(values->{0})` — must grant real benefit. Everyone else keeps `0` in `allConcessions`/`dropdown-concession` and can choose it.
* `duis` forced empty: `register.blade.php:90-92` hidden `0 + today/+10y` — `RegistrationController.php:122-130` still converts to `Y-m-d` + `customerConcessionExpiresAt=_max` and `API.php:1092 POST customer` stores period even for `0`.
* Display confirms `0` = none: `Ajax/Customer/InfoController.php:608-609` skips `concessionId===0` when picking newest active concession name.
