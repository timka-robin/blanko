# Релизный процесс

## Один раз

```sh
gh auth login            # если ещё не авторизован
./scripts/build.sh       # проверить, что сборка проходит
./scripts/install.sh     # поставить локально и проверить в Finder
```

## Выпуск версии

```sh
./scripts/release.sh 1.1.0 "Добавлены горячие клавиши" --push
```

Что произойдёт:

- версия проставится в `Resources/Info-app.plist` и `Resources/Info-appex.plist`
  (`CFBundleShortVersionString` и `CFBundleVersion`);
- соберётся universal-бандл (arm64 + x86_64) и подпишется ad-hoc;
- появится `dist/NewFile.app.zip` и его SHA-256;
- `update.json` с этой версией, ссылкой на ассет и контрольной суммой будет
  закоммичен в ветку `release`;
- ветки `main` и `release` уедут в GitHub, появится тег `vX.Y.Z`;
- создастся GitHub Release с приложенным `NewFile.app.zip`.

Проверка на другой машине:

```sh
curl -L -O https://github.com/timka-robin/newfilemac/releases/latest/download/NewFile.app.zip
unzip NewFile.app.zip
./Установить.command        # или двойной клик по этому файлу
```

В архиве лежат `NewFile.app` и `Установить.command`. Приложение специально
остаётся в корне архива — так его находит автообновление.

## Обновление у пользователей

Приложение само читает `update.json` из ветки `release`
(`raw.githubusercontent.com`, с резервными адресами) и предлагает обновиться,
если версия в манифесте новее установленной. Безопасность: архив скачивается с
GitHub Releases, SHA-256 сверяется с манифестом, идентификатор бандла
проверяется перед подменой.

## Откат

```sh
git checkout release
git revert <commit>      # или вернуть предыдущий update.json
git push origin release
```

Пользователи, у которых уже стоит новая версия, автоматически не откатятся —
для отката нужно выпустить версию с большим номером.
