# JAMbo
Groovebox для iPad — веб-прототип (TypeScript + Vite). Описание и план — в `CLAUDE.md`.

## Запуск
```
npm install
npm run dev      # локальный сервер (--host, можно открыть с iPad в той же сети)
npm run build    # сборка в dist/
```

## GitHub Pages
Workflow `.github/workflows/pages.yml` при пуше в `main` или `stage-1` собирает проект и кладёт `dist` в ветку `gh-pages`.
Один раз в настройках репозитория: Settings → Pages → Source: **Deploy from a branch**, Branch: **gh-pages** / **(root)**.
Адрес: https://djptrvch.github.io/JAMbo/
