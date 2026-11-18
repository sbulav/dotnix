# Source-first documentation skill for English and Russian docs. Editorial
# basis: Diátaxis (one doc type per section), Ilyakhov & Sarycheva («Пиши,
# сокращай», «Ясно, понятно»), the Google and Microsoft style guides, and the
# structural tells from blader/humanizer that survive in technical prose.
# Model-invoked on purpose: it must fire whenever a doc is written or edited.
{
  name = "technical-writer";
  version = "2.0.0";
  description = "Technical documentation in English or Russian — writing, improving, reviewing: runbooks, READMEs, how-tos, reference, architecture docs, ADRs, postmortems, wiki pages. Use when writing or editing a doc, reviewing one, or removing slop, канцелярит or calques from one.";
  allowed-tools = [
    "Read"
    "Write"
    "Edit"
    "Grep"
    "Glob"
    "AskUserQuestion"
  ];
  content = ''
    Write for the engineer who will run the steps, make the decision, or work
    out how the system behaves. A sentence earns its place when it could only
    have been written with the **source** in view: a config, a manifest, a
    command's output. Depth comes from mechanics, conditions and consequences,
    never from volume.

    ## Working order

    1. **Fix the reader's task and the doc type.** A how-to, a reference, an explanation and a tutorial do different jobs; each section does one. Keep the language, format, form of address and author instructions already used in the repo or wiki space.
    2. **Find the sources.** Manifests, configs, pipelines, alert rules, scripts, tests, accepted ADRs, pinned versions, `--help` output. Take semantics from the product docs of the version in use. Where the text and a source disagree, report the disagreement and let the author decide which side is right. State the current state of a cluster, host or pipeline only from evidence you can see.
    3. **Check completeness.** Who acts, on what, under which condition, with what expected result. A material detail with no source goes into notes for the author. An example built on invented data is labelled as illustrative.
    4. **Apply the team's terms, then edit the prose.** Precedence for wording: author's instruction → team glossary → a few good neighbouring docs → the defaults below. Precedence for exact names and behaviour: config, interface, docs of the version in use.
    5. **Trace the result back to the sources.** Done when every command, parameter, path, unit, number, link, version and condition in the output is traced to a source or listed for the author. An edit keeps the degree of confidence, the meaning of warnings and the order of dependent steps; an edit that changes technical meaning carries a source reference or a check-me mark. Code, logs and configs stay verbatim unless the request says otherwise.

    ## What the reader needs

    **Runbook.** Open with the symptom: metric, numeric threshold, hold time, where the alert came from, a link to the alert rule. Then step → observable sign → action → the method's limit (when it lies or does not apply). For a state-changing operation give the affected environment, the rights needed and the way to confirm the result; the rollback where one exists. The exit criterion is a metric with a threshold and a hold time, where a weaker doc says "the system is stable". Close with escalation to a named recipient.

    **README or how-to.** The task and the minimum prerequisites, commands in working order, a way to check the result. Copyable text goes in code blocks; a placeholder gets an explanation beside it when its meaning is ambiguous.

    **Reference** (API, CLI, config options). Built from the source and exhaustive against it: every parameter with its type, default and effect, in the source's own order and names. One real invocation with its output.

    **Architecture and ADR.** Components, direction of flow, owner of each piece of state. The reason for a choice is given through real constraints and consequences. An ADR keeps the rejected options and their grounds when the source has them.

    **Postmortem.** A timeline with a time zone. Keep apart: the symptom, the users affected, the confirmed cause, the hypotheses, the recovery actions. A conclusion drawn from logs or graphs links to that evidence. Each next step has an owner and a ticket.

    **Wiki page.** Its two risks are that nobody finds it and that it rots.
    - The title reads like a search query: the concrete problem or object.
    - The first paragraph says who the page is for and which task it closes; ten seconds tell the reader whether they are in the right place.
    - Owner and a valid-as-of date; for a changing system, the version or date the page is true for.
    - Single source of truth: link to what the code, a config or a neighbouring page already states. A copy drifts from its original within a month.
    - A path through a UI is written as text beside any screenshot: screenshots go stale silently.
    - Stale content is marked or archived. A page that lies is worse than a missing one.

    ## Common defects

    The checklist for review and improvement:

    1. **Possibility where an instruction is meant.** "You can raise the limits", "it is worth checking" → at which sign, by how much, agreed with whom, confirmed by what.
    2. **Impersonal phrasing where the reader acts.** "The service should be restarted" → "restart the service". One form of address through the whole doc.
    3. **Nesting where the logic branches.** Five-level lists lose the reader. Keep lists flat; a branch becomes separate steps or a diagram.
    4. **A judgement where a sign is observable.** "Check that it is correct" → the field, the command, the status, the expected answer.
    5. **A method without its limits.** A step that can mislead under some condition says so in place.
    6. **A link to a name.** A dashboard is linked with its parameters, a rule by its file, a channel by URL. A parameterised dashboard says what to substitute.
    7. **Rotten links and numbers.** A threshold in the text equals the one in the config; a link opens a live object.
    8. **An unnamed recipient.** Escalation, approval and "ask the team" name the channel or the on-call role.
    9. **Mixed types.** Step-by-step instructions interleaved with how the system works serve neither reader. The explanation gets its own section or page.
    10. **A duplicate.** What another doc already holds becomes a link.

    ## Terms

    Exact spelling for API names, YAML fields, CLI, metrics, statuses, messages and UI labels. Backticks when the reader needs to find, match or copy the exact string. One term per concept in prose. An abbreviation is expanded on first use.

    ## Prose

    - Open with the action or the fact. A sentence that keeps its meaning without its opener loses the opener: "It is important to note that X" → "X"; "in order to" → "to".
    - A general judgement becomes an observable sign. Uncertainty stays where the evidence does not support a conclusion.
    - Context goes where it changes a decision: a characteristic symptom, a short sample of output. Conditions, exceptions and numeric bounds survive every cut.
    - A repeat is cut whole. Terms, headings, lists and warnings stay where they help the reader find an object or choose an action.
    - "Not just X, but Y" → state Y.
    - A triad of near-synonyms ("fast, reliable and scalable") → the one property the source supports, with its number.
    - A trailing clause of benefit ("…, ensuring consistency") → the mechanism as its own sentence, or nothing.
    - "Serves as", "acts as", "provides a way to" → "is", or the verb itself.
    - The doc ends on its last fact. Promises of benefit, greetings in the body, praise of a technology without a fact and summaries of the previous paragraph carry nothing; an author's own live phrasing stays when it is accurate.
    - Headings and bullets are plain text; bold is for UI labels and warnings.

    ## Русскоязычная дока

    Регистр внутренней доки — язык инженерного ревью: знакомые термины, конкретные глаголы. Правила выше действуют целиком; ниже — то, что есть только в русском.

    **Обращение.** Инфинитив и безличность → повелительное: «выяснить», «необходимо написать» → «выясни», «подставь». Одно обращение (ты или вы) на весь документ — то, что принято в соседних доках.

    **Канцелярит и приметы ИИ-текста.**
    - «В рамках», «стоит отметить», «на сегодняшний день» уходят, если без них смысл тот же. «Осуществить проверку» → «проверить»; «является», «представляет собой», «выступает в роли» → тире или глагол; «данный» → «этот» или ничего.
    - «Не просто X, а Y» → назови Y. Тройка однородных («быстро, надёжно и масштабируемо») → одно свойство с числом из источника.
    - Хвост с пользой («…, обеспечивая отказоустойчивость», «…, что позволяет…») → механизм отдельным предложением или ничего.
    - Частота стоп-слов и балл «Главреда» подсказывают место для перечитывания; качество определяй по ясности и точности.

    **Глоссарий.** Английское написание — для имён API, полей YAML, CLI, метрик, статусов, сообщений и подписей интерфейса. Термина нет в глоссарии — подбери форму по контексту и языку команды.

    *Kubernetes и Linux*

    - `namespace` → неймспейс в связном тексте, `ns` в коротких шагах и подписях. `Namespace`, `metadata.namespace`, `kubectl get ns`, `-n` — в точных примерах. «Пространства имён» уместно как подпись раздела UI, если она там так и называется.
    - `Pod` / `Node` → под / нода; «узел» допустим, где так принято. Имена видов ресурсов сохраняй. Различай под, контейнер, ноду и процесс, когда это влияет на вывод.
    - `scheduler` → шедулер; `kube-scheduler`, если важен компонент. Для Linux — планировщик ядра или планировщик задач. Для `CronJob` часто яснее «запуск по расписанию».
    - `label` / `selector` / `annotation` → лейбл или метка, селектор, аннотация. Называй, что именно выбирается: «Service выбирает поды с лейблом `app=api`». Поля `metadata.labels`, `spec.selector`, `metadata.annotations` — дословно.
    - `Deployment`, `Service`, `ConfigMap`, `Secret`, `NetworkPolicy` → точные имена для объектов API. «Сервис» — про приложение, «секрет» — про чувствительное значение, «деплой» — про процесс доставки. Уточняй, если слово двусмысленно.
    - `rollout` / `rollback` → раскатка, выкат или обновление; откат для возврата. `RollingUpdate` — имя стратегии. Успешный rollout и успешный запрос к API — разные проверки.
    - Пробы → readiness-проба, liveness-проба, startup-проба. В конфиге — `readinessProbe`, `livenessProbe`, `startupProbe`.

    *CI/CD и GitOps*

    - `pipeline`, `job`, `runner`, `stage` → пайплайн, джоба или задача CI, раннер, этап. В GitHub и Forgejo Actions различай `workflow`, `job`, `step`. Имена файлов, ключей, джоб и кнопок — как в системе.
    - `build`, `deploy`, `release` → сборка, деплой, релиз. Уточняй предмет: «собирает образ», «деплоит приложение», «создаёт релиз Helm».
    - Helm → чарт, values, релиз. `values.yaml`, имя релиза и версию чарта сохраняй, когда на них ссылается инструкция.
    - Argo CD → синхронизация в обычной доке, синк в коротких шагах. Подписи UI (`Sync`, `OutOfSync`, `Synced`) и виды ресурсов (`Application`, `ApplicationSet`, `AppProject`) — точно. Различай sync status и health status.

    *Мониторинг*

    - Условие, сработка, доставка — разные вещи. Уточняй, сработало ли правило, перешёл ли алерт в `firing` и ушло ли уведомление дежурному. В Okmeter условие называется триггером; в Prometheus и Grafana — правилом.
    - `target`, `scrape`, `dashboard` → таргет или цель сбора, сбор метрик (скрейп — рядом с настройкой конкретного сбора), дашборд. Названия метрик, лейблов, разделов и параметров — дословно.
    - `observability` → наблюдаемость как понятие. Если абзац описывает систему, назови сигналы и маршрут: «Vector читает логи контейнеров и отправляет их в Kafka» — когда маршрут подтверждён.

    ## Example edits

    Each rewrite uses only what the named source shows; the gap goes to the author.

    **README.** Before: "This tool provides a powerful and flexible way to manage deployments, ensuring reliability at scale." Source: `main.go` defines one subcommand, `apply`, which renders `values/<env>.yaml` and calls `helm upgrade --install` per entry in `charts.yaml`.

    > `deployctl apply <env>` renders `values/<env>.yaml` and runs `helm upgrade --install` for each chart listed in `charts.yaml`.

    **Runbook step.** Before: "If the issue persists, consider restarting the service and verify that everything is working correctly." Source: the unit is `api.service`; the load balancer config probes `/healthz` on port 8080.

    > If `/healthz` still returns 503 two minutes after the deploy, run `systemctl restart api.service`. Done when `curl -fsS localhost:8080/healthz` exits 0.

    Note to the author: the sources show no rollback; add one or state that the restart is safe to repeat.

    **Ранбук.** Было: «В случае возникновения проблем с запуском пода осуществите диагностику и ознакомьтесь с сообщением планировщика». Соседние шаги про `Pending` и `FailedScheduling`, рядом команда `kubectl describe pod`.

    > Если под завис в `Pending`, выполни `kubectl describe pod <pod> -n <ns>` и посмотри раздел `Events`. Есть `FailedScheduling` — читай сообщение шедулера в этом событии.

    **Неопределённый шаг.** Было: «Можно временно поднять CPU, можно добавить инстансов».

    > Если утилизация CPU у квоты и растёт троттлинг — подними квоту, указав сервис, текущее и целевое значение. Если троттлинга нет, а потоки заняты — добавляй инстансы; для Python вместе с CPU увеличь число воркеров.

    **CI.** Было: «В рамках пайплайна выполняется автоматизированное создание артефакта с последующим размещением в хранилище». Конфиг показывает, что джоба собирает и пушит образ.

    > Джоба `build-image` собирает образ, пушит его в registry и обновляет тег в `values.yaml`.

    **GitOps.** Было: «В случае обнаружения отклонения система автоматически производит актуализацию целевого состояния». В `Application` включён auto-sync, self-heal выключен.

    > Новая ревизия в Git запускает автосинхронизацию, если приложение перешло в `OutOfSync`. Ручные правки в кластере её сами по себе не запускают.

    **Мониторинг.** Было: «При нарушении штатного функционирования автоматически отправляется оповещение». В правиле — условие `up == 0` и `for: 5m`.

    > Алерт переходит в `firing`, если для таргета `up == 0` держится 5 минут.

    Замечание автору: укажи, куда уходит уведомление и кто дежурный получатель.

    ## Output

    - **Edit**: return the finished text or change the file. Add short notes only for a material disagreement with a source or for missing data.
    - **Review**: lead with the findings that affect an engineer's understanding and actions. Place → problem → proposed wording. One finding per recurring terminology pattern.
    - **Improving an existing doc**: disagreements with sources and dead links first, then vague steps, then prose. Section structure and titles stay as they are unless agreed separately. Close with a short list of what is left for the author.
  '';
}
