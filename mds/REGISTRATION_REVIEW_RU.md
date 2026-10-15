# RegistrationController + View `customer.register` — детальный разбор

## 1. Точки входа

`routes/web.php:37` и `routes/web.php:375`:

```php
GET  customer/new -> RegistrationController@viewRegistrationForm // name: get.record.new
POST ajax/customer/save -> RegistrationController@processRegistrationForm // name: post.customer.new, middleware: ajax
```

Контроллер: `app/Http/Controllers/RegistrationController.php:9`, наследуется от `app/Http/Controllers/LoggedinController.php:12`.

`LoggedinController` инжектит `App\API $api`, `CensusApiClient`, `ReporterApiClient`, а в `callAction():62-72` выставляет `$this->initApi` с `X-Application-Token + X-User-Token(Cookie:census)`.

---

## 2. `viewRegistrationForm():11-67` — отрисовка пустой формы

1. Проверка прав: `!AuthUser::can('census_can_create') => view(errors.403)` — `RegistrationController.php:13-15`.
2. `$this->api->GetNewRegistrationFields(true)` — `app/Census/API.php:698`:
   `OPTIONS customer` с заголовками `Accept-Language:ru-RU`, `X-User-Token`, `X-New-Customer:true`, кэш 120 мин как `reg_user_{userId}_1`.
   Сортирует `citizenshipCountryId.values` (`FIRST_COUNTRY_ID=26` первым) и `institutionId.values`.
   Возвращает `APIResponse->payload = result->fields`.
3. При `!Success()` => `response()->view(errors.503,[],503)` — `RegistrationController.php:23-28`.
4. `$fields` — динамический дескриптор: каждое `lastName,firstName,middleName,birthDate,iin,file_photo,file_iin,institutionId,institutionConcessions,documentTypeId,citizenshipCountryId,regionId,address,codeword,email,phones,deliveryInstitutionId,additionalFields[]` имеет `{name,label,type,values,selected,required,extra{maxInputs,webcam,pdf}}`.
5. Учет ролей:
   * роль `institutions`: `unset(institutionConcessions.values->{0})` — прячет вариант `0` — `RegistrationController.php:32-34`.
   * право `auto_select_delivery`: подменяет `deliveryInstitutionId.values` на `initApi->getRealInstitutions()->result->data`, удаляет `0,487,496,625` — `RegistrationController.php:36-46`.
6. `$institutionWithAddFields = unique(additionalFields[].institutionId)` — для скрытых блоков под каждую организацию — `RegistrationController.php:48-54`.
7. `autoSelect(institutionId|deliveryInstitutionId):74-91`: если в `values` ровно 1 запись, `selected=этот_ключ`, иначе `selected=-2` (принудительно «выберите»).
8. `view('customer.register', [fields, educationalInstitutionsTypes, institutionWithAddFields])`. Замечание: `$lang=['ru-RU']` в строках 18-20 — мертвый код.

---

## 3. View `resources/views/customer/register.blade.php:1-393`

Наследует `app`, подключает `register.css`, `bootstrap-datepicker+ru локаль`, `select2`, `js/registerDocuments.js`, `js/register.js`.

`form#mainCustomerForm.ui.form` (без `action/method` — отправка через JS):

Левая колонка `4 wide`:
* карточка `file_photo` + превью `img#file_photo_preview` через паршл `fields/file`.
* `lastName/firstName/middleName:text` + `birthDate:date`, все `disabled:true` (включаются только после автозаполнения по ИИН в JS, ссылка `autofillDateBtn`).
* `iin:text` со спиннером + `file_iin:file`.

Правая колонка `12 wide`:
* `institutionId:institutions`.
* Если роль `duis`: скрытые `institutionConcessions=0 + _min=сегодня(d.m.Y) + _max=+10 лет`; иначе паршл `concessions` + скрытый `allConcessions=json(values)` — `register.blade.php:89-98`.
* `documentTypeId:documents` (таблица `#docTable` + модалка).
* Если роль `institutions`: скрытые `citizenshipCountryId,regionId`; иначе паршлы `select` — `register.blade.php:105-127`.
* Если `can(census_can_create_address)`: `customer.edit.forms.partial.address`.
* Если `!duis`: `codeword:text` под `census__customer_info__field__view_customer_email`, `email:email` под `view_customer_codeword`, `phones:text`; если `duis`: только `email` — `register.blade.php:133-150`.
* Если `!institutions && !duis`: `deliveryInstitutionId:institutions` — `register.blade.php:156-160`.
* Если `can(...edit_additional_fields)`: цикл по `institutionWithAddFields` => `<div#institutionWithAddFields-{id}.hidden>` с паршлами `fields.{type}`; показывается JS при `institutionId>1` в `register.js:17-21`.
* Обязательные чекбоксы `chkAccept` (дисклеймер) + `checkLogging` (действия логируются).
* Если `can(bypass_reg_check)`: чекбокс `checkIgnoreChecks` — `register.blade.php:196-208`.
* Кнопки `#btnSubmitForm + reset`.

Нижний `<script>:224-392`: задает `photoUploadURL/ajax.post.photo`, `saveCustomerURL/post.customer.new`, `fetchDocumentModalFormUrl/ajax.get.docform`, колбэки `activeFileField/setPhotoPreview` для попапов (`pdf.viewer`, `dev.get.webcam`, `dev.get.cropper` через `calculateDesktopSize()`), для каждого `$fields` с `type==file` регистрирует `regionsButtonCallback({name}_{i}[_webcam|_pdf], {name}_{i}_data, {name}_preview)`; для `type==@include` заполняет `modalregistrations[{name}_modal]={name}_modal_data` для `register.js:registerModalCall()`.

Паршлы полей в `resources/views/customer/_partials/fields/`: `text, date, select, email, file, institutions, concessions, concession, concession-period, documents`.

---

## 4. `processRegistrationForm(RegistrationRequest $request):93-150`

Выполняется только после прохождения `RegistrationRequest` (см. §5, нужен AJAX + `census_can_create`):

1. Отсев UI-полей: ключи с `chkAccept,checkLogging,documentTypeId_modal_data` отбрасываются. `checkIgnoreChecks` не пересылается; если есть и `can(bypass_reg_check)` => `$ignoreChecks=true` — `RegistrationController.php:99-114`.
2. Лог сырых данных, затем `Carbon::createFromFormat(d.m.Y)->format(Y-m-d)` для `birthDate, institutionConcessions_min/max` — при неверном формате будет 500 (но `RegistrationRequest` уже проверяет `date_format:d.m.Y`) — `RegistrationController.php:119-126`.
3. Копирование `institutionConcessions_max => customerConcessionExpiresAt` — `RegistrationController.php:130`.
4. `$this->api->AttemptCustomerRegistration(data,'ru-RU',$ignoreChecks)` в `API.php:1092`: `POST customer` с JSON (`documentTypeId=jq(decoded)`), заголовок `X-IIN-Validation: false|true` (= инверсия `$ignoreChecks`), повторная проверка `census_can_create`.
5. Маппинг backend `result->validator.{field}={isValid,message}`, где invalid => `response.invalid[field]=[message]`; при успехе => `response={isValid:true,customerId:result->data{customerId,concessionCost}}`. Всегда `jsonResponse(response,'See body',200)` — `RegistrationController.php:135-149`.

---

## 5. Валидация `app/Http/Requests/RegistrationRequest.php:18-148`

* `authorize()`: только `ajax()` + `census_can_create`.
* `rules(API $api)`: заново запрашивает `GetNewRegistrationFields()` (без bypass кэша), промоутит подходящие `additionalFields`, где `input(institutionId)==field.institutionId && can(edit_additional_fields)`, в топ-уровень, `unset(additionalFields)`. Базовые правила: `chkAccept+checkLogging:accepted`, `institutionConcessions_min:required|date_format:d.m.Y`, `_max:required|date_format:d.m.Y|after:_min`. Далее по полям: `required=>required` + кастомное сообщение `field_required`, `first/last/middleName=>ru_kk_sp`, `date=>date_format:d.m.Y`, `institutionId:required|numeric|min:0`, `file=>{name}_{i}_data:required|numeric|numeric` на `maxInputs`. Лог через `combinedLog`.
* `messages()`: `agree_termins/agree_log/invalid_file_attached/invalid_iin/concession_*/wrongInstitution` + по файлам `Поле %s является обязательным!`.

---

## 6. Frontend `public/js/register.js:30-90,196-231`

`#btnSubmitForm.click => preventDefault + serializeArray + DisableForm + AttemptCustomerRegistration`: строит `FormData`, `confirm()` если `checkIgnoreChecks`, требует `DocumentStore.GetAllDocuments()!=null` (из модалки `registerDocuments.js`, `documentTypeId`), `checkUserSession()`, `POST saveCustomerURL(processData:false)`. При `422` => `CreateAndDisplayModalErrors(xhr.responseJSON.errors)` через `POST window.variables.modalUrl`; при `200` => `ParseServerResponse`: если `result.isValid` => `alert(Регистрация прошла успешно! ID... [+concessionCost])` + `confirm(Открыть созданную анкету?) ? /customer/{id}/info : reload()`; иначе модалка с `result.invalid`.

---

## 7. Нюансы

* Хардкод `ru-RU`, неиспользуемая переменная `$lang`.
* `Carbon::createFromFormat` считает, что `birthDate/_min/_max` всегда есть — ветка `duis` дает скрытые дефолты, иначе они обязательны по валидации.
* Файловые поля валидируются как `numeric` (ID файлов после загрузки через `ajax.post.photo` / попапы cropper/webcam/pdf), а не как загрузки.
* `documentTypeId` приходит из JS `DocumentStore`, а не из нативных полей формы; `_modal_data` отрезается на сервере.
* `customerConcessionExpiresAt` выводится на сервере, а не вводится пользователем.

---

## 8. Привязка льготы — как выбирается выдаваемый `institutionConcessions`

### 8.1 Исходные данные

`OPTIONS customer` (`app/Census/API.php:698`) возвращает:

```text
fields.institutionConcessions.values:{id:{name,types:[int],parent:[int],expireDate:{from,months},endDate:{months,fixedMonth,fixedDate,from},category}}
fields.institutionId.values:{id:{name,type}}
```

Контроллер хранит полный список, view его дублирует:

* `register.blade.php:95`: `<input#allConcessions=json(values)>` — мастер-копия для JS-фильтрации.
* `register.blade.php:96 + _partials/fields/concessions.blade.php:3-28`: `div.dropdown-concession > input#id_institutionConcessions + .menu>.item[data-value][data-parent][data-from][data-months][data-max-end-date-*]` — первичный полный рендер, `disabled` до разблокировки по ИИН.
* `_partials/fields/institutions.blade.php:1-21`: `div.dropdown-institutions[data-educational-types=json(config/institutions.educational=[2,3,4,10,14])] > .item[data-value][data-type]` — `config/institutions.php:3-9`.

Переопределения по ролям на сервере:

* роль `duis` `register.blade.php:89-92`: дропдауна нет вообще, скрытые `institutionConcessions=0,_min=сегодня,_max=+10 лет`.
* роль `institutions` `RegistrationController.php:32-33`: `unset(values->{0})` — нельзя выдать «без льготы».
* `concessions.blade.php:76-84`: если `isInstitutionsUser && !empty` => `dropdown('set selected', firstKey)` — своя льгота оператора предвыбрана.

### 8.2 Фильтр `организация -> льготы` (`static/application/frontend/src/js/modules/register.js:306-351`)

На `.dropdown-institutions.onChange(value,_,choice)`:

```js
type = parseInt(choice.data('type'))
values = []
for (id in JSON.parse(#allConcessions))
  if (concession.types.includes(type)) values.push({value:id,text,parent,expireDate,endDate})
refreshConcessions(values, Object.values(educational-types))
```

`refreshConcessions():112-150` очищает `.dropdown-concession .menu`, пересоздает `div.item` с теми же `data-*`, затем `dropdown('refresh|set selected',selectedConcessions)`, где `selectedConcessions` выставляется только при `$.inArray(key,educationalTypes) && item.value!=0` — задумка: автовыбор учебной льготы, иначе остается плейсхолдер (`-1/null`). Тот же обработчик переключает доп. поля `institutionWithAddFields-{id}`.

Тот же подход при редактировании в `CustomerViewController.php:249-284`: фильтр `values` по `customer->institutionType in value->types`, ошибка `empty_concessions_list` если пусто, удаление `0` для роли `institutions` / `$hasUtc`.

### 8.3 `льгота -> даты + родитель` (`register.js:273-303,100-225 + mixins.js:339-356`)

На `.dropdown-concession.onChange`:

* `handleParentConcessions(parent)`: если `parent.length>0` => показать обертку `#id_parentIin`, спрятать `#id_institutionConcessions_max`, положить `JSON(parent)` в `#id_parentConcessionId`; иначе наоборот. Дочерняя льгота требует поиска по `parentIin` в `searchByIin.js:180-236`: `GET ajax/customer/{id}`, проверка `activeConcession in parentIds`, копирование `expiresAt -> #id_..._max`, установка `#id_parentConcessionCustomerId`, блокировка сабмита при несовпадении.
* `autoSetConcessionExpireDate(from,months)`: если `from==birthday` => `date=getDateByIin(iin)||#id_birthDate`, `+months -1 день => #id_..._max.setDate`.
* `setMaxEndDate(max-end-date-*, fetchDataForMaxEndDate(source))`: режет datepicker `setEndDate`. `source=schoolkid|student` => от `#id_..._min`; `regSchkid` => от дня рождения; затем `+monthsToAdd`, привязка к `fixedMonth/fixedDate` или `-1 день`. Перезапуск на `#id_..._min.changeDate:257-271`. `#id_..._min` по умолчанию `today:257`.

### 8.4 Выдача = что уходит в POST (`RegistrationController.php:119-133`)

`institutionConcessions=<выбранный data-value>`, `..._min/_max=d.m.Y->Y-m-d`, `customerConcessionExpiresAt=_max`, опц. `parentConcessionCustomerId` + `documentTypeId` из `DocumentStore`. `RegistrationRequest.php:58-59` требует `_min/_max:required|date_format:d.m.Y|after`, backend `POST customer (X-IIN-Validation)` делает финальную проверку `validator`, возвращает `customerId+concessionCost`.

---

## 9. Льгота применяется при каждой регистрации или может быть пустой?

Может быть «пустой», но не отсутствующей — `0 == без льготы`:

* `RegistrationRequest.php:58-59`: `institutionConcessions_min/max:required|date_format` безусловны. `register.blade.php:90-92` (`duis`) / `concessions.blade.php:31-58` (остальные) рендерятся всегда.
* Сам id `institutionConcessions` обязателен, только если backend выставил `fields.institutionConcessions.required==true` (`RegistrationRequest.php:62-64`, общий цикл). Практическое «пусто» — это `value=0`, а не отсутствие ключа.
* `RegistrationController.php:32-33` + `CustomerViewController.php:261-267`: роль `institutions` делает `unset(values->{0})` — обязана выдать реальную льготу. Остальные сохраняют `0` в `allConcessions`/`dropdown-concession` и могут его выбрать.
* `duis` принудительно пусто: `register.blade.php:90-92` скрытые `0 + сегодня/+10 лет` — `RegistrationController.php:122-130` все равно конвертирует в `Y-m-d` + `customerConcessionExpiresAt=_max`, и `API.php:1092 POST customer` хранит период даже для `0`.
* Отображение подтверждает `0` = нет: `Ajax/Customer/InfoController.php:608-609` пропускает `concessionId===0` при выборе новейшей активной льготы.
