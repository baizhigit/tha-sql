# Регистрация — Backend-ревью (`api-master`)

Дополнение к `REGISTRATION_REVIEW.md` (фронтенд `census`:
`RegistrationController`, view `customer.register`, `RegistrationRequest`,
`register.js`).

> Терминология: `GetNewRegistrationFields`, `AttemptCustomerRegistration`,
> `census_can_create`, `bypass_reg_check` в этом репозитории **отсутствуют**
> (проверено поиском, ноль совпадений). Это названия фронтенда. Эквиваленты бэкенда —
> `OPTIONS /customer` (дескриптор формы) и `POST /customer` (создание).
> Сабмодуль `core/` в данном чекауте пуст.

---

## 1. Точки входа

`src/App/Applications/Api/Config/Module/Module.php:77-88`:

```php
/customer        -> POST,OPTIONS -> customers/one
/customer/{id}   -> GET,PUT,DELETE -> customers/one
```

* Контроллер: `src/App/Applications/Api/Modules/Main/Controller/CustomersController.php:10-109`
  `oneAction() -> getServiceResponse()`,
  `serviceClass = CustomersService::class` (`App\Model\Service\Customers`).
* Диспетчеризация: `src/App/Model/Service/Base.php:105-177` отображает
  `post -> create`, `options -> options` на
  `App\Model\Service\Customers\Handlers\One`.
* Сервис: `src/App/Model/Service/Customers.php:9-18` →
  репозиторий `App\Model\Repository\Customers`.
* Хендлер: `src/App/Model/Service/Customers/Handlers/One.php:35-48`
  (`configuratorClass = 'Customer'`). `create():115-168`, `update():178-234`,
  `read():56-106`, `options()` — унаследован.

Соответствие фронтенду:

| Фронтенд | Бэкенд |
|---|---|
| `viewRegistrationForm` → `OPTIONS customer` + `X-New-Customer:true` | `One::options()` → `BaseHandler::options()` → `Configurator\Customer` |
| `processRegistrationForm` → `POST customer` + `X-IIN-Validation:false\|true` | `One::create()` → `createCustomer()` + подпроцессоры |
| Правила `RegistrationRequest` | `Entity\Customers::validation()` + `Entity\Customer\Concessions::validation()` + валидаторы файлов/допполей |
| `customerConcessionExpiresAt`, `parentConcessionCustomerId` | Разрешение expiry в `One::createConcession()` |

---

## 2. `OPTIONS /customer` (= фронтендовый `GetNewRegistrationFields`)

`src/App/Model/Service/BaseHandler.php:476-494`:

```php
fields = configurator->getFields('Customer', header('X-Form-Type'), header('X-Debug') ? true : false)
return 200 {fields}
+ Access-Control-Allow-Methods: GET, POST, OPTIONS
```

Конфигуратор `src/App/Model/Configurator/Customer.php:22-468`:

* Динамические `additionalFields` (`:22-68`): загружает `inst_add_fields` для
  учреждений оператора, генерирует `addField{order}_{id}_{text|date|list}`
  (`Types::TEXT_STRING/DATE_STRING/LIST_STRING`), `required:true`,
  значения списков через `AddFieldList::get(fieldId)`.
* Поля `FORM_CREATE`: `file_photo` (FILE, `CUSTOMER_MAX_FILE_SIZE`,
  jpeg/gif/jpg/png/tiff, `maxInputs=CUSTOMER_MAX_FILES`, `webcam:true`,
  сущность `Customer\Photos`), `iin` (`PresenceOf + @Iin`),
  `file_iin` (`maxInputs:1, webcam`), `institutionId`
  (`Filter\Institution::get`), `institutionConcessions`
  (`PSEUDO_MULTIDIMENSIONAL`, `Filter\Institution\Type\Concessions::get`),
  `phones/externalPhone` (`@Phone`), документы/адреса.
* Фронтендовые `Accept-Language:ru-RU` / захардкоженная локаль на бэкенд не влияют;
  префикс переводов бэкенда — `configurator.customer.`.

Скоупинг льгот для создания —
`src/App/Model/Configurator/Filter/Institution/Type/Concessions.php:25-72,152-199`:

```php
$isNewCustomer = request->getHeader('X-New-Customer'); // фронтенд шлёт true
conditions = 'isHidden = :isHidden: AND id IN ({concessionIds})'
if ($isNewCustomer) conditions .= ' AND showOnCreate = true';
```

Далее пересечение с разрешёнными оператору учреждениями → типы учреждений →
`institution_type_concessions` → строки `concessions`, каждая обогащается
`{name, period{min,max}, parent[], types[], category{}, expireDate{from,months}?,
endDate{from,months,fixedDate,fixedMonth}?}` (`:212-254`, правила группируются по
`concessionGroupId`).

Важно: фронтендовый кеш 120 минут `reg_user_{id}_1` аналога на бэкенде не имеет —
изменения льгот/учреждений не видны, пока не протухнет кеш фронтенда.

---

## 3. Авторизация — `census_can_create` на бэкенде нет

`src/App/Applications/Api/Modules/Main/Controller/BaseController.php:131-202` +
`src/App/Component/Security/Access.php:70-186`:
JWT `X-Application-Token + X-User-Token`, `validateAll()`, иначе
`forward(error/noAccess)`. Проверки по строке роли нет.

Вместо этого — скоупинг по учреждениям:

* `src/App/Model/Configurator/Filter/Institution.php:179-212` `getIdentifiers()`:
  разрешённые id учреждений из JWT; пустой массив = суперпользователь (видит всё).
* `src/App/Model/Entity/Customers.php:1235-1292` `isUserBelongsToCustomerInstitution()`:
  суперпользователь ИЛИ `userCanViewCustomerCity` ИЛИ `isUserBelongsToDuis` ИЛИ
  `institutionId in identifiers`.
* `Entity\Customers.php:1749-1773` `validation()`: `InclusionIn institutionId`
  с теми же исключениями.
* `One.php:60-68` на `read()` возвращает `403 forbidden` при несовпадении.
  `create()` опирается только на валидацию сущности — явной предварительной
  проверки в `createCustomer()` нет.

---

## 4. `POST /customer` (= фронтендовый `AttemptCustomerRegistration`)

`One.php:115-168`:

```php
create(): createEntry(function (Transaction $t) {
  requestData = (array) request->getJsonRawBody(); // JSON; documentTypeId уже объект
  customerId = createCustomer(t, requestData);     // §5, проставляет iinFileId + byPassIin
  if (customerId) {
    addCustomerFilesIdentifiers(ids, requestData);
    processCustomerDocuments(t, cid, req, ids);    // §7, rollback без documentTypeId
    processCustomerAddress(t, cid, req);
    processAdditionalFields(t, cid, req);          // §8
    concessionCost = processConcessions(t, cid, req, logger); // §6
  }
  processPhotoFiles(t, cid, req, ids);             // §7
  unlockFiles(t, ids);                             // files.isLocked=false
  initiatePrintJob(t, cid, req);                   // customer_card_print_jobs
  return 201 {customerId, concessionCost} + сообщения validator
})
catch: если есть сообщения репозитория -> 200 {validator}; иначе 500 message
```

Расхождение с фронтендом: бэкенд возвращает `201` при успехе,
`200 + validator` при бизнес-ошибке, `500` при исключении. Фронтендовый
`RegistrationController.php:135-149` нормализует всё к `200`.
Всё создание — одна DB-транзакция: `rollback()` в любом месте отменяет и строку клиента.

Ветка обновления (`One.php:178-234,561-638`) отличается: `prepareRequestData`,
`validateIinAndFileId`, `processInstitutionId` (смена учреждения → очистка
допполей + трансфер), `updateOne`, затем адрес/льготы/допполя/фото,
`addPrintJobIfNeeded`.

---

## 5. Строка клиента + ИИН (`X-IIN-Validation`)

`One.php:1551-1587`:

```php
createCustomer(): setIinData(req); byPass = (header('X-IIN-Validation') === 'false');
  repository->createOne(req, true, false, ['byPassIin' => byPass]);
setIinData(): preg_grep('/^file_iin_([0-9]+)_data/', keys) -> req['iinFileId'] = первое совпадение;
```

`src/App/Model/Entity/Customers.php:1624-1717`:

* Всегда (кроме `isAnonymous`): `Uniqueness(iin) + PresenceOf(iin)`.
* Если `byPassIin == false`: `Numericality + StringLength(12,12) + Validator\Iin`
  (либо egov-`Callback` через `IinApi::getAddressByIin`, если `validateIinByAddress`,
  проставляет `egovAddress='[Е] ...'`).
* Если `byPassIin == true` (фронтендовый `checkIgnoreChecks`): контрольная сумма/
  дата рождения пропускаются, уникальность всё равно проверяется. Отдельного
  аудита кроме `customers.byPassIin` нет.

`src/App/Component/Validation/Validator/Iin.php:70-152`: двухпроходная контрольная
сумма (`[1..11]`, запасной `[3..1,2]` при `%11==10`), затем выведенная из ИИН
дата `YYMMDD + век(3,4→19xx иначе 20xx)` обязана совпасть с `birthDate Y-m-d`.
При неуспехе сообщения добавляются сразу в ключи `iin` и `birthDate`.
`validateIinAndFileId()` (`One.php:381-389`, только update):
`iin && !iinFileId → ошибка emptyIinFile`. На создании работает требование
конфигуратора к `file_iin`.

Замечание: в egov-колбэке есть `echo "Error during validation."` — мусор в stdout
API-контекста.

---

## 6. Льготы (`institutionConcessions`, `customerConcessionExpiresAt`, `parentConcessionCustomerId`)

`One.php:1642-1669,930-1050`:

```php
processConcessions(): if (!empty(req['institutionConcessions'])) { // empty(0)/empty('0') == true
  ccId = createConcession(t, req, cid, false, {customerBirthDate: req['birthDate']});
  cost = Concession\Costs where concessionId ORDER issueCost ASC;
}
createConcession(): expire = +5 лет по умолчанию;
  if parentConcessionCustomerId -> getParentConcessionExpireDate(parent) ?? default;
  elsif customerConcessionExpiresAt -> Carbon::createFromFormat('Y-m-d');
  createCustomerConcession({customerId, concessionId, isActive:!nextDay,
    activatedAt: now | 1900-01-01, startedAt: today | +1day, expiresAt, isScheduled:nextDay});
  if parentConcessionCustomerId && ccId -> createConcessionTree(active ?? scheduled -> {parentId, childId});
```

Поправка к `REGISTRATION_REVIEW.md §9`: бэкенд при `0` **не создаёт** строку
`customer_concessions` (гвард пропускает). Фронтендовый DUIS `hidden 0 + today/+10y`
следовательно льготу не сохраняет; `customerConcessionExpiresAt` при id `0`
игнорируется. Ненулевой id создаёт ровно одну активную запись при регистрации.

Ветка обновления (`One.php:561-638,649-713,1061-1094`): деактивирует старые строки
кроме `ETK`/`EXCLUSION`, `transferCardFromSameConcessionType`,
`isApplyConcessionNextDay` сейчас всегда `false`.

Валидация `src/App/Model/Entity/Customer/Concessions.php:570-682`:

* `InclusionIn concessionId in InstitutionTypeConcessionsFilter::get()`.
* Групповые правила: `age` vs даты рождения, `expireDate[birthday]`,
  `endDate[schoolkid|student]`
  (`Validator\Concessions\Rules\Age/ExpireDate/EndDate/ParentChild/InactiveConcessionAllowed`).
* `Validator\Concessions` maxPeriod (`expiresAt in [today, now+max]`).
* Пропуск только для `Cli && !isActive` (крон `deactivateConcession`).

---

## 7. Документы / фото / файлы (ID, а не загрузки)

Загрузка — отдельно: `POST /upload/file → FilesService::One::create()`
(`UploadController.php:68-76`, `Module.php:583-587`). Регистрация передаёт только
ID — соответствует фронтендовому правилу `numeric`. Пример:
`tests/api/CustomersCest.php:135-254` (`file_photo_0_data`, `iinFileId`,
`documentTypeId[1].fields{docSeries,docNumber,validFrom,validUntil,file_document}`).

`One.php:1840-1902,1727-1776`:

* `addCustomerFilesIdentifiers`: собирает `iinFileId`.
* `processCustomerDocuments`: на каждую запись `documentTypeId`
  `createCustomerDocument({customerId, customerDocumentTypeId:0, ...fields})` +
  `createDocumentFile` на каждый `file_document`; иначе rollback.
* `processPhotoFiles`: `preg_grep('/^file_photo_([0-9]+)_data/') →
  customer_photos{fileId,customerId,isPrimary:true}`.
* `unlockFiles`: `files.updateOne(isLocked=>false)`. При откате транзакции до этого
  шага файлы остаются заблокированными.
* `Validator\Customer\Photo.php:23-55`: фото должно быть `<4 лет` и `>=2018-11-01`.

---

## 8. Дополнительные поля

* Определение: `2.0.2/inst_add_fields.php` (`inst_add_fields{institutionId FK,
  nameFront, instAddFiledTypeId FK, fieldOrder}`), значения —
  `inst_add_fields_values`, опции списков — `inst_add_fields_list`.
* `One.php:1681-1715`: `preg_grep('/^addField[0-9]+/')`,
  `explode('_') → [order,id,type]`, `DATE_STRING: d.m.Y→Y-m-d` через Carbon
  (при плохом формате — 500), пропуск falsy, `checkForDuplicateUniqueFields`
  (`UNIQUE_FIELD_IDS` → `RuntimeException`), `createOne{customerId,instAddFieldId,value}`.
* Обновление: upsert по `customerId+instAddFieldId`; смена учреждения →
  `clearAdditionalFields` (удаление всех значений) (`One.php:724-774,1158-1339`).
* Валидатор `src/App/Component/Validation/Validator/Customer/AdditionalFields.php:19-60`:
  все обязательные поля учреждения должны иметь строку в `Values`.

---

## 9. База данных

### 9.1 Таблицы, пишущиеся при создании

| # | Таблица (миграция) | Колонки |
|---|---|---|
| 1 | `customers` (`1.0.0/customers.php`) | `id bigserial PK, institutionId int FK institutions, iin varchar(20), iinFileId bigint FK files, lastName/firstName varchar(45) NOT NULL, middleName varchar(45), birthDate date NOT NULL, citizenshipCountryId FK countries, regionId FK regions, codeword varchar(25), phones/email varchar(50), isSigned/isDeleted bool NOT NULL default false, createdAt/updatedAt timestamptz NOT NULL default now, createdBy/lastUpdatedBy varchar(50) NOT NULL, rstkId bigint, note text, byPassIin bool default false, deliveryInstitutionId int default -1`. Индексы по `createdAt, citizenshipCountryId, iin, iinFileId, institutionId, regionId, rstkId`. Все FK `CASCADE`. |
| 2 | `customer_documents` (`1.0.0/customer_documents.php`) + `customer_document_files` (`1.0.0/customer_document_files.php`) | `customer_documents{id bigserial, customerId FK NOT NULL, customerDocumentTypeId FK NOT NULL, docSeries(15), docNumber(20) NOT NULL, validFrom date NOT NULL, validUntil date, issuedBy(200) NOT NULL, note(100), isDeleted/isPrimary bool NOT NULL, createdAt/By}` + связка `{fileId FK files, customerDocumentId FK}`. |
| 3 | `customer_addresses` (`1.0.0/customer_addresses.php`) | `{id bigserial, customerId FK NOT NULL, name varchar(255), updatedAt timestamptz NOT NULL, lastUpdatedBy(50) NOT NULL}`. Триггер `on_update_current_timestamp_updatedat` (также на `customers`). |
| 4 | `inst_add_fields_values` (`2.0.2/inst_add_fields_values.php`) | `{customerId, instAddFieldId FK inst_add_fields, value}`; определение в `inst_add_fields` (`2.0.2/inst_add_fields.php`), типы `2.0.1/2.0.3`, списки `2.0.2/inst_add_fields_list.php`. |
| 5 | `customer_concessions` (`1.0.0/customer_concessions.php`) + `customer_concessions_tree` (`1.2.0/customer_concessions_tree.php`) | `customer_concessions{id bigserial, customerId FK NOT NULL, concessionId FK NOT NULL, isActive bool NOT NULL, activatedAt timestamptz NOT NULL, activatedBy(50) NOT NULL, startedAt date NOT NULL, expiresAt date, deactivatedAt timestamptz, deactivatedBy(50)}` (+ позже `isScheduled`); tree `{id bigserial, parentId FK customer_concessions NOT NULL UNIQUE, childId FK NOT NULL UNIQUE}`, оба `RESTRICT`. |
| 6 | `customer_photos` (`1.0.0/customer_photos.php`) | `{id bigserial, fileId FK files NOT NULL, customerId FK customers NOT NULL, isPrimary bool NOT NULL, name(100)}`. |
| 7 | `files` (`1.0.0/files.php`) | `{id bigserial, userId bigint, isLocked bool NOT NULL default true, createdAt/By, isDeleted bool NOT NULL, isUploaded bool}`. |
| side | `customer_card_print_jobs` (`1.0.0/customer_card_print_jobs.php`) | заполняется в `initiatePrintJob()`. |

Справочное чтение: `concessions{id,name(100) NOT NULL,minPeriod,maxPeriod,rstkValue,isHidden/canBlock bool} + showOnCreate` (`1.0.0/concessions.php` + поздняя дельта), `institution_type_concessions{institutionTypeId,concessionId}` (`1.0.0/institution_type_concessions.php`), `concession_costs{concessionId,cardTypeId,issueCost,reIssueCost}` (`1.0.0/concession_costs.php`), `concession_rules/groups/categories/subcategories` (`1.4.2/concession_rules.php`, `1.3.9`, `2.1.3`), `institutions/institution_types/cities/regions/countries`, `customer_document_types`, `customer_card_deliveries`.

### 9.2 Ограничения / индексы

* DB-уникальности на `customers.iin` нет — только обычный `idx_22194_iin`.
  Уникальность — валидатором приложения (`Entity\Customers`) → при конкурентных
  POST возможна гонка.
* `customer_concessions` индексирован только по `customerId/concessionId`; дерево
  требует `UNIQUE(parentId) + UNIQUE(childId)` (максимум один родитель / один потомок).
* Даты — тип `date`, метки — `timestamptz default CURRENT_TIMESTAMP`.

### 9.3 Триггеры / история / поиск

* `data/db/migrations/1.3.6/external_users.php:16-54`: `BEFORE DELETE ...
  EXECUTE backup_deleted()` на `customers, customer_concessions(+tree),
  customer_documents(+files/types), customer_photos, customer_addresses,
  customer_cards(+deliveries/print_jobs/transfers), customer_funds(+tx), ...`
  → копии строк в `census_history`. Изменения схемы требуют парной миграции
  истории (см. `readme.md §Triggers`).
* Аудит: `field_history_changes`, `actions_history`, `deleted_rows`;
  `Entity\Base.php:180-365` снимает `columnMap()/previousValues`.
* Поиск: `data/elasticsearch/census/mapping-customers.json`, индексация через
  `Component/Data/Customers.php:27,143`.

---

## 10. Риски / пробелы

1. `!empty(institutionConcessions)` считает `0/'0'` отсутствием — утверждение
   фронтендового §9 «период сохраняется даже для 0» на бэкенде неверно.
2. Необёрнутый `Carbon::createFromFormat` (допполя, `customerConcessionExpiresAt`)
   → 500 при плохой дате; расчёт на фронтендовый `date_format:d.m.Y`.
3. `byPassIin` пропускает checksum, но сохраняет уникальность; persists только как
   `customers.byPassIin`, отдельного аудита нет.
4. Заблокированные-сироты файлов при откате транзакции до `unlockFiles()`.
5. `echo` в egov-колбэке ИИН; обход валидации льгот при `Cli && !isActive`
   (крон) — проверить шум логов/мониторинга.
6. Фронтендовый кеш (`reg_user_*` 120 мин) против отсутствия кеша на бэкенде —
   возможны протухшие дескрипторы льгот/учреждений.
7. Уникальность ИИН без DB-ограничения — при дублях добавить частичный уникальный
   индекс `WHERE isDeleted=false`.
