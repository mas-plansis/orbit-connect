# Orbit Connect Network Control

Системное расширение реализует режим «Только через доверенный выход» через
macOS Network Extension Content Filter.

Политика и короткоживущее подтверждение маршрута хранятся в App Group
`group.io.orbit.connect`. Источник потока определяется по audit token и подписи
кода. Защищённые потоки проверяются при создании и при каждом фрагменте входящих
и исходящих данных.

`scripts/build-app.sh` вкладывает расширение в:

```text
OrbitConnect.app/Contents/Library/SystemExtensions/
└── io.orbit.status.network-filter.systemextension
```

Скрипт сначала подписывает расширение, затем приложение-контейнер. Ad-hoc
подпись предназначена только для локальной проверки состава. Реальная активация
требует доверенной подписи и provisioning profiles с разрешёнными Apple
entitlements.
